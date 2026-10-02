"""Subscription lifecycle (FRD §3, FR-A6/A7 as amended by F-3-03 and F-5.1-05; contract
Phase 7).

- Trial: server-side, ``TRIAL_DAYS`` (7) from household creation, one per phone number and
  device id (a second household from the same phone or device starts ``expired``).
- ``trial -> active`` (store purchase / restore / webhook), ``active -> grace`` when the
  renewal date passes without a renewal (``grace_until = renews_at + 3 days``, full access and
  a banner), ``grace -> expired``, and ``expired -> active`` on a later purchase.
- Expired = read-only (``enforce``): no new menus, chats or tickets; tickets for today and
  tomorrow stay workable (transitions, item out, stock issue, messages), F-5.1-05.
- Store verification sits behind :class:`StoreVerifier`: ``FakeStoreVerifier`` in dev/test
  (a stub receipt is valid unless it starts with "invalid"); ``StoreApiVerifier`` in prod:
  Google Play via the Play Developer API (``purchases.subscriptionsv2.get`` with a service
  account; the purchase is acknowledged when Play says it is not yet), App Store still TODO
  (503). Each Play RTDN re-reads the authoritative state from the same API.
- Webhooks: Play RTDN (Pub/Sub push; shared secret in the ``X-Webhook-Secret`` header or the
  Pub/Sub OIDC bearer token) and App Store Server Notifications v2 (JWS; outside dev/test the
  x5c chain to Apple Root CA - G3 and the ES256 signature are verified by
  :class:`app.services.store_jws.AppleJwsDecoder`; the unverified decoder exists for dev/test
  only and ``appAccountToken`` is only used from a verified payload).
- Reminders: ``expiry_reminder`` to the admin on trial day 5 and day 7 at 10:00 local, once.
"""

from __future__ import annotations

import base64
import hashlib
import json
import math
import re
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, time, timedelta
from typing import Any, Protocol
from urllib.parse import quote
from zoneinfo import ZoneInfo

import httpx
import structlog
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.errors import AppError, Conflict
from app.models import (
    Household,
    Subscription,
    SubscriptionStatus,
    Ticket,
    User,
)
from app.models.base import utcnow
from app.services import notifications as notify
from app.services.store_jws import AppleJwsDecoder

log = structlog.get_logger(__name__)

S = SubscriptionStatus
GRACE_DAYS = 3
REMINDER_DAYS: tuple[int, ...] = (5, 7)
REMINDER_TIME = time(10, 0)
DEFAULT_PRODUCT = "banega_weekly_50"
WEEK = timedelta(days=7)


def subscription_expired(status: str = "expired") -> AppError:
    return AppError(
        "subscription_expired",
        "Your plan has ended. Subscribe to plan new meals.",
        "Plan khatam ho gaya hai. Naye khaane ke liye subscribe kijiye.",
        status_code=402,
        details={"status": status},
    )


# ---- state ------------------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class State:
    status: SubscriptionStatus
    grace_until: datetime | None


def effective(sub: Subscription, now: datetime) -> State:
    """Time-based transitions on top of the stored status (pure)."""
    status = sub.status
    grace_until = sub.grace_until
    if status == S.trial and sub.trial_ends_at is not None and now >= sub.trial_ends_at:
        status = S.expired
    if status == S.active and sub.renews_at is not None and now >= sub.renews_at:
        grace_until = sub.renews_at + timedelta(days=GRACE_DAYS)
        status = S.grace
    if status == S.grace:
        grace_until = grace_until or ((sub.renews_at or now) + timedelta(days=GRACE_DAYS))
        if now >= grace_until:
            status = S.expired
    return State(status, grace_until)


def refresh(sub: Subscription, now: datetime) -> bool:
    state = effective(sub, now)
    changed = state.status != sub.status or state.grace_until != sub.grace_until
    if changed:
        sub.status = state.status
        sub.grace_until = state.grace_until
    return changed


