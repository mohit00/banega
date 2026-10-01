"""The caller's own account: read, update, delete (7-day undo, FR-A8) and restore."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter
from sqlalchemy import select

from app.api.auth import revoke_all_sessions
from app.api.deps import DB, Auth, active_membership
from app.core.config import get_settings
from app.core.errors import Conflict, Gone, NotFound
from app.core.security import utcnow
from app.models import (
    Cook,
    CookKind,
    Household,
    HouseholdMembership,
    MembershipStatus,
    NotificationPref,
)
from app.permissions import Actor
from app.schemas import (
    LANGUAGE_TO_LOCALE,
    DeletionOut,
    MeConsentOut,
    MeCookOut,
    MembershipOut,
    MeOut,
    UserOut,
    UserPatch,
)
from app.schemas_kitchen import (
    NotificationPrefOut,
    NotificationPrefsIn,
    NotificationPrefsOut,
    QuietHours,
)
from app.services import cooks as cook_svc
from app.services.notifications import MATRIX, QUIET_HOURS_EVENT

router = APIRouter(prefix="/me", tags=["me"])


async def _me(db: DB, auth: Auth) -> MeOut:
    membership = await active_membership(db, auth.user.id)
    cook_kind: CookKind | None = None
    cook_out: MeCookOut | None = None
    modes: list[str] = []
    if membership is not None:
        if membership.is_admin or membership.is_member:
            modes.append("family")
        cook = await db.get(Cook, membership.cook_id) if membership.cook_id else None
        if cook is not None and cook.removed_at is None:
            cook_kind = cook.kind
            modes.append("cook")
            cook_out = MeCookOut(
                id=cook.id,
                kind=cook.kind,
                login_mode=cook.login_mode,
                on_duty=cook.on_duty,
                off_duty_until=cook.off_duty_until,
            )
    from app.api.billing import consent_state

    consent = await consent_state(db, auth.user.id)
    return MeOut(
        user=UserOut.model_validate(auth.user),
        membership=MembershipOut.model_validate(membership) if membership else None,
        cook_kind=cook_kind,
        modes=modes,
        cook=cook_out,
        consent=MeConsentOut.model_validate(consent.model_dump()),
    )


@router.get("", response_model=MeOut)
async def get_me(auth: Auth, db: DB) -> MeOut:
    return await _me(db, auth)


@router.patch("", response_model=MeOut)
async def update_me(body: UserPatch, auth: Auth, db: DB) -> MeOut:
    changes = body.model_dump(exclude_unset=True)
    language = changes.pop("language", None)
    if language is not None:
        changes["locale"] = LANGUAGE_TO_LOCALE[language]
    for field, value in changes.items():
        if value is not None:
            setattr(auth.user, field, value)
    await db.commit()
    return await _me(db, auth)


async def _leave_household(db: DB, auth: Auth, now: datetime) -> None:
    """Account deletion must not orphan the household (review M9)."""
    membership = await active_membership(db, auth.user.id)
    if membership is None:
        return
    household = await db.get(Household, membership.household_id)
    if household is None or household.deleted_at is not None:
        return
    if membership.is_admin:
        other_admin = (
            await db.execute(
                select(HouseholdMembership.id).where(
                    HouseholdMembership.household_id == household.id,
                    HouseholdMembership.user_id != auth.user.id,
                    HouseholdMembership.status == MembershipStatus.active,
                    HouseholdMembership.is_admin.is_(True),
                )
            )
        ).first()
        if other_admin is None:
            raise Conflict(
                "transfer_admin_first",
                "You are the only admin. Make someone else admin, or delete the household first.",
                "Aap akele admin hain. Pehle kisi aur ko admin banaiye, ya ghar delete kijiye.",
            )
    cook = await db.get(Cook, membership.cook_id) if membership.cook_id else None
    if cook is not None and cook.kind == CookKind.hired and cook.removed_at is None:
        # A hired cook leaving: archive her cook row, unassign her open tickets, alert admin.
        actor = Actor(user_id=uuid.UUID(int=0), household_id=household.id, is_admin=True)
        await cook_svc.remove_cook(db, household, cook, actor, now)


@router.delete("", response_model=DeletionOut)
async def delete_me(auth: Auth, db: DB) -> DeletionOut:
    """Soft-delete the account and log out everywhere. Log in again within 7 days to undo.
    409 ``transfer_admin_first`` for the only admin of a live household; a hired cook's cook
    row is archived and her open tickets go back to the admin (unassigned)."""
    now = utcnow()
    await _leave_household(db, auth, now)
    auth.user.deleted_at = now
    await revoke_all_sessions(db, auth.user.id)
    await db.commit()
    return DeletionOut(
        deleted_at=now, undo_until=now + timedelta(days=get_settings().UNDO_WINDOW_DAYS)
    )


@router.post("/restore", response_model=MeOut)
async def restore_me(auth: Auth, db: DB) -> MeOut:
    deleted_at = auth.user.deleted_at
    if deleted_at is None:
        raise NotFound()
    if deleted_at + timedelta(days=get_settings().UNDO_WINDOW_DAYS) <= utcnow():
        raise Gone(
            "undo_window_over", "The undo window has closed.", "Wapas laane ka samay khatam."
        )
    auth.user.deleted_at = None
    await db.commit()
    return await _me(db, auth)


# ---- notification preferences (F-X-01: per-event switch + quiet hours) ---------------------


async def _prefs_out(db: DB, auth: Auth) -> NotificationPrefsOut:
    rows = {
        p.event: p
        for p in (
            await db.execute(
                select(NotificationPref).where(NotificationPref.user_id == auth.user.id)
            )
        ).scalars()
    }
    quiet = rows.get(QUIET_HOURS_EVENT)
    return NotificationPrefsOut(
        prefs=[
            NotificationPrefOut(
                event=event,
                enabled=True
                if rule.mandatory
                else (rows[event].enabled if event in rows else True),
                mandatory=rule.mandatory,
            )
            for event, rule in MATRIX.items()
        ],
        quiet_hours=QuietHours.model_validate(quiet.quiet_hours)
        if quiet is not None and quiet.quiet_hours
        else None,
    )


@router.get("/notification-prefs", response_model=NotificationPrefsOut)
async def get_notification_prefs(auth: Auth, db: DB) -> NotificationPrefsOut:
    return await _prefs_out(db, auth)


@router.put("/notification-prefs", response_model=NotificationPrefsOut)
async def put_notification_prefs(
    body: NotificationPrefsIn, auth: Auth, db: DB
) -> NotificationPrefsOut:
    """Mandatory events (assigned/updated ticket for the assignee, approvals) stay on."""
    rows = {
        p.event: p
        for p in (
            await db.execute(
                select(NotificationPref).where(NotificationPref.user_id == auth.user.id)
            )
        ).scalars()
    }
    for item in body.prefs:
        rule = MATRIX.get(item.event)
        if rule is None:
            raise NotFound("unknown_event", details={"event": item.event})
        if rule.mandatory:
            continue
        row = rows.get(item.event)
        if row is None:
            row = NotificationPref(user_id=auth.user.id, event=item.event)
            db.add(row)
            rows[item.event] = row
        row.enabled = item.enabled
    if "quiet_hours" in body.model_fields_set:
        row = rows.get(QUIET_HOURS_EVENT)
        if row is None:
            row = NotificationPref(user_id=auth.user.id, event=QUIET_HOURS_EVENT, enabled=True)
            db.add(row)
        row.quiet_hours = body.quiet_hours.model_dump() if body.quiet_hours else None
    await db.commit()
    return await _prefs_out(db, auth)
