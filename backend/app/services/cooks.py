"""Cooks and duty (FRD §5.7 as amended by F-2-05, F-2-06, F-2-07, F-5.7-06, F-5.7-10).

- v1: at most one hired cook per household plus any number of family cooks; exactly one
  primary, at most one backup (F-2-05).
- A hired cook's phone can hold that role in one household only (FR-K20 / F-2-06).
- Off duty for period P (F-5.7-06): (1) Cooking tickets stay; (2) New/Accepted tickets due
  in P go to the backup if the backup is on duty at that due time, else Unassigned, and the
  admin is alerted; (3) nothing moves back when the cook returns; (4) tickets confirmed during
  P follow (2) (see ``tickets.initial_status``).
- Removing a cook (F-5.7-10, F-2-07): the role goes, open New/Accepted tickets go Unassigned
  and the admin is alerted; a hired cook's login loses the household and its sessions.
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.models import (
    AuthSession,
    Cook,
    CookDutyLog,
    CookKind,
    CookLoginMode,
    Household,
    HouseholdMembership,
    Member,
    MembershipStatus,
    Ticket,
    TicketStatus,
    User,
)
from app.models.base import utcnow
from app.permissions import Action, Actor, Resource, can
from app.services import notifications as notify
from app.services import tickets as ticket_svc
from app.services.labels import mask_phone, time_label
from app.services.membership import release_deleted_memberships

S = TicketStatus


def cook_view(cook: Cook, user_phone: str | None = None) -> dict[str, Any]:
    return {
        "id": cook.id,
        "name": cook.name or "",
        "kind": str(cook.kind),
        "member_id": cook.member_id,
        "user_id": cook.user_id,
        "login_mode": str(cook.login_mode),
        "is_primary": cook.is_primary,
        "is_backup": cook.is_backup,
        "on_duty": cook.on_duty,
        "off_duty_until": cook.off_duty_until,
        "phone_masked": mask_phone(cook.phone or user_phone),
    }


async def list_cooks(db: AsyncSession, household: Household) -> list[dict[str, Any]]:
    cooks = await ticket_svc.household_cooks(db, household.id)
    phones: dict[uuid.UUID, str] = {}
    ids = [c.user_id for c in cooks if c.user_id]
    if ids:
        rows = await db.execute(select(User.id, User.phone).where(User.id.in_(ids)))
        phones = {r[0]: r[1] for r in rows.all()}
    return [cook_view(c, phones.get(c.user_id) if c.user_id else None) for c in cooks]


async def get_cook(db: AsyncSession, household: Household, cook_id: uuid.UUID) -> Cook:
    cook = await db.get(Cook, cook_id)
    if cook is None or cook.household_id != household.id or cook.removed_at is not None:
        raise NotFound()
    return cook


def _hired_limit() -> Conflict:
    return Conflict(
        "hired_cook_limit",
        "Only one hired cook for now.",
        "Abhi ek hi hired cook.",
    )


def _phone_elsewhere() -> Conflict:
    return Conflict(
        "phone_in_other_household",
        "This number is a cook in another household.",
        "Ye number dusre ghar mein cook hai.",
    )


async def check_hired_limit(db: AsyncSession, household_id: uuid.UUID) -> None:
    existing = (
        await db.execute(
            select(Cook.id).where(
                Cook.household_id == household_id,
                Cook.kind == CookKind.hired,
                Cook.removed_at.is_(None),
            )
        )
    ).first()
    if existing is not None:
        raise _hired_limit()


async def check_phone_free(db: AsyncSession, household_id: uuid.UUID, phone: str) -> User | None:
    """FR-K20: 409 when the phone is a cook in another household or belongs to a login that
    is already in another household. Returns the existing user (if any) to link."""
    # Soft-deleted households (7-day undo) do not hold the phone.
    other_cook = (
        await db.execute(
            select(Cook.id)
            .join(Household, Household.id == Cook.household_id)
            .where(
                Cook.phone == phone,
                Cook.household_id != household_id,
                Cook.removed_at.is_(None),
                Household.deleted_at.is_(None),
            )
            .limit(1)
        )
    ).first()
    if other_cook is not None:
        raise _phone_elsewhere()
    user = (await db.execute(select(User).where(User.phone == phone))).scalars().first()
    if user is None:
        return None
    membership = (
        (
            await db.execute(
                select(HouseholdMembership)
                .join(Household, Household.id == HouseholdMembership.household_id)
                .where(
                    HouseholdMembership.user_id == user.id,
                    HouseholdMembership.status == MembershipStatus.active,
                    Household.deleted_at.is_(None),
                )
            )
        )
        .scalars()
        .first()
    )
    if membership is not None and membership.household_id != household_id:
        raise _phone_elsewhere()
    if membership is not None:
        raise Conflict(
            "already_member",
            "This number already belongs to your household.",
            "Ye number pehle se aapke ghar mein hai.",
        )
    return user


async def _make_primary_or_backup(
    db: AsyncSession, household_id: uuid.UUID, cook: Cook, *, primary: bool
) -> None:
    others = await ticket_svc.household_cooks(db, household_id)
    for c in others:
        if c.id == cook.id:
            continue
        if primary and c.is_primary:
            c.is_primary = False
        if not primary and c.is_backup:
            c.is_backup = False
    if primary:
        cook.is_primary, cook.is_backup = True, False
    else:
        cook.is_backup, cook.is_primary = True, False


async def create_cook(
    db: AsyncSession, household: Household, actor: Actor, body: Mapping[str, Any]
) -> Cook:
    if not can(actor, Action.manage_cooks):
        raise Forbidden(details={"action": Action.manage_cooks.value})
    kind = CookKind(body["kind"])
    login_mode = CookLoginMode(body.get("login_mode") or CookLoginMode.own)
    existing = await ticket_svc.household_cooks(db, household.id)
    cook = Cook(household_id=household.id, kind=kind, login_mode=login_mode, on_duty=True)
    membership: HouseholdMembership | None = None
    if kind == CookKind.hired:
        phone = body.get("phone")
        if not phone:
            raise AppError(
                "phone_required",
                "A hired cook needs a phone number.",
                "Cook ka number chahiye.",
                status_code=422,
            )
        await check_hired_limit(db, household.id)
        user = await check_phone_free(db, household.id, phone)
        cook.phone = phone
        cook.name = body.get("name") or (user.name if user else None) or "Cook"
        db.add(cook)
        await db.flush()
        if user is not None and login_mode == CookLoginMode.own:
            await link_cook_login(db, cook, user)
    else:
        member_id = body.get("member_id")
        if member_id is None:
            raise AppError(
                "member_required",
                "Pick the family member who cooks.",
                "Kaun banayega, chuniye.",
                status_code=422,
            )
        member = await db.get(Member, member_id)
        if member is None or member.household_id != household.id or member.archived_at:
            raise NotFound("member_not_found")
        if any(c.member_id == member.id for c in existing):
            raise Conflict("already_cook", "This member already cooks.", "Ye pehle se cook hain.")
        membership = (
            await db.execute(
                select(HouseholdMembership).where(
                    HouseholdMembership.household_id == household.id,
                    HouseholdMembership.member_id == member.id,
                    HouseholdMembership.status == MembershipStatus.active,
                )
            )
        ).scalar_one_or_none()
        cook.member_id = member.id
        cook.name = body.get("name") or member.name
        if membership is not None:
            cook.user_id = membership.user_id
        elif body.get("login_mode") is None:
            # F-2-03: a profile-only member cooks "via admin".
            cook.login_mode = CookLoginMode.via_admin
        db.add(cook)
        await db.flush()
        if membership is not None and membership.cook_id is None:
            membership.cook_id = cook.id
    if not any(c.is_primary for c in existing):
        cook.is_primary = True
    await db.flush()
    return cook


async def link_cook_login(db: AsyncSession, cook: Cook, user: User) -> HouseholdMembership:
    """Give a hired cook's login its cook-only membership (no member / admin role)."""
    membership = (
        await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.user_id == user.id,
                HouseholdMembership.household_id == cook.household_id,
            )
        )
    ).scalar_one_or_none()
    await release_deleted_memberships(db, user.id)
    if membership is None:
        membership = HouseholdMembership(user_id=user.id, household_id=cook.household_id)
        db.add(membership)
    membership.status = MembershipStatus.active
    membership.is_admin = False
    membership.is_member = False
    membership.cook_id = cook.id
    cook.user_id = user.id
    if not cook.name and user.name:
        cook.name = user.name
    await db.flush()
    return membership


