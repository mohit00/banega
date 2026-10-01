"""Cooking tickets: the declarative state table (docs/frd-review.md F-5.7-02, contract
§Tickets), confirm, edit (FR-K7), claim (K16), item-out and messages.

``STATE_TABLE`` is the single source of truth for status changes. Each row says which
statuses it leaves from, which it goes to, which actor roles may use it and through which
entry point (``Via``). :func:`transition` serves ``POST /tickets/{id}/transitions``; the other
entry points (confirm, edit, claim, the worker, the off-duty rule) go through
:func:`_apply`, which checks the same table.

Actor roles for one ticket (``roles_for``):
- ``assignee``: the ticket's cook, or the admin for a cook run "via admin" (profile-only
  family cook F-2-03, WhatsApp-only hired cook F-5.6-03);
- ``family_cook_own``: the assignee when that cook is a family cook;
- ``admin``; ``confirmer``: the user who confirmed the menu, within the §2.1 edit/cancel
  window (members: before Accepted); ``claimant``: anyone allowed to claim Chef for the day;
- ``system``: worker timers and the off-duty rule (no user).

An illegal (from, to) pair for the caller is HTTP 409 ``invalid_transition`` with the
caller's allowed next statuses. A pair that exists in the table but not for the caller's
roles is 403.
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from enum import StrEnum
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, Conflict, Forbidden, NotFound
from app.models import (
    Cook,
    CookKind,
    CookLoginMode,
    Household,
    HouseholdMembership,
    Ingredient,
    Member,
    MembershipStatus,
    Menu,
    Ticket,
    TicketEvent,
    TicketMessage,
    TicketStatus,
    User,
)
from app.models.base import utcnow
from app.permissions import PRE_ACCEPT_STATUSES, Action, Actor, Resource, can
from app.services import menus as menu_svc
from app.services import notifications as notify
from app.services.labels import day_label, slot_label, time_label

S = TicketStatus


class Role(StrEnum):
    assignee = "assignee"
    family_cook_own = "family_cook_own"
    admin = "admin"
    confirmer = "confirmer"
    claimant = "claimant"
    system = "system"


class Via(StrEnum):
    api = "api"  # POST /tickets/{id}/transitions
    edit = "edit"  # PATCH /tickets/{id}, re-confirm
    claim = "claim"  # POST /tickets/{id}/claim
    system = "system"  # worker timers, off-duty rule, cook removal


@dataclass(frozen=True, slots=True)
class Row:
    frm: frozenset[TicketStatus]
    to: frozenset[TicketStatus]
    actors: frozenset[Role]
    via: Via
    condition: str
    reason_required: bool = False


def _row(
    frm: Sequence[TicketStatus],
    to: Sequence[TicketStatus],
    actors: Sequence[Role],
    via: Via,
    condition: str,
    *,
    reason_required: bool = False,
) -> Row:
    return Row(frozenset(frm), frozenset(to), frozenset(actors), via, condition, reason_required)


R = Role
# Initial status on confirm (no "from"): hired assignee -> new; family cook or the confirmer
# herself -> accepted; no assignee, or assignee off duty with no on-duty backup -> unassigned
# (F-5.7-06 rule 4: an off-duty assignee's new ticket goes to the on-duty backup first).
# See initial_status().
STATE_TABLE: tuple[Row, ...] = (
    _row([S.new], [S.accepted], [R.assignee], Via.api, "Hired cook accepts"),
    _row(
        [S.new, S.accepted],
        [S.new],
        [R.admin, R.confirmer, R.family_cook_own],
        Via.edit,
        "Edit of a hired-cook ticket: back to New with updated=true; the cook re-accepts",
    ),
    _row(
        [S.accepted, S.unassigned],
        [S.accepted, S.unassigned],
        [R.admin, R.confirmer, R.family_cook_own],
        Via.edit,
        "Edit of a family-cook / unassigned ticket: status kept, updated=true",
    ),
    _row([S.accepted], [S.cooking], [R.assignee], Via.api, "Assignee starts cooking"),
    _row([S.cooking], [S.ready], [R.assignee], Via.api, "Optional; may be skipped"),
    _row(
        [S.cooking, S.ready],
        [S.completed],
        [R.assignee, R.admin],
        Via.api,
        "Fires rating prompts, stock decrement, history (Phases 6-7)",
    ),
    _row(
        [S.new, S.unassigned, S.accepted],
        [S.cancelled],
        [R.admin, R.confirmer, R.family_cook_own],
        Via.api,
        "Cook notified",
    ),
    _row([S.cooking], [S.cancelled], [R.admin], Via.api, "Reason required", reason_required=True),
    _row(
        [S.unassigned],
        [S.new, S.accepted],
        [R.admin],
        Via.api,
        "Admin reassigns (body.assignee_cook_id): new for a hired cook, accepted for family",
    ),
    _row([S.unassigned], [S.accepted], [R.claimant], Via.claim, "Chef for the day; first wins"),
    _row(
        [S.accepted, S.cooking, S.ready],
        [S.not_confirmed],
        [R.system],
        Via.system,
        "due_at + 3 h without Completed; admin asked 'Khaana bana?'",
    ),
    _row(
        [S.not_confirmed],
        [S.completed, S.cancelled],
        [R.admin],
        Via.api,
        "Admin answers 'Khaana bana?' (no learning or stock effects when cancelled)",
    ),
    _row([S.not_confirmed], [S.cancelled], [R.system], Via.system, "24 h in not_confirmed"),
    _row(
        [S.new, S.unassigned],
        [S.cancelled],
        [R.system],
        Via.system,
        "Nobody picked it up: auto-cancelled 24 h after due",
    ),
    _row(
        [S.new, S.accepted],
        [S.unassigned],
        [R.system],
        Via.system,
        "Assignee off duty for due_at with no on-duty backup, or cook removed",
    ),
    _row(
        [S.new, S.accepted],
        [S.new, S.accepted],
        [R.system],
        Via.system,
        "Assignee off duty: moved to the on-duty backup (new if hired, accepted if family)",
    ),
)

OPEN_STATUSES: frozenset[TicketStatus] = frozenset(
    {S.new, S.unassigned, S.accepted, S.cooking, S.ready}
)
CLOSED_STATUSES: frozenset[TicketStatus] = frozenset({S.completed, S.cancelled, S.not_confirmed})
PRE_COOKING: frozenset[TicketStatus] = frozenset({S.new, S.unassigned, S.accepted})
EDITABLE_FIELDS: frozenset[str] = frozenset(
    {"dishes", "eaters", "guests", "servings", "due_at", "notes"}
)


class InvalidTransition(Conflict):
    code = "invalid_transition"
    message_en = "This ticket cannot move to that status now."
    message_hi = "Ticket abhi is sthiti mein nahi ja sakta."

    def __init__(self, allowed: Sequence[TicketStatus | str]) -> None:
        values = sorted(str(a) for a in allowed)
        super().__init__(details={"allowed": values})
        self.extra = {"allowed": values}


def _closed_error() -> Conflict:
    return Conflict(
        "ticket_closed",
        "This ticket is closed.",
        "Ye ticket band ho chuka hai.",
    )


# ---- actor roles ----


def acts_as_assignee(actor: Actor | None, cook: Cook | None) -> bool:
    if actor is None or cook is None or cook.removed_at is not None:
        return False
    if cook.user_id is not None and cook.user_id == actor.user_id:
        return True
    return actor.is_admin and (cook.login_mode == CookLoginMode.via_admin or cook.user_id is None)


def resource_for(ticket: Ticket, cook: Cook | None, actor: Actor | None = None) -> Resource:
    """§2.1 resource for a ticket. The assignee is the caller when she acts for the cook."""
    assignee_user = cook.user_id if cook is not None else None
    if actor is not None and acts_as_assignee(actor, cook):
        assignee_user = actor.user_id
    return Resource(
        confirmed_by_user_id=ticket.confirmed_by_user_id,
        assignee_user_id=assignee_user,
        ticket_status=str(ticket.status),
    )


def roles_for(actor: Actor | None, ticket: Ticket, cook: Cook | None) -> frozenset[Role]:
    if actor is None:
        return frozenset({Role.system})
    roles: set[Role] = set()
    if actor.is_admin:
        roles.add(Role.admin)
    if acts_as_assignee(actor, cook):
        roles.add(Role.assignee)
        if cook is not None and cook.kind == CookKind.family:
            roles.add(Role.family_cook_own)
    if ticket.confirmed_by_user_id == actor.user_id and (
        actor.is_admin
        or can(actor, Action.cancel_ticket, resource_for(ticket, cook, actor))
        or (actor.is_member and str(ticket.status) in PRE_ACCEPT_STATUSES)
    ):
        roles.add(Role.confirmer)
    if can(actor, Action.claim_chef):
        roles.add(Role.claimant)
    return frozenset(roles)


def allowed_next(
    status: TicketStatus, roles: frozenset[Role], via: Via = Via.api
) -> list[TicketStatus]:
    out: set[TicketStatus] = set()
    for row in STATE_TABLE:
        if row.via == via and status in row.frm and row.actors & roles:
            out |= row.to
    return sorted(out, key=lambda s: list(TicketStatus).index(s))


def _rows(status: TicketStatus, to: TicketStatus, via: Via) -> list[Row]:
    return [r for r in STATE_TABLE if r.via == via and status in r.frm and to in r.to]


def check(status: TicketStatus, to: TicketStatus, roles: frozenset[Role], via: Via) -> Row:
    """The table row that allows (status -> to) for ``roles`` through ``via``; else raises."""
    rows = _rows(status, to, via)
    if not rows:
        raise InvalidTransition(allowed_next(status, roles, via))
    for row in rows:
        if row.actors & roles:
            return row
    raise Forbidden(
        "transition_not_allowed",
        "You cannot make this change on this ticket.",
        "Aap is ticket mein ye badlav nahi kar sakte.",
        details={"allowed": [str(s) for s in allowed_next(status, roles, via)]},
    )


# ---- duty and assignment ----


def on_duty_at(cook: Cook, at: datetime) -> bool:
    """On duty for a ticket due at ``at`` (an off period ends at off_duty_until)."""
    if cook.removed_at is not None:
        return False
    if cook.on_duty:
        return True
    return cook.off_duty_until is not None and cook.off_duty_until <= at


async def household_cooks(db: AsyncSession, household_id: uuid.UUID) -> list[Cook]:
    stmt = select(Cook).where(Cook.household_id == household_id, Cook.removed_at.is_(None))
    return list((await db.execute(stmt.order_by(Cook.created_at))).scalars())


def backup_for(cooks: Sequence[Cook], cook: Cook | None, at: datetime) -> Cook | None:
    for c in cooks:
        if c.is_backup and (cook is None or c.id != cook.id) and on_duty_at(c, at):
            return c
    return None


@dataclass(frozen=True, slots=True)
class Assignment:
    status: TicketStatus
    cook: Cook | None
    reason: str  # assigned | self | no_assignee | off_duty_backup | off_duty_unassigned


def status_for_cook(cook: Cook, confirmer_user_id: uuid.UUID | None) -> TicketStatus:
    if cook.kind == CookKind.hired:
        return S.new
    return S.accepted


def initial_status(
    cook: Cook | None,
    cooks: Sequence[Cook],
    due_at: datetime,
    confirmer_user_id: uuid.UUID | None,
) -> Assignment:
    """Initial state rule (F-5.7-02 rows 1-3, F-5.7-06 rule 4)."""
    if cook is None or cook.removed_at is not None:
        return Assignment(S.unassigned, None, "no_assignee")
    if not on_duty_at(cook, due_at):
        backup = backup_for(cooks, cook, due_at)
        if backup is None:
            return Assignment(S.unassigned, None, "off_duty_unassigned")
        return Assignment(status_for_cook(backup, confirmer_user_id), backup, "off_duty_backup")
    if confirmer_user_id is not None and cook.user_id == confirmer_user_id:
        return Assignment(S.accepted, cook, "self")
    return Assignment(status_for_cook(cook, confirmer_user_id), cook, "assigned")


# ---- helpers ----


def log_event(
    db: AsyncSession,
    ticket: Ticket,
    action: str,
    by: uuid.UUID | None,
    detail: Mapping[str, Any] | None = None,
    now: datetime | None = None,
) -> TicketEvent:
    ev = TicketEvent(
        ticket_id=ticket.id,
        at=now or utcnow(),
        by_user_id=by,
        action=action,
        detail=dict(detail or {}),
    )
    db.add(ev)
    return ev


def bump(ticket: Ticket) -> None:
    ticket.version = (ticket.version or 0) + 1


def _set_status(ticket: Ticket, to: TicketStatus, now: datetime) -> None:
    if ticket.status != to:
        ticket.status = to
        ticket.status_changed_at = now


def ticket_params(
    household: Household, ticket: Ticket, cook: Cook | None = None, **extra: Any
) -> dict[str, Any]:
    return {
        "slot": slot_label(ticket.slot),
        "day": day_label(ticket.date),
        "due": time_label(ticket.due_at, household.timezone),
        "dishes": ", ".join(str(d.get("name", "")) for d in ticket.dishes or []) or "-",
        "cook": (cook.name if cook is not None else None) or "Cook",
        **extra,
    }


async def ticket_cook(db: AsyncSession, ticket: Ticket) -> Cook | None:
    return await db.get(Cook, ticket.assignee_cook_id) if ticket.assignee_cook_id else None


async def get_ticket(db: AsyncSession, household: Household, ticket_id: uuid.UUID) -> Ticket:
    ticket = await db.get(Ticket, ticket_id)
    if ticket is None or ticket.household_id != household.id:
        raise NotFound()
    return ticket


# ---- confirm ----


async def confirm(
    db: AsyncSession,
    household: Household,
    menu: Menu,
    actor: Actor,
    now: datetime | None = None,
) -> Ticket:
    """POST /menus/{id}/confirm: create the ticket (F-5.6-02). A menu whose ticket is still
    open (anything but cancelled) is 409 ``menu_already_confirmed``."""
    now = now or utcnow()
    cooks = await household_cooks(db, household.id)
    cook = next((c for c in cooks if c.id == menu.assignee_cook_id), None)
    res = Resource(assignee_user_id=cook.user_id if cook is not None else None)
    if not can(actor, Action.confirm_menu, res):
        raise Forbidden(details={"action": Action.confirm_menu.value})
    plan = await menu_svc.menu_plan(db, household, menu)
    if not plan.dishes:
        raise AppError(
            "menu_empty",
            "Add at least one dish first.",
            "Pehle kam se kam ek dish jodiye.",
            status_code=422,
        )
    existing = await db.get(Ticket, menu.ticket_id) if menu.ticket_id else None
    if existing is not None and existing.status != S.cancelled:
        # One ticket per menu: later changes are ticket edits (PATCH /tickets/{id}, FR-K7).
        raise Conflict(
            "menu_already_confirmed",
            "This menu is already with the cook. Edit the ticket instead.",
            "Ye menu pehle hi bhej diya gaya hai. Ticket badliye.",
            details={"ticket_id": str(existing.id), "status": str(existing.status)},
        )
    assignment = initial_status(cook, cooks, menu.due_at, actor.user_id)
    ticket = Ticket(
        id=uuid.uuid4(),
        household_id=household.id,
        menu_id=menu.id,
        date=menu.date,
        slot=menu.slot,
        due_at=menu.due_at,
        status=assignment.status,
        assignee_cook_id=assignment.cook.id if assignment.cook else None,
        confirmed_by_user_id=actor.user_id,
        dishes=plan.dishes,
        eaters=plan.eater_refs(),
        guests=plan.guests,
        servings=menu.servings if menu.servings else plan.servings,
        notes=menu.notes,
        accepted_at=now if assignment.status == S.accepted else None,
        status_changed_at=now,
        version=1,
    )
    db.add(ticket)
    await db.flush()
    menu.ticket_id = ticket.id
    detail: dict[str, Any] = {
        "status": str(assignment.status),
        "assignee_cook_id": str(assignment.cook.id) if assignment.cook else None,
        "reason": assignment.reason,
    }
    if assignment.reason == "self":
        detail["self_approved"] = True  # F-2-04: no accept step for her own ticket
    log_event(db, ticket, "created", actor.user_id, detail, now)
    await _notify_assignment(db, household, ticket, assignment.cook, actor.user_id, now)
    return ticket


async def _notify_assignment(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    cook: Cook | None,
    actor_user_id: uuid.UUID | None,
    now: datetime,
) -> None:
    if ticket.status == S.unassigned:
        await notify.emit(
            db,
            "ticket_unassigned",
            household,
            ticket=ticket,
            actor_user_id=actor_user_id,
            params=ticket_params(household, ticket),
            now=now,
        )
    elif cook is not None:
        await notify.emit(
            db,
            "ticket_created",
            household,
            ticket=ticket,
            assignee=cook,
            actor_user_id=actor_user_id,
            params=ticket_params(household, ticket, cook),
            now=now,
        )


# ---- transitions ----


async def transition(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    to: TicketStatus,
    actor: Actor,
    *,
    reason: str | None = None,
    note: str | None = None,
    assignee_cook_id: uuid.UUID | None = None,
    now: datetime | None = None,
) -> Ticket:
    """POST /tickets/{id}/transitions."""
    now = now or utcnow()
    cook = await ticket_cook(db, ticket)
    roles = roles_for(actor, ticket, cook)
    row = check(ticket.status, to, roles, Via.api)
    if row.reason_required and not (reason or "").strip():
        raise AppError(
            "reason_required",
            "Please give a reason.",
            "Kripya kaaran bataiye.",
            status_code=422,
        )
    frm = ticket.status
    new_cook = cook
    if frm == S.unassigned and to in (S.new, S.accepted):
        if assignee_cook_id is None:
            raise AppError(
                "assignee_required",
                "Choose who will cook.",
                "Chuniye kaun banayega.",
                status_code=422,
            )
        new_cook = await db.get(Cook, assignee_cook_id)
        if new_cook is None or new_cook.household_id != household.id or new_cook.removed_at:
            raise NotFound("cook_not_found")
        implied = status_for_cook(new_cook, ticket.confirmed_by_user_id)
        if implied != to:
            raise InvalidTransition([implied])
        ticket.assignee_cook_id = new_cook.id
    await _apply(db, household, ticket, to, actor.user_id, now, reason=reason, note=note)
    detail: dict[str, Any] = {"from": str(frm), "to": str(to)}
    if reason:
        detail["reason"] = reason
    if note:
        detail["note"] = note
    if new_cook is not cook and new_cook is not None:
        detail["assignee_cook_id"] = str(new_cook.id)
    log_event(db, ticket, str(to), actor.user_id, detail, now)
    await _notify_transition(db, household, ticket, frm, to, new_cook, actor.user_id, reason, now)
    if to == S.completed:
        # Phases 6-7: served history, auto-decrement, rating prompts (never on cancel).
        from app.services.ratings import on_completed

        await on_completed(db, household, ticket, now=now)
    return ticket


async def _apply(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    to: TicketStatus,
    by: uuid.UUID | None,
    now: datetime,
    *,
    reason: str | None = None,
    note: str | None = None,
) -> None:
    """Set the status and the matching timestamps; bump the version once."""
    _set_status(ticket, to, now)
    if to == S.accepted:
        ticket.accepted_at = now
        ticket.updated = False
    elif to == S.cooking:
        ticket.started_at = now
    elif to == S.ready:
        ticket.ready_at = now
    elif to == S.completed:
        ticket.completed_at = now
        ticket.completed_by = by
    elif to == S.cancelled:
        ticket.cancel_reason = (reason or note or "")[:200] or None
    elif to == S.new:
        ticket.accepted_at = None
    bump(ticket)


async def _notify_transition(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    frm: TicketStatus,
    to: TicketStatus,
    cook: Cook | None,
    actor_user_id: uuid.UUID | None,
    reason: str | None,
    now: datetime,
) -> None:
    params = ticket_params(household, ticket, cook, reason=reason or "")
    if to == S.accepted and frm == S.new:
        await notify.emit(
            db,
            "ticket_accepted",
            household,
            ticket=ticket,
            assignee=cook,
            actor_user_id=actor_user_id,
            params=params,
            now=now,
        )
    elif to in (S.new, S.accepted) and frm == S.unassigned:
        await _notify_assignment(db, household, ticket, cook, actor_user_id, now)
    elif to == S.completed:
        await notify.emit(
            db,
            "ticket_completed",
            household,
            ticket=ticket,
            assignee=cook,
            actor_user_id=actor_user_id,
            params=params,
            now=now,
        )
    elif to == S.cancelled and cook is not None:
        await notify.emit(
            db,
            "ticket_cancelled",
            household,
            ticket=ticket,
            assignee=cook,
            actor_user_id=actor_user_id,
            params=params,
            now=now,
        )


async def system_transition(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    to: TicketStatus,
    *,
    action: str | None = None,
    reason: str | None = None,
    new_cook: Cook | None = None,
    now: datetime | None = None,
) -> None:
    """Worker timers, off-duty moves and cook removal (Via.system rows only)."""
    now = now or utcnow()
    check(ticket.status, to, frozenset({Role.system}), Via.system)
    frm = ticket.status
    if new_cook is not None:
        ticket.assignee_cook_id = new_cook.id
    elif to == S.unassigned:
        ticket.assignee_cook_id = None
    await _apply(db, household, ticket, to, None, now, reason=reason)
    detail: dict[str, Any] = {"from": str(frm), "to": str(to)}
    if reason:
        detail["reason"] = reason
    if new_cook is not None:
        detail["assignee_cook_id"] = str(new_cook.id)
    log_event(db, ticket, action or str(to), None, detail, now)


# ---- edit (FR-K7) ----


async def edit(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    actor: Actor,
    changes: Mapping[str, Any],
    *,
    now: datetime | None = None,
    sync_menu: bool = True,
) -> Ticket:
    """PATCH /tickets/{id}. Before Cooking everything may change; during Cooking/Ready only
    notes; closed tickets not at all. A hired-cook ticket returns to New (updated=true) so
    the cook re-accepts; a family-cook ticket stays Accepted with updated=true. When the
    editor is the assignee herself the change is self-approved (F-2-04): no re-accept."""
    now = now or utcnow()
    cook = await ticket_cook(db, ticket)
    res = resource_for(ticket, cook, actor)
    if not can(actor, Action.edit_ticket, res):
        raise Forbidden(details={"action": Action.edit_ticket.value})
    if ticket.status in CLOSED_STATUSES:
        raise _closed_error()
    requested = {k for k, v in changes.items() if k in EDITABLE_FIELDS}
    if ticket.status not in PRE_COOKING and requested - {"notes"}:
        raise Conflict(
            "edit_locked",
            "Cooking has started: only notes can change now.",
            "Khaana banna shuru ho gaya: ab sirf note badal sakte hain.",
            details={"allowed_fields": ["notes"]},
        )
    diff = await _apply_changes(db, household, ticket, changes)
    if not diff:
        return ticket
    self_edit = acts_as_assignee(actor, cook)
    roles = roles_for(actor, ticket, cook)
    target = ticket.status
    if (
        cook is not None
        and cook.kind == CookKind.hired
        and ticket.status in (S.new, S.accepted)
        and not self_edit
        and set(diff) - {"notes"}
    ):
        target = S.new
    if ticket.status in PRE_COOKING:
        check(ticket.status, target, roles, Via.edit)
    frm = ticket.status
    if target != frm:
        _set_status(ticket, target, now)
        ticket.accepted_at = None
    ticket.updated = not self_edit
    bump(ticket)
    detail: dict[str, Any] = {"changes": diff, "from": str(frm), "to": str(ticket.status)}
    if self_edit:
        detail["self_approved"] = True
    log_event(db, ticket, "edited", actor.user_id, detail, now)
    if sync_menu and ticket.menu_id is not None:
        await _sync_menu(db, ticket)
    if cook is not None:
        await notify.emit(
            db,
            "ticket_updated",
            household,
            ticket=ticket,
            assignee=cook,
            actor_user_id=actor.user_id,
            params=ticket_params(household, ticket, cook, changes=_changes_line(diff)),
            now=now,
        )
    return ticket


def _changes_line(diff: Mapping[str, Any]) -> str:
    names = {
        "dishes": "Dishes",
        "eaters": "Kaun kha raha hai",
        "guests": "Mehmaan",
        "servings": "Servings",
        "due_at": "Time",
        "notes": "Note",
    }
    return ", ".join(names.get(k, k) for k in diff) or "Badlav"


async def _apply_changes(
    db: AsyncSession, household: Household, ticket: Ticket, changes: Mapping[str, Any]
) -> dict[str, Any]:
    """Apply editable fields to the snapshot; return {field: {before, after}} for real changes."""
    diff: dict[str, Any] = {}
    recompute = False
    if changes.get("dishes") is not None:
        ids = menu_svc.parse_uuid_list(changes["dishes"])
        plan = await menu_svc.plan_for(
            db,
            household,
            ids,
            [e["member_id"] for e in ticket.eaters or []],
            ticket.guests or {},
        )
        if len(plan.dishes) != len(ids):
            raise AppError(
                "unknown_recipe",
                "Some dishes are not available.",
                "Kuch dishes uplabdh nahi hain.",
                status_code=422,
            )
        before = [d["name"] for d in ticket.dishes or []]
        after = [d["name"] for d in plan.dishes]
        if [d["recipe_id"] for d in ticket.dishes or []] != [d["recipe_id"] for d in plan.dishes]:
            diff["dishes"] = {"before": before, "after": after}
            ticket.dishes = plan.dishes
    if changes.get("eaters") is not None:
        members = await menu_svc.active_members(db, household)
        by_id = {str(m.id): m for m in members}
        eater_ids = [str(i) for i in menu_svc.parse_uuid_list(changes["eaters"])]
        unknown = [i for i in eater_ids if i not in by_id]
        if unknown:
            raise NotFound(details={"member_ids": unknown})
        refs = [menu_svc.eater_ref(by_id[i]) for i in eater_ids]
        if [e["member_id"] for e in ticket.eaters or []] != eater_ids:
            diff["eaters"] = {
                "before": [e["name"] for e in ticket.eaters or []],
                "after": [e["name"] for e in refs],
            }
            ticket.eaters = refs
            recompute = True
    if changes.get("guests") is not None:
        g = menu_svc.normalise_guests(changes["guests"])
        if g != (ticket.guests or {}):
            diff["guests"] = {"before": ticket.guests, "after": g}
            ticket.guests = g
            recompute = True
    if changes.get("servings") is not None:
        value = Decimal(str(changes["servings"])).quantize(Decimal("0.01"))
        if value != ticket.servings:
            diff["servings"] = {"before": float(ticket.servings), "after": float(value)}
            ticket.servings = value
            recompute = False
    elif recompute:
        members = await menu_svc.active_members(db, household)
        by_id = {str(m.id): m for m in members}
        eaters = [by_id[e["member_id"]] for e in ticket.eaters or [] if e["member_id"] in by_id]
        value = menu_svc.compute_servings(eaters, ticket.guests or {})
        if value != ticket.servings:
            diff["servings"] = {"before": float(ticket.servings), "after": float(value)}
            ticket.servings = value
    if changes.get("due_at") is not None and changes["due_at"] != ticket.due_at:
        diff["due_at"] = {
            "before": ticket.due_at.isoformat(),
            "after": changes["due_at"].isoformat(),
        }
        ticket.due_at = changes["due_at"]
    if "notes" in changes and changes["notes"] != ticket.notes:
        diff["notes"] = {"before": ticket.notes, "after": changes["notes"]}
        ticket.notes = changes["notes"]
    return diff


async def _sync_menu(db: AsyncSession, ticket: Ticket) -> None:
    menu = await db.get(Menu, ticket.menu_id) if ticket.menu_id else None
    if menu is None:
        return
    ids = [uuid.UUID(d["recipe_id"]) for d in ticket.dishes or []]
    await menu_svc.set_dishes(db, menu, ids)
    menu.eaters = [e["member_id"] for e in ticket.eaters or []]
    menu.guests = dict(ticket.guests or {})
    menu.servings = ticket.servings
    menu.due_at = ticket.due_at
    menu.notes = ticket.notes
    menu_svc.bump(menu)


# ---- claim (K16) ----


async def _claimant_cook(db: AsyncSession, household: Household, actor: Actor) -> Cook:
    """The claimant's family-cook role, created on first claim ("Chef for the day")."""
    membership = (
        await db.execute(
            select(HouseholdMembership).where(
                HouseholdMembership.user_id == actor.user_id,
                HouseholdMembership.household_id == household.id,
                HouseholdMembership.status == MembershipStatus.active,
            )
        )
    ).scalar_one()
    if membership.cook_id is not None:
        cook = await db.get(Cook, membership.cook_id)
        if cook is not None and cook.removed_at is None:
            return cook
    member = await db.get(Member, membership.member_id) if membership.member_id else None
    user = await db.get(User, actor.user_id)
    cook = Cook(
        household_id=household.id,
        kind=CookKind.family,
        name=(member.name if member else None) or (user.name if user else None) or "Chef",
        member_id=membership.member_id,
        user_id=actor.user_id,
        login_mode=CookLoginMode.own,
        on_duty=True,
    )
    db.add(cook)
    await db.flush()
    membership.cook_id = cook.id
    return cook