def view(sub: Subscription | None, now: datetime) -> dict[str, Any]:
    if sub is None:
        return {"status": "expired", "read_only": True}
    state = effective(sub, now)
    end = (
        sub.trial_ends_at
        if state.status == S.trial
        else state.grace_until
        if state.status == S.grace
        else None
    )
    days_left = max(0, math.ceil((end - now).total_seconds() / 86400)) if end else None
    return {
        "status": str(state.status),
        "trial_ends_at": sub.trial_ends_at,
        "renews_at": sub.renews_at,
        "grace_until": state.grace_until,
        "product_id": sub.product_id,
        "store": sub.store,
        "read_only": state.status == S.expired,
        "days_left": days_left,
    }


async def for_household(db: AsyncSession, household_id: uuid.UUID) -> Subscription | None:
    return (
        await db.execute(select(Subscription).where(Subscription.household_id == household_id))
    ).scalar_one_or_none()


async def start_trial(
    db: AsyncSession,
    household: Household,
    user: User,
    device_id: str | None,
    *,
    now: datetime | None = None,
) -> Subscription:
    """F-3-03: one trial per phone number and device id."""
    now = now or utcnow()
    conds = [Subscription.trial_phone == user.phone]
    if device_id:
        conds.append(Subscription.trial_device_id == device_id)
    used = (await db.execute(select(Subscription.id).where(or_(*conds)).limit(1))).first()
    days = get_settings().TRIAL_DAYS
    sub = Subscription(
        household_id=household.id,
        status=S.expired if used else S.trial,
        trial_ends_at=now if used else now + timedelta(days=days),
        trial_phone=user.phone,
        trial_device_id=device_id,
    )
    db.add(sub)
    if used:
        log.info("trial_already_used", household_id=str(household.id))
    return sub


async def is_read_only(db: AsyncSession, household: Household, now: datetime | None = None) -> bool:
    sub = await for_household(db, household.id)
    return bool(view(sub, now or utcnow())["read_only"])


# ---- read-only enforcement (F-5.1-05) ------------------------------------------------------

WRITE_METHODS = frozenset({"POST", "PUT", "PATCH", "DELETE"})
# Writes that never run on an expired plan: new menus, chats, tickets (via confirm), edits.
_BLOCKED = (
    ("/v1/menus", None),
    ("/v1/chat", None),
)
# Ticket actions kept for today's / tomorrow's tickets (the cook finishes what was planned).
_TICKET_WORK = ("transitions", "items", "stock-issue", "messages")


def _ticket_route(path: str) -> tuple[str | None, str | None]:
    parts = path.strip("/").split("/")
    # v1 / tickets / {id} / action...
    if len(parts) >= 3 and parts[0] == "v1" and parts[1] == "tickets":
        return parts[2], parts[3] if len(parts) > 3 else None
    return None, None


async def enforce(
    db: AsyncSession, household: Household, method: str, path: str, now: datetime | None = None
) -> None:
    """402 ``subscription_expired`` for writes an expired household may not make."""
    if method not in WRITE_METHODS:
        return
    blocked = any(path.startswith(prefix) for prefix, _ in _BLOCKED)
    ticket_id, action = _ticket_route(path)
    if not blocked and ticket_id is None:
        return
    now = now or utcnow()
    sub = await for_household(db, household.id)
    state = view(sub, now)
    if not state["read_only"]:
        return
    if blocked:
        raise subscription_expired()
    if action in _TICKET_WORK:
        try:
            ticket = await db.get(Ticket, uuid.UUID(ticket_id or ""))
        except ValueError:
            ticket = None
        if ticket is not None and ticket.household_id == household.id:
            today = now.astimezone(ZoneInfo(household.timezone or "Asia/Kolkata")).date()
            if today <= ticket.date <= today + timedelta(days=1):
                return
    raise subscription_expired()


# ---- store adapters --------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class StoreState:
    status: SubscriptionStatus
    renews_at: datetime | None
    product_id: str
    original_transaction_id: str | None = None
    purchase_token: str | None = None
    # Play: the token this purchase replaced (resubscribe / plan change).
    linked_purchase_token: str | None = None


class StoreVerifier(Protocol):
    async def verify(
        self,
        store: str,
        *,
        receipt: str | None,
        purchase_token: str | None,
        product_id: str | None,
        now: datetime,
    ) -> StoreState: ...


def _receipt_invalid() -> AppError:
    return AppError(
        "receipt_invalid",
        "The store could not confirm this purchase.",
        "Store ne is kharid ki pushti nahi ki.",
        status_code=422,
    )