async def link_pending_cook(db: AsyncSession, user: User) -> bool:
    """On OTP login: a hired cook added by phone (login_mode own) gets cook mode (FR-K1)."""
    active = (
        await db.execute(
            select(HouseholdMembership.id).where(
                HouseholdMembership.user_id == user.id,
                HouseholdMembership.status == MembershipStatus.active,
            )
        )
    ).first()
    if active is not None:
        return False
    cook = (
        await db.execute(
            select(Cook)
            .join(Household, Household.id == Cook.household_id)
            .where(
                Cook.phone == user.phone,
                Cook.kind == CookKind.hired,
                Cook.login_mode == CookLoginMode.own,
                Cook.user_id.is_(None),
                Cook.removed_at.is_(None),
                Household.deleted_at.is_(None),
            )
            .limit(1)
        )
    ).scalar_one_or_none()
    if cook is None:
        return False
    await link_cook_login(db, cook, user)
    return True


# ---- duty ----------------------------------------------------------------------------------------


@dataclass
class DutyOutcome:
    moved_to_backup: list[Ticket] = field(default_factory=list)
    unassigned: list[Ticket] = field(default_factory=list)
    kept: list[Ticket] = field(default_factory=list)


def _log_duty(db: AsyncSession, cook: Cook, by: uuid.UUID | None, now: datetime) -> None:
    db.add(
        CookDutyLog(
            cook_id=cook.id,
            at=now,
            on_duty=cook.on_duty,
            until=cook.off_duty_until,
            reason=cook.off_duty_reason,
            by_user_id=by,
        )
    )