async def claim(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    actor: Actor,
    now: datetime | None = None,
) -> Ticket:
    """First claim wins: the UPDATE is guarded by the version the caller loaded (a concurrent
    claim fails with StaleDataError -> 409)."""
    now = now or utcnow()
    if not can(actor, Action.claim_chef):
        raise Forbidden(details={"action": Action.claim_chef.value})
    if ticket.status != S.unassigned:
        raise Conflict(
            "already_claimed",
            "Somebody already took this ticket.",
            "Ye ticket kisi aur ne le liya hai.",
            details={"status": str(ticket.status)},
        )
    check(ticket.status, S.accepted, roles_for(actor, ticket, None), Via.claim)
    cook = await _claimant_cook(db, household, actor)
    ticket.assignee_cook_id = cook.id
    await _apply(db, household, ticket, S.accepted, actor.user_id, now)
    log_event(db, ticket, "claimed", actor.user_id, {"assignee_cook_id": str(cook.id)}, now)
    await db.flush()
    user = await db.get(User, actor.user_id)
    await notify.emit(
        db,
        "chef_claimed",
        household,
        ticket=ticket,
        actor_user_id=actor.user_id,
        params=ticket_params(
            household, ticket, cook, author=cook.name or (user.name if user else "")
        ),
        now=now,
    )
    return ticket