class FakeStoreVerifier:
    """Dev/test: any non-empty receipt / token is a weekly purchase renewing in 7 days."""

    async def verify(
        self,
        store: str,
        *,
        receipt: str | None,
        purchase_token: str | None,
        product_id: str | None,
        now: datetime,
    ) -> StoreState:
        proof = purchase_token if store == "play" else receipt
        if not proof or proof.startswith("invalid"):
            raise _receipt_invalid()
        digest = hashlib.sha256(proof.encode()).hexdigest()[:24]
        return StoreState(
            status=S.active,
            renews_at=now + WEEK,
            product_id=product_id or DEFAULT_PRODUCT,
            original_transaction_id=f"fake-{digest}" if store == "app_store" else None,
            purchase_token=proof if store == "play" else None,
        )


def _store_unavailable() -> AppError:
    return AppError(
        "store_verification_unavailable",
        "Purchase verification is not available right now. Please try again.",
        "Kharid ki jaanch abhi nahi ho paayi. Thodi der baad try kijiye.",
        status_code=503,
    )


def _store_not_supported() -> AppError:
    return AppError(
        "store_not_supported",
        "Purchases from this store are not supported yet.",
        "Is store ki kharid abhi support nahi hai.",
        status_code=422,
    )


def _purchase_pending() -> AppError:
    return AppError(
        "purchase_pending",
        "The payment is still pending. Your plan starts once it completes.",
        "Payment abhi pending hai. Poora hote hi plan shuru ho jayega.",
        status_code=409,
    )


PLAY_API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{package}"
# Google may send more than 6 fractional digits; fromisoformat takes at most 6.
_FRACTION = re.compile(r"\.(\d{6})\d+")


def _rfc3339(value: Any) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(_FRACTION.sub(r".\1", str(value)).replace("Z", "+00:00"))
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)


class PlayDeveloperApi:
    """Google Play Developer API v3 for one package: ``purchases.subscriptionsv2.get`` and
    ``purchases.subscriptions.acknowledge``, with a service-account token (scope
    androidpublisher)."""

    def __init__(
        self,
        package: str,
        product_ids: frozenset[str],
        tokens: Any,
        *,
        transport: httpx.AsyncBaseTransport | None = None,
        timeout: float = 10.0,
    ) -> None:
        self.package = package
        self.product_ids = product_ids
        self.tokens = tokens  # google_sa.TokenSource
        self.transport = transport
        self.timeout = timeout

    @classmethod
    def from_settings(cls) -> PlayDeveloperApi:
        from app.services import google_sa

        s = get_settings()
        info = google_sa.load_service_account(
            s.PLAY_SERVICE_ACCOUNT_FILE, s.PLAY_SERVICE_ACCOUNT_JSON, "PLAY"
        )
        return cls(
            s.PLAY_PACKAGE_NAME,
            s.play_product_ids,
            google_sa.GoogleTokenSource(info, [google_sa.PLAY_SCOPE]),
        )

    async def _request(self, method: str, path: str) -> httpx.Response:
        url = PLAY_API.format(package=quote(self.package, safe="")) + path
        try:
            access = await self.tokens.token()
            async with httpx.AsyncClient(
                timeout=self.timeout,
                transport=self.transport,
                headers={"Authorization": f"Bearer {access}"},
            ) as client:
                if method == "POST":
                    return await client.post(url, json={})
                return await client.get(url)
        except Exception as exc:  # network errors, token minting
            log.warning("play_api_unreachable", error=type(exc).__name__)
            raise _store_unavailable() from exc

    async def get(self, purchase_token: str) -> dict[str, Any]:
        resp = await self._request(
            "GET", f"/purchases/subscriptionsv2/tokens/{quote(purchase_token, safe='')}"
        )
        if resp.is_success:
            return dict(resp.json())
        log.warning("play_api_get_failed", status=resp.status_code)
        if resp.status_code in (400, 404, 410):
            raise _receipt_invalid()
        raise _store_unavailable()  # 401/403 (service-account access), 429, 5xx

    async def acknowledge(self, product_id: str, purchase_token: str) -> None:
        resp = await self._request(
            "POST",
            f"/purchases/subscriptions/{quote(product_id, safe='')}"
            f"/tokens/{quote(purchase_token, safe='')}:acknowledge",
        )
        if not resp.is_success:
            # The app acknowledges too (completePurchase); the next RTDN retries.
            log.warning("play_acknowledge_failed", status=resp.status_code)


