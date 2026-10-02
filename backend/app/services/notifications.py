"""Notification matrix (F-X-01, contract §Notifications) and delivery.

``MATRIX`` is the data: event -> recipient roles -> channels. :func:`emit` resolves the roles
to users of one household, writes one ``InboxItem`` per user (the inbox is the source of
truth) and queues a push in ``push_outbox`` in the same transaction; after commit the
worker delivers it through the configured :class:`PushAdapter` (``NoopPush`` in dev and
tests, ``FcmPush`` in prod; see ``app.services.push_outbox``). Push respects the user's
per-event switch and quiet hours;
mandatory events (ticket assigned/updated for the assignee, approvals) ignore both (F-X-01
footnote). The inbox row is always written.

The actor who caused an event is never notified about it.
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import datetime, time
from enum import StrEnum
from typing import Any, Protocol
from zoneinfo import ZoneInfo

import httpx
import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import (
    Cook,
    CookLoginMode,
    Device,
    Household,
    HouseholdMembership,
    InboxItem,
    MembershipStatus,
    NotificationPref,
    PushOutbox,
    Ticket,
)
from app.models.base import utcnow

log = structlog.get_logger(__name__)


class Role(StrEnum):
    assignee = "assignee"
    confirmer = "confirmer"
    admin = "admin"
    # Eligible approvers for a stock issue / swap (§2.1): admins and adult members.
    approvers = "approvers"
    primary = "primary"
    backup = "backup"
    # Whoever raised the request being decided (ration raiser, approval requester, export).
    requester = "requester"


class Channel(StrEnum):
    push = "push"
    inbox = "inbox"


BOTH: tuple[Channel, ...] = (Channel.push, Channel.inbox)


@dataclass(frozen=True, slots=True)
class EventRule:
    roles: tuple[Role, ...]
    channels: tuple[Channel, ...] = BOTH
    # Cannot be switched off and ignores quiet hours.
    mandatory: bool = False
    # From the contract matrix (False = additive event, see README).
    in_contract: bool = True


MATRIX: dict[str, EventRule] = {
    "ticket_created": EventRule((Role.assignee,), mandatory=True),
    "ticket_accepted": EventRule((Role.confirmer,)),
    "ticket_updated": EventRule((Role.assignee,), mandatory=True),
    "ticket_unassigned": EventRule((Role.admin,)),
    "ticket_completed": EventRule((Role.confirmer, Role.admin)),
    "not_confirmed_prompt": EventRule((Role.admin,), mandatory=True),
    "cook_off_duty": EventRule((Role.admin,)),
    # F-5.7-12 / F-X-01: the backup cook hears about a no-show too (she may step in).
    "no_show": EventRule((Role.admin, Role.backup)),
    "stock_issue": EventRule((Role.admin, Role.approvers), mandatory=True),
    "ration_request": EventRule((Role.admin,)),
    "tomorrow_tickets": EventRule((Role.assignee,)),
    # Phase 6-7 contract rows.
    "stock_low": EventRule((Role.admin,)),
    "ration_decided": EventRule((Role.requester,)),
    "approval_request": EventRule((Role.approvers,), mandatory=True),
    "approval_decided": EventRule((Role.requester,), mandatory=True),
    "stock_issue_timeout": EventRule((Role.admin,), mandatory=True),
    "rate_prompt": EventRule((Role.confirmer, Role.admin)),
    "expiry_reminder": EventRule((Role.admin,)),
    "weekly_summary": EventRule((Role.admin,)),
    # Additive events (F-X-01 rows the contract matrix does not list).
    "ticket_cancelled": EventRule((Role.assignee,), in_contract=False),
    "cook_message": EventRule((Role.admin, Role.confirmer), in_contract=False),
    "family_message": EventRule((Role.assignee,), in_contract=False),
    "chef_claimed": EventRule((Role.admin, Role.primary), in_contract=False),
    "cook_on_duty": EventRule((Role.admin,), in_contract=False),
    "ration_bought": EventRule((Role.requester,), in_contract=False),
    "stock_issue_resolved": EventRule((Role.admin,), in_contract=False),
    "export_ready": EventRule((Role.requester,), channels=(Channel.inbox,), in_contract=False),
    # F-5.7-12: accepted but not cooking shortly before due (per-slot threshold).
    "at_risk": EventRule((Role.admin, Role.assignee), in_contract=False),
}

# (title, body) templates; params are filled with str.format_map (missing keys -> "").
TEMPLATES: dict[str, tuple[str, str]] = {
    "ticket_created": ("Naya ticket: {slot} {day}", "{dishes}. Kab tak: {due}."),
    "ticket_accepted": ("{cook} ne {slot} accept kiya", "{dishes}. Kab tak: {due}."),
    "ticket_updated": ("{slot} ticket badla gaya", "{changes}. Dobara dekh lijiye."),
    "ticket_unassigned": (
        "{slot} ({day}) ke liye koi cook nahi",
        "Ticket Unassigned hai. Kisi ko assign kijiye ya khud le lijiye.",
    ),
    "ticket_completed": ("{slot} ban gaya", "{dishes}. Rating dijiye."),
    "not_confirmed_prompt": ("Khaana bana?", "{slot} ({day}) complete nahi hua. Bataiye."),
    "cook_off_duty": ("{cook} off duty", "{until}{moved}"),
    "cook_on_duty": ("{cook} wapas on duty", "Aaj ke baaki tickets unhe dikhenge."),
    "no_show": (
        "{cook} ne abhi tak accept nahi kiya",
        "{slot} {due} tak chahiye. Reassign karein ya khud banayein.",
    ),
    "stock_issue": ("Saaman khatam: {item}", "{cook}: {slot} ke liye {item} nahi hai."),
    "ration_request": ("Ration request", "{cook} ne saaman maanga hai."),
    "tomorrow_tickets": ("Kal ke {count} ticket", "{summary}"),
    "ticket_cancelled": ("{slot} cancel", "{slot} ({day}) ab nahi banana. {reason}"),
    "cook_message": ("{author}: {slot}", "{text}"),
    "family_message": ("{author}: {slot}", "{text}"),
    "chef_claimed": ("{author} aaj {slot} banayenge", "{day}: Chef for the day."),
    "stock_low": ("Saaman kam: {item}", "{item}: {level}. Ration list mein jod dijiye."),
    "ration_decided": ("Ration request {decision}", "{items}. {note}"),
    "ration_bought": ("Saaman aa gaya", "{items} ab stock mein hai."),
    "approval_request": ("Manzoori chahiye: {slot}", "{what}. 30 min mein jawab dijiye."),
    "approval_decided": ("{what}: {decision}", "{slot} ({day})."),
    "stock_issue_timeout": (
        "Kisi ne jawab nahi diya: {slot}",
        "{item} khatam hai aur 30 min mein manzoori nahi mili. Ticket dekhiye.",
    ),
    "stock_issue_resolved": ("{slot}: {what}", "{cook} ne khud badla ({item} khatam tha)."),
    "rate_prompt": ("Khaana kaisa laga?", "{slot}: {dishes}. {eaters} ke liye rating dijiye."),
    "expiry_reminder": (
        "Trial {days_left} din mein khatam",
        "Plan chalu rakhne ke liye subscribe kijiye. Uske baad app sirf padhne ke liye.",
    ),
    "weekly_summary": ("Is hafte ki rasoi", "{summary}"),
    "export_ready": ("Aapka data tayyar hai", "Download: {link}"),
    "at_risk": (
        "{slot} abhi shuru nahi hua",
        "{cook} ne accept kiya hai par cooking shuru nahi hui. {due} tak chahiye.",
    ),
}


class _Blank(dict[str, Any]):
    def __missing__(self, key: str) -> str:
        return ""


def render(event: str, params: Mapping[str, Any]) -> tuple[str, str]:
    title, body = TEMPLATES.get(event, (event, ""))
    values = _Blank(params)
    return title.format_map(values)[:200], body.format_map(values).strip()


# ---- recipient resolution (pure) ----------------------------------------------------------


@dataclass(frozen=True, slots=True)
class Audience:
    """Who holds each role for one event. Resolution is pure so the matrix is unit-testable."""

    admins: tuple[uuid.UUID, ...] = ()
    members: tuple[uuid.UUID, ...] = ()
    assignee: tuple[uuid.UUID, ...] = ()
    confirmer: uuid.UUID | None = None
    primary: tuple[uuid.UUID, ...] = ()
    backup: tuple[uuid.UUID, ...] = ()
    requester: tuple[uuid.UUID, ...] = ()


def resolve(
    event: str, audience: Audience, actor_user_id: uuid.UUID | None = None
) -> list[uuid.UUID]:
    """Users to notify for ``event``, in role order, deduplicated, without the actor."""
    rule = MATRIX[event]
    out: list[uuid.UUID] = []
    for role in rule.roles:
        if role == Role.admin:
            out.extend(audience.admins)
        elif role == Role.approvers:
            out.extend(audience.admins)
            out.extend(audience.members)
        elif role == Role.assignee:
            out.extend(audience.assignee)
        elif role == Role.confirmer and audience.confirmer is not None:
            out.append(audience.confirmer)
        elif role == Role.primary:
            out.extend(audience.primary)
        elif role == Role.backup:
            out.extend(audience.backup)
        elif role == Role.requester:
            out.extend(audience.requester)
    seen: set[uuid.UUID] = set()
    result = []
    for uid in out:
        if uid in seen or uid == actor_user_id:
            continue
        seen.add(uid)
        result.append(uid)
    return result


def cook_users(cook: Cook | None, admins: Sequence[uuid.UUID]) -> tuple[uuid.UUID, ...]:
    """A cook's notifications go to her login; profile-only / WhatsApp-only cooks are run by
    the admin (F-2-03, F-5.6-03), so the admins get them."""
    if cook is None or cook.removed_at is not None:
        return ()
    if cook.login_mode == CookLoginMode.own and cook.user_id is not None:
        return (cook.user_id,)
    return tuple(admins)


async def household_roles(
    db: AsyncSession, household_id: uuid.UUID
) -> tuple[tuple[uuid.UUID, ...], tuple[uuid.UUID, ...]]:
    rows = (
        await db.execute(
            select(
                HouseholdMembership.user_id,
                HouseholdMembership.is_admin,
                HouseholdMembership.is_member,
            ).where(
                HouseholdMembership.household_id == household_id,
                HouseholdMembership.status == MembershipStatus.active,
            )
        )
    ).all()
    admins = tuple(r.user_id for r in rows if r.is_admin)
    members = tuple(r.user_id for r in rows if r.is_member and not r.is_admin)
    return admins, members


async def build_audience(
    db: AsyncSession,
    household: Household,
    *,
    ticket: Ticket | None = None,
    assignee: Cook | None = None,
    requester: uuid.UUID | None = None,
) -> Audience:
    admins, members = await household_roles(db, household.id)
    cooks = list(
        (
            await db.execute(
                select(Cook).where(Cook.household_id == household.id, Cook.removed_at.is_(None))
            )
        ).scalars()
    )
    if assignee is None and ticket is not None and ticket.assignee_cook_id is not None:
        assignee = next((c for c in cooks if c.id == ticket.assignee_cook_id), None)
    primary = next((c for c in cooks if c.is_primary), None)
    backup = next((c for c in cooks if c.is_backup), None)
    return Audience(
        admins=admins,
        members=members,
        assignee=cook_users(assignee, admins),
        confirmer=ticket.confirmed_by_user_id if ticket is not None else None,
        primary=cook_users(primary, admins),
        backup=cook_users(backup, admins),
        requester=(requester,) if requester is not None else (),
    )


# ---- push adapters ------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class PushMessage:
    user_id: uuid.UUID
    tokens: tuple[tuple[str, str], ...]  # (platform, token)
    title: str
    body: str
    data: Mapping[str, str] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class PushResult:
    """Per-device outcome. ``dead``: tokens the provider says are gone (their Device rows are
    deleted); ``retry``: (platform, token) pairs that failed transiently (only those are
    retried, with backoff, by the outbox). Everything else was delivered or dropped."""

    dead: tuple[str, ...] = ()
    retry: tuple[tuple[str, str], ...] = ()


class PushAdapter(Protocol):
    async def send(self, message: PushMessage) -> PushResult | None: ...


class NoopPush:
    """Dev/test adapter: logs and remembers what would have been sent."""

    def __init__(self) -> None:
        self.sent: list[PushMessage] = []

    async def send(self, message: PushMessage) -> PushResult | None:
        self.sent.append(message)
        log.info(
            "push_noop",
            user_id=str(message.user_id),
            devices=len(message.tokens),
            title=message.title,
            notification=message.data.get("event"),
        )
        return None


FCM_URL = "https://fcm.googleapis.com/v1/projects/{project}/messages:send"
# Android notification channel created by the app (core/push/push_messaging.dart).
ANDROID_CHANNEL_ID = "banega_alerts"


class FcmPush:
    """FCM HTTP v1 (Android; iOS through APNs once there is an iOS app).

    One ``messages:send`` per device token with a ``notification`` (title, body), ``data``
    (``event``, ``ticket_id``, ... as strings, read by the app on tap) and Android priority
    high. OAuth2 access token from the service account (``google_sa``). Outcomes per token:
    200 delivered; ``UNREGISTERED`` / 404, ``SENDER_ID_MISMATCH`` and an ``INVALID_ARGUMENT``
    about the token -> dead (Device row deleted); 401/429/5xx/network -> retried by the
    outbox; any other 4xx -> dropped and logged (retrying the same payload cannot help).
    """

    def __init__(
        self,
        project_id: str,
        tokens: Any,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        timeout: float = 10.0,
    ) -> None:
        self.project_id = project_id
        self.tokens = tokens  # google_sa.TokenSource
        self.transport = transport
        self.timeout = timeout

    @classmethod
    def from_settings(cls) -> FcmPush:
        from app.services import google_sa

        s = get_settings()
        info = google_sa.load_service_account(
            s.FCM_SERVICE_ACCOUNT_FILE, s.FCM_SERVICE_ACCOUNT_JSON, "FCM"
        )
        project = s.FCM_PROJECT_ID or str(info.get("project_id") or "")
        if not project:
            raise google_sa.ServiceAccountError("FCM_PROJECT_ID is not set")
        return cls(project, google_sa.GoogleTokenSource(info, [google_sa.FCM_SCOPE]))

    def payload(self, token: str, message: PushMessage) -> dict[str, Any]:
        data = {str(k): str(v) for k, v in message.data.items() if not str(k).startswith("_")}
        return {
            "message": {
                "token": token,
                "notification": {"title": message.title, "body": message.body},
                "data": data,
                "android": {
                    "priority": "high",
                    # Matches the app's high-importance channel, so the alert
                    # rings and pops up even with the app in the background.
                    "notification": {
                        "channel_id": ANDROID_CHANNEL_ID,
                        "default_sound": True,
                        "notification_priority": "PRIORITY_HIGH",
                    },
                },
                "apns": {"headers": {"apns-priority": "10"}},
            }
        }

    async def send(self, message: PushMessage) -> PushResult | None:
        access = await self.tokens.token()
        url = FCM_URL.format(project=self.project_id)
        async with httpx.AsyncClient(
            timeout=self.timeout,
            transport=self.transport,
            headers={"Authorization": f"Bearer {access}"},
        ) as client:
            outcomes = await asyncio.gather(
                *(self._one(client, url, token, message) for _, token in message.tokens)
            )
        dead = tuple(t for (_, t), o in zip(message.tokens, outcomes, strict=True) if o == "dead")
        retry = tuple(p for p, o in zip(message.tokens, outcomes, strict=True) if o == "retry")
        return PushResult(dead=dead, retry=retry)

    async def _one(
        self, client: httpx.AsyncClient, url: str, token: str, message: PushMessage
    ) -> str:
        try:
            resp = await client.post(url, json=self.payload(token, message))
        except httpx.HTTPError as exc:
            log.warning("fcm_unreachable", error=type(exc).__name__)
            return "retry"
        if resp.is_success:
            return "ok"
        outcome = classify_fcm_error(resp)
        log.warning(
            "fcm_send_failed",
            status=resp.status_code,
            outcome=outcome,
            notification=message.data.get("event"),
        )
        return outcome


def classify_fcm_error(resp: httpx.Response) -> str:
    """dead | retry | drop for a non-2xx FCM v1 response."""
    try:
        err = resp.json().get("error") or {}
    except (ValueError, AttributeError):
        err = {}
    codes: set[str] = set()
    fields: set[str] = set()
    for d in err.get("details") or []:
        if isinstance(d, dict):
            if d.get("errorCode"):
                codes.add(str(d["errorCode"]))
            for v in d.get("fieldViolations") or []:
                if isinstance(v, dict):
                    fields.add(str(v.get("field") or ""))
    status = str(err.get("status") or "")
    if "UNREGISTERED" in codes or "SENDER_ID_MISMATCH" in codes or resp.status_code == 404:
        return "dead"
    if "INVALID_ARGUMENT" in codes or status == "INVALID_ARGUMENT" or resp.status_code == 400:
        about_token = "message.token" in fields or "token" in str(err.get("message", "")).lower()
        return "dead" if about_token else "drop"
    if resp.status_code in (401, 408, 429) or resp.status_code >= 500:
        return "retry"
    return "drop"


_push: PushAdapter | None = None


def get_push() -> PushAdapter:
    global _push
    if _push is None:
        s = get_settings()
        _push = FcmPush.from_settings() if s.PUSH_PROVIDER == "fcm" else NoopPush()
    return _push


def set_push(adapter: PushAdapter | None) -> None:
    global _push
    _push = adapter


# ---- preferences --------------------------------------------------------------------------

QUIET_HOURS_EVENT = "*"


def in_quiet_hours(quiet: Mapping[str, Any] | None, now: datetime, tz: str) -> bool:
    if not quiet:
        return False
    try:
        start = time.fromisoformat(str(quiet["start"]))
        end = time.fromisoformat(str(quiet["end"]))
    except (KeyError, ValueError):
        return False
    local = now.astimezone(ZoneInfo(tz or "Asia/Kolkata")).time()
    if start <= end:
        return start <= local < end
    return local >= start or local < end


async def _prefs(
    db: AsyncSession, user_ids: Iterable[uuid.UUID]
) -> dict[uuid.UUID, dict[str, NotificationPref]]:
    ids = list(user_ids)
    out: dict[uuid.UUID, dict[str, NotificationPref]] = {uid: {} for uid in ids}
    if not ids:
        return out
    for p in (
        await db.execute(select(NotificationPref).where(NotificationPref.user_id.in_(ids)))
    ).scalars():
        out[p.user_id][p.event] = p
    return out


# ---- emit ---------------------------------------------------------------------------------


async def emit(
    db: AsyncSession,
    event: str,
    household: Household,
    *,
    ticket: Ticket | None = None,
    assignee: Cook | None = None,
    actor_user_id: uuid.UUID | None = None,
    params: Mapping[str, Any] | None = None,
    audience: Audience | None = None,
    recipients: Sequence[uuid.UUID] | None = None,
    requester: uuid.UUID | None = None,
    data: Mapping[str, Any] | None = None,
    now: datetime | None = None,
) -> list[InboxItem]:
    """Write inbox rows for everyone the matrix names and push to their devices."""
    rule = MATRIX[event]
    now = now or utcnow()
    if recipients is None:
        audience = audience or await build_audience(
            db, household, ticket=ticket, assignee=assignee, requester=requester
        )
        recipients = resolve(event, audience, actor_user_id)
    if not recipients:
        return []
    title, body = render(event, params or {})
    items = [
        InboxItem(
            household_id=household.id,
            user_id=uid,
            event=event,
            title=title,
            body=body,
            ticket_id=ticket.id if ticket is not None else None,
            data={k: str(v) for k, v in (data or {}).items() if v is not None},
            created_at=now,
        )
        for uid in recipients
    ]
    if Channel.inbox in rule.channels:
        db.add_all(items)
        await db.flush()
    if Channel.push in rule.channels:
        await _push_all(db, event, rule, household, recipients, title, body, ticket, now)
    return items


async def _push_all(
    db: AsyncSession,
    event: str,
    rule: EventRule,
    household: Household,
    recipients: Sequence[uuid.UUID],
    title: str,
    body: str,
    ticket: Ticket | None,
    now: datetime,
) -> None:
    """Queue pushes (outbox) for recipients with a device and push allowed; delivered after
    the transaction commits (app.services.push_outbox)."""
    from app.services import push_outbox

    prefs = await _prefs(db, recipients)
    with_device = set(
        (
            await db.execute(
                select(Device.user_id).where(Device.user_id.in_(list(recipients))).distinct()
            )
        ).scalars()
    )
    queued = False
    for uid in recipients:
        user_prefs = prefs.get(uid, {})
        if not rule.mandatory:
            pref = user_prefs.get(event)
            if pref is not None and not pref.enabled:
                continue
            quiet = user_prefs.get(QUIET_HOURS_EVENT)
            if quiet is not None and in_quiet_hours(quiet.quiet_hours, now, household.timezone):
                continue
        if uid not in with_device:
            continue
        data = {"event": event}
        if ticket is not None:
            data["ticket_id"] = str(ticket.id)
        db.add(
            PushOutbox(
                user_id=uid,
                household_id=household.id,
                event=event,
                title=title,
                body=body,
                data=data,
                created_at=now,
            )
        )
        queued = True
    if queued:
        await db.flush()
        push_outbox.mark_pending(db)