# ---- item out, messages ----


async def check_item_out(
    db: AsyncSession, ticket: Ticket, ingredient_id: uuid.UUID, actor: Actor
) -> Ingredient:
    """Permission (assignee, §2.1 mark_item_out), open ticket, known ingredient."""
    cook = await ticket_cook(db, ticket)
    if not (
        acts_as_assignee(actor, cook)
        or can(actor, Action.mark_item_out, resource_for(ticket, cook, actor))
    ):
        raise Forbidden(details={"action": Action.mark_item_out.value})
    if ticket.status not in OPEN_STATUSES:
        raise _closed_error()
    ingredient = await db.get(Ingredient, ingredient_id)
    if ingredient is None:
        raise NotFound("ingredient_not_found")
    return ingredient


async def mark_item_out(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    ingredient_id: uuid.UUID,
    actor: Actor,
    now: datetime | None = None,
    *,
    detail: Mapping[str, Any] | None = None,
) -> Ticket:
    """``detail`` (Phase 6: the ladder step and issue id) is merged into the change log."""
    now = now or utcnow()
    ingredient = await check_item_out(db, ticket, ingredient_id, actor)
    cook = await ticket_cook(db, ticket)
    ticket.stock_issue_open = True
    bump(ticket)
    log_event(
        db,
        ticket,
        "item_out",
        actor.user_id,
        {"ingredient_id": str(ingredient.id), "name": ingredient.name_en, **(detail or {})},
        now,
    )
    await notify.emit(
        db,
        "stock_issue",
        household,
        ticket=ticket,
        assignee=cook,
        actor_user_id=actor.user_id,
        params=ticket_params(household, ticket, cook, item=ingredient.name_en),
        now=now,
    )
    return ticket