# subscriptionsv2 subscriptionState -> our status (CANCELED keeps access until expiry).
PLAY_STATES: dict[str, SubscriptionStatus] = {
    "SUBSCRIPTION_STATE_ACTIVE": S.active,
    "SUBSCRIPTION_STATE_CANCELED": S.active,
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD": S.grace,
    "SUBSCRIPTION_STATE_ON_HOLD": S.expired,
    "SUBSCRIPTION_STATE_PAUSED": S.expired,
    "SUBSCRIPTION_STATE_EXPIRED": S.expired,
}


def play_state(
    data: dict[str, Any], purchase_token: str, product_ids: frozenset[str], now: datetime
) -> StoreState:
    """``SubscriptionPurchaseV2`` -> :class:`StoreState` (pure). Pending payments are 409
    ``purchase_pending``; cancelled-pending, unknown states and products we do not sell are
    422 ``receipt_invalid``."""
    state = str(data.get("subscriptionState") or "")
    if state == "SUBSCRIPTION_STATE_PENDING":
        raise _purchase_pending()
    status = PLAY_STATES.get(state)
    if status is None:
        raise _receipt_invalid()
    items = [i for i in data.get("lineItems") or [] if isinstance(i, dict)]
    ours = [i for i in items if not product_ids or i.get("productId") in product_ids]
    if not ours:
        log.warning("play_unknown_product", products=[str(i.get("productId")) for i in items])
        raise _receipt_invalid()
    expiries = [e for e in (_rfc3339(i.get("expiryTime")) for i in ours) if e is not None]
    expiry = max(expiries) if expiries else None
    if state == "SUBSCRIPTION_STATE_CANCELED" and (expiry is None or expiry <= now):
        status = S.expired
    return StoreState(
        status=status,
        renews_at=expiry,
        product_id=str(ours[0].get("productId") or DEFAULT_PRODUCT),
        purchase_token=purchase_token,
        linked_purchase_token=str(data.get("linkedPurchaseToken") or "") or None,
    )


class StoreApiVerifier:
    """Production verifier. Play: the Play Developer API (authoritative; acknowledges new
    purchases). App Store: TODO (App Store Server API ``/inApps/v1/subscriptions/{id}``)."""

    # The Play RTDN handler re-reads the state through this verifier.
    authoritative = True

    def __init__(self, play: PlayDeveloperApi | None = None) -> None:
        self._play = play

    @property
    def play(self) -> PlayDeveloperApi:
        if self._play is None:
            try:
                self._play = PlayDeveloperApi.from_settings()
            except Exception as exc:
                log.error("play_api_not_configured", error=type(exc).__name__)
                raise _store_unavailable() from exc
        return self._play

    async def verify(
        self,
        store: str,
        *,
        receipt: str | None,
        purchase_token: str | None,
        product_id: str | None,
        now: datetime,
    ) -> StoreState:
        if store == "play":
            if not purchase_token:
                raise _receipt_invalid()
            return await self.play_verify(purchase_token, now)
        if store == "app_store" and not get_settings().APPSTORE_ENABLED:
            raise _store_not_supported()
        raise _store_unavailable()

    async def play_verify(self, purchase_token: str, now: datetime) -> StoreState:
        api = self.play
        data = await api.get(purchase_token)
        state = play_state(data, purchase_token, api.product_ids, now)
        # Play refunds a purchase that is not acknowledged within 3 days.
        if data.get("acknowledgementState") == "ACKNOWLEDGEMENT_STATE_PENDING" and (
            state.status in (S.active, S.grace)
        ):
            await api.acknowledge(state.product_id, purchase_token)
        return state


_verifier: StoreVerifier | None = None


def get_verifier() -> StoreVerifier:
    global _verifier
    if _verifier is None:
        _verifier = FakeStoreVerifier() if use_fakes() else StoreApiVerifier()
    return _verifier


def set_verifier(v: StoreVerifier | None) -> None:
    global _verifier
    _verifier = v