async def apply_off_duty(
    db: AsyncSession,
    household: Household,
    cook: Cook,
    *,
    start: datetime,
    end: datetime | None,
    now: datetime,
) -> DutyOutcome:
    """F-5.7-06 rules (1) and (2) for tickets of ``cook`` due in [start, end)."""
    out = DutyOutcome()
    stmt = select(Ticket).where(
        Ticket.household_id == household.id,
        Ticket.assignee_cook_id == cook.id,
        Ticket.status.in_([S.new, S.accepted, S.cooking]),
        Ticket.due_at >= start,
    )
    if end is not None:
        stmt = stmt.where(Ticket.due_at < end)
    tickets = list((await db.execute(stmt.order_by(Ticket.due_at))).scalars())
    cooks = await ticket_svc.household_cooks(db, household.id)
    for t in tickets:
        if t.status == S.cooking:
            out.kept.append(t)
            continue
        backup = ticket_svc.backup_for(cooks, cook, t.due_at)
        if backup is not None:
            to = ticket_svc.status_for_cook(backup, t.confirmed_by_user_id)
            await ticket_svc.system_transition(
                db,
                household,
                t,
                to,
                action="moved_to_backup",
                reason="assignee_off_duty",
                new_cook=backup,
                now=now,
            )
            t.updated = False
            out.moved_to_backup.append(t)
            await notify.emit(
                db,
                "ticket_created",
                household,
                ticket=t,
                assignee=backup,
                params=ticket_svc.ticket_params(household, t, backup),
                now=now,
            )
        else:
            await ticket_svc.system_transition(
                db,
                household,
                t,
                S.unassigned,
                action="unassigned",
                reason="assignee_off_duty",
                now=now,
            )
            out.unassigned.append(t)
            await notify.emit(
                db,
                "ticket_unassigned",
                household,
                ticket=t,
                params=ticket_svc.ticket_params(household, t),
                now=now,
            )
    return out


async def patch_cook(
    db: AsyncSession,
    household: Household,
    cook: Cook,
    actor: Actor,
    changes: Mapping[str, Any],
    now: datetime | None = None,
) -> DutyOutcome:
    now = now or utcnow()
    admin_fields = {"is_primary", "is_backup", "name", "login_mode"}
    duty_fields = {"on_duty", "off_duty_until", "reason"}
    touched = set(changes)
    if touched & admin_fields and not can(actor, Action.manage_cooks):
        raise Forbidden(details={"action": Action.manage_cooks.value})
    if touched & duty_fields and not can(
        actor, Action.set_duty, Resource(owner_user_id=cook.user_id)
    ):
        raise Forbidden(details={"action": Action.set_duty.value})
    if changes.get("is_primary") and changes.get("is_backup"):
        raise AppError(
            "primary_and_backup",
            "A cook cannot be both primary and backup.",
            "Ek hi cook primary aur backup dono nahi ho sakte.",
            status_code=422,
        )
    if changes.get("is_primary"):
        await _make_primary_or_backup(db, household.id, cook, primary=True)
    elif changes.get("is_primary") is False:
        cook.is_primary = False
    if changes.get("is_backup"):
        await _make_primary_or_backup(db, household.id, cook, primary=False)
    elif changes.get("is_backup") is False:
        cook.is_backup = False
    if changes.get("name"):
        cook.name = changes["name"]
    if changes.get("login_mode"):
        cook.login_mode = CookLoginMode(changes["login_mode"])

    outcome = DutyOutcome()
    if not touched & duty_fields:
        return outcome
    was_on = cook.on_duty
    old_until = cook.off_duty_until
    going_off = changes.get("on_duty") is False or (
        "off_duty_until" in changes
        and changes["off_duty_until"] is not None
        and changes.get("on_duty") is not True
    )
    if going_off:
        until = changes.get("off_duty_until")
        if until is not None and until <= now:
            raise AppError(
                "until_in_past",
                "The return time must be in the future.",
                "Wapas aane ka samay aage ka hona chahiye.",
                status_code=422,
            )
        cook.on_duty = False
        cook.off_duty_until = until
        cook.off_duty_reason = changes.get("reason")
        if was_on or old_until != until:
            _log_duty(db, cook, actor.user_id, now)
            outcome = await apply_off_duty(db, household, cook, start=now, end=until, now=now)
            await _alert_off_duty(db, household, cook, actor, outcome, now)
    elif changes.get("on_duty") is True:
        cook.on_duty = True
        cook.off_duty_until = None
        cook.off_duty_reason = None
        if not was_on:
            _log_duty(db, cook, actor.user_id, now)
            # F-5.7-06 rule 3: nothing moves back.
            await notify.emit(
                db,
                "cook_on_duty",
                household,
                actor_user_id=actor.user_id,
                params={"cook": cook.name or "Cook"},
                now=now,
            )
    return outcome