async def post_message(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    actor: Actor,
    text: str,
    now: datetime | None = None,
) -> TicketMessage:
    now = now or utcnow()
    cook = await ticket_cook(db, ticket)
    # Messages by the cook's own login go to the family; everything else goes to the cook.
    from_cook = cook is not None and cook.user_id == actor.user_id
    if not (
        acts_as_assignee(actor, cook)
        or can(actor, Action.message_ticket, resource_for(ticket, cook, actor))
    ):
        raise Forbidden(details={"action": Action.message_ticket.value})
    msg = TicketMessage(
        ticket_id=ticket.id, author_user_id=actor.user_id, text=text, created_at=now
    )
    db.add(msg)
    await db.flush()
    log_event(db, ticket, "message", actor.user_id, {"message_id": str(msg.id)}, now)
    user = await db.get(User, actor.user_id)
    author = (cook.name if from_cook and cook is not None else None) or (
        user.name if user and user.name else "Ghar se"
    )
    await notify.emit(
        db,
        "cook_message" if from_cook else "family_message",
        household,
        ticket=ticket,
        assignee=cook,
        actor_user_id=actor.user_id,
        params=ticket_params(household, ticket, cook, author=author, text=text[:180]),
        now=now,
    )
    return msg


# ---- read model ----


def _issue_detail(name: str, issue: Any, approval: Any) -> str:
    payload = dict(approval.payload or {}) if approval is not None else {}
    if payload.get("action") == "swap":
        return f"{name} → {payload.get('substitute_name')}"
    if payload.get("action") == "change_dish":
        return f"Dish → {payload.get('recipe_name')} ({name} khatam)"
    if issue.resolution is not None and str(issue.resolution) == "skip":
        return f"{name} ke bina"
    return f"{name} khatam"