def use_fakes() -> bool:
    """Fakes only ever in dev/test (the settings validator also refuses fake elsewhere)."""
    s = get_settings()
    if not s.is_dev:
        return False
    return s.STORE_VERIFIER in ("fake", "auto")


async def restore(
    db: AsyncSession,
    household: Household,
    *,
    store: str,
    receipt: str | None,
    purchase_token: str | None,
    product_id: str | None,
    now: datetime | None = None,
) -> Subscription:
    now = now or utcnow()
    store = "app_store" if store in ("appstore", "app_store") else store
    state = await get_verifier().verify(
        store, receipt=receipt, purchase_token=purchase_token, product_id=product_id, now=now
    )
    other = None
    if state.original_transaction_id or state.purchase_token:
        conds = []
        if state.original_transaction_id:
            conds.append(Subscription.original_transaction_id == state.original_transaction_id)
        if state.purchase_token:
            conds.append(Subscription.purchase_token == state.purchase_token)
        other = (
            await db.execute(
                select(Subscription).where(or_(*conds), Subscription.household_id != household.id)
            )
        ).scalar_one_or_none()
    if other is not None:
        raise Conflict(
            "purchase_in_other_household",
            "This purchase belongs to another household.",
            "Ye kharid kisi aur ghar ki hai.",
        )
    sub = await for_household(db, household.id)
    if sub is None:
        sub = Subscription(household_id=household.id)
        db.add(sub)
    _apply_state(sub, store, state, now)
    await db.flush()
    return sub


def _apply_state(sub: Subscription, store: str, state: StoreState, now: datetime) -> None:
    sub.store = store
    sub.product_id = state.product_id
    sub.status = state.status
    sub.renews_at = state.renews_at
    sub.grace_until = now + timedelta(days=GRACE_DAYS) if state.status == S.grace else None
    if state.original_transaction_id:
        sub.original_transaction_id = state.original_transaction_id
    if state.purchase_token:
        sub.purchase_token = state.purchase_token
    sub.last_event_at = now


# ---- Play RTDN -----------------------------------------------------------------------------

# SubscriptionNotification.notificationType -> status (None: no status change).
PLAY_TYPES: dict[int, SubscriptionStatus | None] = {
    1: S.active,  # RECOVERED
    2: S.active,  # RENEWED
    3: None,  # CANCELED: access continues until renews_at, then grace/expired by time
    4: S.active,  # PURCHASED
    5: S.expired,  # ON_HOLD
    6: S.grace,  # IN_GRACE_PERIOD
    7: S.active,  # RESTARTED
    12: S.expired,  # REVOKED
    13: S.expired,  # EXPIRED
}


def _ms(value: Any) -> datetime | None:
    try:
        return datetime.fromtimestamp(int(value) / 1000, tz=UTC)
    except (TypeError, ValueError):
        return None


def parse_play(body: dict[str, Any]) -> dict[str, Any]:
    """Pub/Sub push envelope -> DeveloperNotification dict."""
    msg = body.get("message")
    if isinstance(msg, dict) and msg.get("data"):
        try:
            return dict(json.loads(base64.b64decode(msg["data"]).decode("utf-8")))
        except (ValueError, TypeError) as exc:
            raise AppError("invalid_notification", "Bad notification.", "Galat suchna.") from exc
    return body


async def handle_play(
    db: AsyncSession, body: dict[str, Any], *, now: datetime | None = None
) -> str:
    now = now or utcnow()
    note = parse_play(body)
    sn = note.get("subscriptionNotification") or {}
    token = sn.get("purchaseToken")
    try:
        ntype = int(sn.get("notificationType") or 0)
    except (TypeError, ValueError):
        return "ignored"
    if not token:
        return "ignored"  # test notifications, one-time products
    verifier = get_verifier()
    if getattr(verifier, "authoritative", False):
        return await _handle_play_authoritative(db, verifier, note, token, ntype, now)
    sub = (
        await db.execute(select(Subscription).where(Subscription.purchase_token == token))
    ).scalar_one_or_none()
    if sub is None:
        log.info("play_rtdn_unknown_token", notification_type=ntype)
        return "unknown"
    event_at = _ms(note.get("eventTimeMillis")) or now
    if sub.last_event_at is not None and event_at < sub.last_event_at:
        return "stale"
    target = PLAY_TYPES.get(ntype)
    if target is not None:
        sub.status = target
        if target == S.active:
            # TODO(prod): read expiryTime from the Play Developer API; weekly until then.
            sub.renews_at = max(event_at, now) + WEEK
            sub.grace_until = None
        elif target == S.grace:
            sub.grace_until = now + timedelta(days=GRACE_DAYS)
    sub.store = "play"
    if sn.get("subscriptionId"):
        sub.product_id = sn["subscriptionId"]
    sub.last_event_at = event_at
    await db.flush()
    return str(sub.status)