async def _alert_off_duty(
    db: AsyncSession,
    household: Household,
    cook: Cook,
    actor: Actor | None,
    outcome: DutyOutcome,
    now: datetime,
) -> None:
    until = (
        f"{time_label(cook.off_duty_until, household.timezone)} tak off. "
        if cook.off_duty_until
        else "Agli suchna tak off. "
    )
    parts = []
    if outcome.moved_to_backup:
        parts.append(f"{len(outcome.moved_to_backup)} ticket backup ko gaye")
    if outcome.unassigned:
        parts.append(f"{len(outcome.unassigned)} ticket Unassigned")
    await notify.emit(
        db,
        "cook_off_duty",
        household,
        actor_user_id=actor.user_id if actor else None,
        params={"cook": cook.name or "Cook", "until": until, "moved": ", ".join(parts)},
        now=now,
    )


async def return_from_off_duty(
    db: AsyncSession, household: Household, cook: Cook, now: datetime
) -> None:
    """Worker: the off period ended. On duty again; tickets stay where they are (rule 3)."""
    cook.on_duty = True
    cook.off_duty_until = None
    cook.off_duty_reason = None
    _log_duty(db, cook, None, now)
    await notify.emit(db, "cook_on_duty", household, params={"cook": cook.name or "Cook"}, now=now)


async def remove_cook(
    db: AsyncSession, household: Household, cook: Cook, actor: Actor, now: datetime | None = None
) -> list[Ticket]:
    now = now or utcnow()
    if not can(actor, Action.manage_cooks):
        raise Forbidden(details={"action": Action.manage_cooks.value})
    tickets = list(
        (
            await db.execute(
                select(Ticket).where(
                    Ticket.assignee_cook_id == cook.id,
                    Ticket.status.in_([S.new, S.accepted]),
                )
            )
        ).scalars()
    )
    for t in tickets:
        await ticket_svc.system_transition(
            db, household, t, S.unassigned, action="unassigned", reason="cook_removed", now=now
        )
    cook.removed_at = now
    cook.is_primary = False
    cook.is_backup = False
    memberships = list(
        (
            await db.execute(
                select(HouseholdMembership).where(HouseholdMembership.cook_id == cook.id)
            )
        ).scalars()
    )
    for m in memberships:
        m.cook_id = None
        if not (m.is_admin or m.is_member):
            m.status = MembershipStatus.removed
            await db.execute(
                update(AuthSession)
                .where(AuthSession.user_id == m.user_id, AuthSession.revoked_at.is_(None))
                .values(revoked_at=now)
            )
    await db.flush()
    for t in tickets:
        await notify.emit(
            db,
            "ticket_unassigned",
            household,
            ticket=t,
            actor_user_id=actor.user_id,
            params=ticket_svc.ticket_params(household, t),
            now=now,
        )
    return tickets


async def duty_history(
    db: AsyncSession, cook: Cook, start: datetime, end: datetime
) -> list[CookDutyLog]:
    stmt = (
        select(CookDutyLog)
        .where(CookDutyLog.cook_id == cook.id, CookDutyLog.at >= start, CookDutyLog.at < end)
        .order_by(CookDutyLog.at)
    )
    return list((await db.execute(stmt)).scalars())