def apply_swaps(
    items: list[dict[str, Any]],
    dishes: Sequence[Mapping[str, Any]],
    stock: menu_svc.StockLookup,
) -> list[dict[str, Any]]:
    """Required items after the ladder: a skipped item drops out, a swapped one is replaced
    by its substitute (Phase 6, FR-O3)."""
    swaps = [s for d in dishes for s in d.get("swaps") or []]
    if not swaps:
        return items
    out = list(items)
    for sw in swaps:
        src = str(sw.get("from_ingredient_id"))
        out = [i for i in out if i["ingredient_id"] != src]
        to = sw.get("to_ingredient_id")
        if to and all(i["ingredient_id"] != str(to) for i in out):
            out.append(
                {
                    "ingredient_id": str(to),
                    "display_text": str(sw.get("to_name") or ""),
                    "status": stock.status(uuid.UUID(str(to))),
                }
            )
    return out


def current_issue(issues: Sequence[Mapping[str, Any]], now: datetime) -> dict[str, Any] | None:
    """The app's single ``stock_issue`` card: the latest open issue, else the latest one.
    state: open | pending_approval | timed_out | resolved."""
    if not issues:
        return None
    open_ = [i for i in issues if i["resolved_at"] is None]
    issue = (open_ or list(issues))[-1]
    approval = issue.get("approval")
    if issue["resolved_at"] is not None:
        state = "resolved"
    elif approval is not None and approval["decision"] == "expired":
        state = "timed_out"
    elif approval is not None and approval["decision"] is None:
        expires = approval.get("expires_at")
        state = "timed_out" if expires is not None and expires <= now else "pending_approval"
    else:
        state = "open"
    return {
        "ingredient_id": issue["ingredient_id"],
        "name": issue["name"],
        "state": state,
        "action": issue["resolution"] or (approval or {}).get("action"),
        "approval_id": approval["id"] if approval is not None else None,
        "expires_at": approval.get("expires_at") if approval is not None else None,
        "detail": issue.get("detail") or "",
    }