async def _handle_play_authoritative(
    db: AsyncSession,
    verifier: Any,
    note: dict[str, Any],
    token: str,
    ntype: int,
    now: datetime,
) -> str:
    """Prod RTDN: the notification only says "something changed"; status, expiry and
    product come from ``purchases.subscriptionsv2.get``. A token we do not know is matched
    through ``linkedPurchaseToken`` (resubscribe / plan change); otherwise the app's restore
    call links it. Play API outages raise 503 so Pub/Sub redelivers."""
    state: StoreState | None
    try:
        state = await verifier.play_verify(token, now)
    except AppError as exc:
        if exc.code == "purchase_pending":
            return "pending"
        if exc.code != "receipt_invalid":
            raise
        state = None  # Play no longer knows the token (or it is not our product)
    sub = (
        await db.execute(select(Subscription).where(Subscription.purchase_token == token))
    ).scalar_one_or_none()
    if sub is None and state is not None and state.linked_purchase_token:
        sub = (
            await db.execute(
                select(Subscription).where(
                    Subscription.purchase_token == state.linked_purchase_token
                )
            )
        ).scalar_one_or_none()
    if sub is None:
        log.info("play_rtdn_unknown_token", notification_type=ntype)
        return "unknown"
    event_at = _ms(note.get("eventTimeMillis")) or now
    if sub.last_event_at is not None and event_at < sub.last_event_at:
        return "stale"
    if state is None:
        sub.status = S.expired
        sub.grace_until = None
    else:
        _apply_state(sub, "play", state, now)
    sub.last_event_at = event_at
    await db.flush()
    return str(sub.status)


# ---- App Store Server Notifications v2 ----------------------------------------------------


class JwsDecoder(Protocol):
    # True only for a decoder that checked the signature (appAccountToken is trusted then).
    verified: bool

    def decode(self, token: str) -> dict[str, Any]: ...


class UnverifiedJwsDecoder:
    """Dev/test only: reads the JWS payload without checking the x5c chain or signature."""

    verified = False

    def __init__(self) -> None:
        if not get_settings().is_dev:
            raise RuntimeError("UnverifiedJwsDecoder is for dev/test only")

    def decode(self, token: str) -> dict[str, Any]:
        try:
            part = token.split(".")[1]
            part += "=" * (-len(part) % 4)
            return dict(json.loads(base64.urlsafe_b64decode(part).decode("utf-8")))
        except (IndexError, ValueError, TypeError) as exc:
            raise AppError("invalid_notification", "Bad notification.", "Galat suchna.") from exc


_jws_decoder: JwsDecoder | None = None


def get_jws_decoder() -> JwsDecoder:
    if _jws_decoder is not None:
        return _jws_decoder
    if use_fakes():
        return UnverifiedJwsDecoder()
    decoder = AppleJwsDecoder()
    return decoder


def set_jws_decoder(decoder: JwsDecoder | None) -> None:
    global _jws_decoder
    _jws_decoder = decoder


APPSTORE_ACTIVE = {"SUBSCRIBED", "DID_RENEW", "OFFER_REDEEMED", "DID_CHANGE_RENEWAL_PREF"}
APPSTORE_EXPIRED = {"EXPIRED", "GRACE_PERIOD_EXPIRED", "REVOKE", "REFUND"}


