"""The ticket state table (F-5.7-02 / contract §Tickets), unit-level: every legal row succeeds
for its actors, every other (from, to) pair is 409 with the caller's allowed next states."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from app.core.errors import Forbidden
from app.models import Cook, CookKind, CookLoginMode, Ticket, TicketStatus
from app.permissions import Actor
from app.services.tickets import (
    STATE_TABLE,
    InvalidTransition,
    Role,
    Via,
    allowed_next,
    check,
    initial_status,
    roles_for,
)

S = TicketStatus
ALL = list(TicketStatus)
ME = uuid.UUID(int=1)
OTHER = uuid.UUID(int=2)


def _legal(via: Via) -> set[tuple[TicketStatus, TicketStatus]]:
    return {(f, t) for row in STATE_TABLE if row.via == via for f in row.frm for t in row.to}


@pytest.mark.parametrize(
    ("frm", "to", "actors", "via"),
    [
        (f, t, row.actors, row.via)
        for row in STATE_TABLE
        for f in sorted(row.frm)
        for t in sorted(row.to)
    ],
    ids=lambda v: str(v) if not isinstance(v, frozenset) else "+".join(sorted(v)),
)
def test_every_legal_row_succeeds_for_each_of_its_actors(
    frm: TicketStatus, to: TicketStatus, actors: frozenset[Role], via: Via
) -> None:
    for actor in actors:
        row = check(frm, to, frozenset({actor}), via)
        assert frm in row.frm and to in row.to


# Everyone who can act through the transitions endpoint at once: the allowed list is then the
# full set of API rows out of a status.
EVERYONE = frozenset(
    {Role.assignee, Role.family_cook_own, Role.admin, Role.confirmer, Role.claimant}
)

EXPECTED_API_NEXT: dict[TicketStatus, list[TicketStatus]] = {
    S.new: [S.accepted, S.cancelled],
    S.unassigned: [S.new, S.accepted, S.cancelled],
    S.accepted: [S.cooking, S.cancelled],
    S.cooking: [S.ready, S.completed, S.cancelled],
    S.ready: [S.completed],
    S.completed: [],
    S.not_confirmed: [S.completed, S.cancelled],
    S.cancelled: [],
}


@pytest.mark.parametrize("status", ALL)
def test_allowed_next_matches_the_table(status: TicketStatus) -> None:
    assert allowed_next(status, EVERYONE) == EXPECTED_API_NEXT[status]


@pytest.mark.parametrize(
    ("frm", "to"),
    [(f, t) for f in ALL for t in ALL if (f, t) not in _legal(Via.api)],
)
def test_every_illegal_pair_is_409_with_allowed(frm: TicketStatus, to: TicketStatus) -> None:
    with pytest.raises(InvalidTransition) as exc:
        check(frm, to, EVERYONE, Via.api)
    assert exc.value.status_code == 409
    assert exc.value.code == "invalid_transition"
    assert exc.value.extra["allowed"] == sorted(str(s) for s in EXPECTED_API_NEXT[frm])


# Per-role allowed lists (what each caller's buttons show).
ROLE_NEXT: list[tuple[Role, TicketStatus, list[TicketStatus]]] = [
    (Role.assignee, S.new, [S.accepted]),
    (Role.assignee, S.accepted, [S.cooking]),
    (Role.assignee, S.cooking, [S.ready, S.completed]),
    (Role.assignee, S.ready, [S.completed]),
    (Role.admin, S.new, [S.cancelled]),
    (Role.admin, S.unassigned, [S.new, S.accepted, S.cancelled]),
    (Role.admin, S.cooking, [S.completed, S.cancelled]),
    (Role.admin, S.not_confirmed, [S.completed, S.cancelled]),
    (Role.confirmer, S.new, [S.cancelled]),
    (Role.confirmer, S.cooking, []),
    (Role.family_cook_own, S.accepted, [S.cancelled]),
    (Role.claimant, S.unassigned, []),  # claiming is POST /claim, not a transition
]


@pytest.mark.parametrize(("role", "status", "expected"), ROLE_NEXT)
def test_allowed_next_per_role(
    role: Role, status: TicketStatus, expected: list[TicketStatus]
) -> None:
    assert allowed_next(status, frozenset({role})) == expected


def test_legal_pair_for_the_wrong_role_is_403() -> None:
    with pytest.raises(Forbidden) as exc:
        check(S.new, S.accepted, frozenset({Role.admin}), Via.api)
    assert exc.value.details["allowed"] == ["cancelled"]
    with pytest.raises(Forbidden):
        check(S.cooking, S.cancelled, frozenset({Role.confirmer}), Via.api)


def test_system_rows_are_not_reachable_from_the_api() -> None:
    for frm, to in [(S.accepted, S.not_confirmed), (S.new, S.unassigned)]:
        with pytest.raises(InvalidTransition):
            check(frm, to, EVERYONE, Via.api)
        check(frm, to, frozenset({Role.system}), Via.system)


def test_cooking_cancel_requires_reason_flag() -> None:
    rows = [r for r in STATE_TABLE if S.cooking in r.frm and S.cancelled in r.to]
    assert len(rows) == 1 and rows[0].reason_required and rows[0].actors == {Role.admin}


# ---- actor roles --------------------------------------------------------------------------


def _ticket(status: TicketStatus, confirmed_by: uuid.UUID | None = OTHER) -> Ticket:
    return Ticket(status=status, confirmed_by_user_id=confirmed_by)


def _cook(kind: CookKind, user: uuid.UUID | None, mode: CookLoginMode = CookLoginMode.own) -> Cook:
    return Cook(id=uuid.uuid4(), kind=kind, user_id=user, login_mode=mode, on_duty=True)


def test_roles_hired_cook_owns_only_her_ticket() -> None:
    cook_actor = Actor(user_id=ME, cook_kind=CookKind.hired)
    assert roles_for(cook_actor, _ticket(S.new), _cook(CookKind.hired, ME)) == {Role.assignee}
    assert roles_for(cook_actor, _ticket(S.new), _cook(CookKind.hired, OTHER)) == frozenset()


def test_roles_member_confirmer_only_before_accepted() -> None:
    member = Actor(user_id=ME, is_member=True)
    hired = _cook(CookKind.hired, OTHER)
    assert Role.confirmer in roles_for(member, _ticket(S.new, ME), hired)
    assert Role.confirmer in roles_for(member, _ticket(S.unassigned, ME), None)
    assert Role.confirmer not in roles_for(member, _ticket(S.accepted, ME), hired)
    assert Role.confirmer not in roles_for(member, _ticket(S.new, OTHER), hired)
    assert Role.claimant in roles_for(member, _ticket(S.unassigned), None)


def test_roles_admin_acts_for_via_admin_cooks() -> None:
    admin = Actor(user_id=ME, is_admin=True, is_member=True)
    mummy = _cook(CookKind.family, None, CookLoginMode.via_admin)
    roles = roles_for(admin, _ticket(S.accepted), mummy)
    assert {Role.admin, Role.assignee, Role.family_cook_own} <= roles
    whatsapp_only = _cook(CookKind.hired, None, CookLoginMode.via_admin)
    assert Role.assignee in roles_for(admin, _ticket(S.new), whatsapp_only)
    assert Role.assignee not in roles_for(admin, _ticket(S.new), _cook(CookKind.hired, OTHER))


def test_system_actor() -> None:
    assert roles_for(None, _ticket(S.accepted), None) == {Role.system}


# ---- initial state rule -------------------------------------------------------------------

DUE = datetime(2026, 10, 1, 8, 0, tzinfo=UTC)


def test_initial_status_rules() -> None:
    hired = _cook(CookKind.hired, OTHER)
    family = _cook(CookKind.family, OTHER)
    me_family = _cook(CookKind.family, ME)
    assert initial_status(hired, [hired], DUE, ME).status == S.new
    assert initial_status(family, [family], DUE, ME).status == S.accepted
    self_ = initial_status(me_family, [me_family], DUE, ME)
    assert (self_.status, self_.reason) == (S.accepted, "self")
    assert initial_status(None, [], DUE, ME).status == S.unassigned


def test_initial_status_off_duty_goes_to_on_duty_backup_else_unassigned() -> None:
    hired = _cook(CookKind.hired, OTHER)
    hired.on_duty = False
    backup = _cook(CookKind.family, None, CookLoginMode.via_admin)
    backup.is_backup = True
    a = initial_status(hired, [hired, backup], DUE, ME)
    assert (a.status, a.cook, a.reason) == (S.accepted, backup, "off_duty_backup")
    backup.on_duty = False
    a = initial_status(hired, [hired, backup], DUE, ME)
    assert (a.status, a.cook, a.reason) == (S.unassigned, None, "off_duty_unassigned")
    # Back before the due time: still his ticket.
    hired.off_duty_until = DUE - timedelta(hours=1)
    assert initial_status(hired, [hired, backup], DUE, ME).cook is hired