async def stock_issues_view(db: AsyncSession, ticket: Ticket) -> list[dict[str, Any]]:
    from app.models import Approval, TicketStockIssue

    rows = list(
        (
            await db.execute(
                select(TicketStockIssue, Ingredient.name_en)
                .join(Ingredient, Ingredient.id == TicketStockIssue.ingredient_id)
                .where(TicketStockIssue.ticket_id == ticket.id)
                .order_by(TicketStockIssue.created_at, TicketStockIssue.id)
            )
        ).all()
    )
    out = []
    for issue, name in rows:
        approval = await db.get(Approval, issue.approval_id) if issue.approval_id else None
        out.append(
            {
                "id": issue.id,
                "ingredient_id": issue.ingredient_id,
                "name": name,
                "step": str(issue.step),
                "resolution": str(issue.resolution) if issue.resolution else None,
                "substitute_ingredient_id": issue.substitute_ingredient_id,
                "new_recipe_id": issue.new_recipe_id,
                "detail": _issue_detail(name, issue, approval),
                "approval": {
                    "id": approval.id,
                    "action": (approval.payload or {}).get("action"),
                    "type": str(approval.type),
                    "decision": str(approval.decision) if approval.decision else None,
                    "auto": approval.auto,
                    "expires_at": approval.expires_at,
                }
                if approval is not None
                else None,
                "created_at": issue.created_at,
                "resolved_at": issue.resolved_at,
            }
        )
    return out