async def handle_appstore(
    db: AsyncSession, body: dict[str, Any], *, now: datetime | None = None
) -> str:
    now = now or utcnow()
    if not get_settings().APPSTORE_ENABLED:
        raise _store_not_supported()
    decoder = get_jws_decoder()
    payload = decoder.decode(str(body.get("signedPayload") or ""))
    ntype = str(payload.get("notificationType") or "")
    subtype = str(payload.get("subtype") or "")
    data = payload.get("data") or {}
    info = (
        decoder.decode(data["signedTransactionInfo"]) if data.get("signedTransactionInfo") else {}
    )
    otid = info.get("originalTransactionId")
    sub = None
    if otid:
        sub = (
            await db.execute(
                select(Subscription).where(Subscription.original_transaction_id == str(otid))
            )
        ).scalar_one_or_none()
    token = info.get("appAccountToken")
    # appAccountToken is the household id the app set at purchase: only a verified
    # signature makes it trustworthy (else anyone could revoke any household).
    if sub is None and token and getattr(decoder, "verified", False):
        try:
            sub = await for_household(db, uuid.UUID(str(token)))
        except ValueError:
            sub = None
    if sub is None:
        log.info("appstore_unknown_transaction", notification_type=ntype)
        return "unknown"
    event_at = _ms(payload.get("signedDate")) or now
    if sub.last_event_at is not None and event_at < sub.last_event_at:
        return "stale"
    expires = _ms(info.get("expiresDate"))
    if ntype in APPSTORE_ACTIVE:
        sub.status = S.active
        sub.renews_at = expires or now + WEEK
        sub.grace_until = None
    elif ntype == "DID_FAIL_TO_RENEW":
        if subtype == "GRACE_PERIOD":
            sub.status = S.grace
            sub.grace_until = now + timedelta(days=GRACE_DAYS)
        else:
            sub.status = S.expired
    elif ntype in APPSTORE_EXPIRED:
        sub.status = S.expired
    sub.store = "app_store"
    if otid:
        sub.original_transaction_id = str(otid)
    if info.get("productId"):
        sub.product_id = str(info["productId"])
    sub.last_event_at = event_at
    await db.flush()
    return str(sub.status)


# ---- worker sweeps -----------------------------------------------------------------------------


async def sweep(db: AsyncSession, now: datetime) -> dict[str, int]:
    """Persist time-based transitions and send the day-5 / day-7 trial reminders. One
    transaction per subscription (``FOR UPDATE SKIP LOCKED``); reminders deduplicated by
    ``notification_marks`` (``expiry_reminder:5`` / ``:7`` per local day)."""
    from app.services import marks
    from app.services.sweeps import each

    changed = 0
    reminded = 0
    failed: dict[str, int] = {}
    days = get_settings().TRIAL_DAYS
    live = [S.trial, S.active, S.grace]

    def ids(seen: set[uuid.UUID]) -> Any:
        q = (
            select(Subscription.id)
            .join(Household, Household.id == Subscription.household_id)
            .where(Household.deleted_at.is_(None), Subscription.status.in_(live))
        )
        return (q.where(Subscription.id.not_in(seen)) if seen else q).order_by(Subscription.id)

    async def handle(sid: uuid.UUID) -> None:
        nonlocal changed, reminded
        sub = (
            await db.execute(
                select(Subscription)
                .where(Subscription.id == sid, Subscription.status.in_(live))
                .with_for_update(skip_locked=True)
            )
        ).scalar_one_or_none()
        if sub is None:
            return
        household = await db.get(Household, sub.household_id)
        if household is None or household.deleted_at is not None:
            return
        if refresh(sub, now):
            changed += 1
        if sub.status != S.trial or sub.trial_ends_at is None:
            return
        tz = ZoneInfo(household.timezone or "Asia/Kolkata")
        start_day = (sub.trial_ends_at - timedelta(days=days)).astimezone(tz).date()
        local = now.astimezone(tz)
        for n in REMINDER_DAYS:
            day = start_day + timedelta(days=n - 1)
            at = datetime.combine(day, REMINDER_TIME, tzinfo=tz)
            if local.date() != day or local < at:
                continue
            if not await marks.claim(db, household.id, f"expiry_reminder:{n}", day):
                continue
            left = max(0, math.ceil((sub.trial_ends_at - now).total_seconds() / 86400))
            await notify.emit(
                db, "expiry_reminder", household, params={"days_left": left, "day": n}, now=now
            )
            reminded += 1

    await each(db, "subscriptions", ids, handle, failed)
    return {
        "subscriptions_changed": changed,
        "expiry_reminders": reminded,
        "subscription_failures": sum(failed.values()),
    }