async def ticket_view(
    db: AsyncSession, ticket: Ticket, actor: Actor | None = None
) -> dict[str, Any]:
    cook = await ticket_cook(db, ticket)
    events = list(
        (
            await db.execute(
                select(TicketEvent)
                .where(TicketEvent.ticket_id == ticket.id)
                .order_by(TicketEvent.at, TicketEvent.id)
            )
        ).scalars()
    )
    user_ids = {e.by_user_id for e in events if e.by_user_id}
    names: dict[uuid.UUID, str | None] = {}
    if user_ids:
        for uid, name in (
            await db.execute(select(User.id, User.name).where(User.id.in_(user_ids)))
        ).all():
            names[uid] = name
    roles = roles_for(actor, ticket, cook) if actor is not None else frozenset()
    recipe_ids = menu_svc.parse_uuid_list(d.get("recipe_id") for d in ticket.dishes or [])
    recipes = await menu_svc.load_recipes(db, recipe_ids)
    household = await db.get(Household, ticket.household_id)
    assert household is not None
    # F-5.6-04: stock status is read at render time, not stored on the ticket.
    stock = await menu_svc.stock_lookup(db, household)
    items = apply_swaps(
        menu_svc.required_items([recipes[i] for i in recipe_ids if i in recipes], stock),
        ticket.dishes or [],
        stock,
    )
    issues = await stock_issues_view(db, ticket)
    return {
        "id": ticket.id,
        "menu_id": ticket.menu_id,
        "date": ticket.date,
        "slot": ticket.slot,
        "due_at": ticket.due_at,
        "status": str(ticket.status),
        "assignee": menu_svc.assignee_ref(cook),
        "dishes": list(ticket.dishes or []),
        "eaters": list(ticket.eaters or []),
        "guests": dict(ticket.guests or {}),
        "servings": float(ticket.servings or 0),
        "notes": ticket.notes,
        "stock_issue_open": ticket.stock_issue_open,
        "stock_issues": issues,
        "stock_issue": current_issue(issues, utcnow()),
        "required_items": items,
        "updated": ticket.updated,
        "accepted_at": ticket.accepted_at,
        "started_at": ticket.started_at,
        "completed_at": ticket.completed_at,
        "completed_by": ticket.completed_by,
        "rated_at": ticket.rated_at,
        "cancel_reason": ticket.cancel_reason,
        "confirmed_by": ticket.confirmed_by_user_id,
        "allowed_next": [str(s) for s in allowed_next(ticket.status, roles)],
        "change_log": [
            {
                "at": e.at,
                "by": {
                    "user_id": e.by_user_id,
                    "name": (names.get(e.by_user_id) or "") if e.by_user_id else "System",
                },
                "action": e.action,
                "detail": e.detail or {},
            }
            for e in events
        ],
        "version": ticket.version,
    }
