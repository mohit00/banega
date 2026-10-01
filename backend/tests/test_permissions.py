"""Contract tests for the §2.1 permission table (F-2-02): one test per table cell.

Each role is tested in isolation (a single role flag set), so every parametrised case maps to
exactly one cell. Conditional cells ("own tickets", "if setting on") get a positive and a
negative case. Combined roles and the self-approval rule are tested at the end.
"""

from __future__ import annotations

import uuid
from dataclasses import replace

import pytest

from app.models.enums import CookKind
from app.permissions import (
    APPROVAL_ACTIONS,
    TABLE,
    Action,
    Actor,
    Resource,
    can,
    resolve_approval,
)

ME = uuid.UUID(int=1)
OTHER = uuid.UUID(int=2)
MY_MEMBER = uuid.UUID(int=11)
OTHER_MEMBER = uuid.UUID(int=12)

ROLES: dict[str, Actor] = {
    "admin": Actor(user_id=ME, is_admin=True, member_id=MY_MEMBER),
    "member": Actor(user_id=ME, is_member=True, member_id=MY_MEMBER),
    "hired_cook": Actor(user_id=ME, cook_kind=CookKind.hired),
    "family_cook": Actor(user_id=ME, cook_kind=CookKind.family, member_id=MY_MEMBER),
}

R_NONE = Resource()
R_OWN_PROFILE = Resource(owner_user_id=ME)
R_OWN_MEMBER = Resource(owner_member_id=MY_MEMBER)
R_OTHER_PROFILE = Resource(owner_user_id=OTHER)
R_OTHER_MEMBER = Resource(owner_member_id=OTHER_MEMBER)
R_ASSIGNED_ME = Resource(assignee_user_id=ME, ticket_status="accepted")
R_ASSIGNED_OTHER = Resource(assignee_user_id=OTHER, ticket_status="accepted")
R_CONFIRMED_ME_NEW = Resource(confirmed_by_user_id=ME, ticket_status="new")
R_CONFIRMED_ME_UNASSIGNED = Resource(confirmed_by_user_id=ME, ticket_status="unassigned")
R_CONFIRMED_ME_ACCEPTED = Resource(confirmed_by_user_id=ME, ticket_status="accepted")
R_CONFIRMED_OTHER_NEW = Resource(confirmed_by_user_id=OTHER, ticket_status="new")
R_REQ_ME = Resource(requested_by_user_id=ME)
R_REQ_OTHER = Resource(requested_by_user_id=OTHER)

# (action, role, resource, household-setting overrides, expected)
Case = tuple[Action, str, Resource, dict[str, bool], bool]
A = Action

CELLS: list[Case] = [
    # Edit household, cook setup, settings, subscription: Admin only.
    (A.edit_household, "admin", R_NONE, {}, True),
    (A.edit_household, "member", R_NONE, {}, False),
    (A.edit_household, "hired_cook", R_NONE, {}, False),
    (A.edit_household, "family_cook", R_NONE, {}, False),
    # Add/remove members; edit any profile: Admin only.
    (A.manage_members, "admin", R_NONE, {}, True),
    (A.manage_members, "member", R_NONE, {}, False),
    (A.manage_members, "hired_cook", R_NONE, {}, False),
    (A.manage_members, "family_cook", R_NONE, {}, False),
    # Edit own profile: Admin yes; member own only; hired no; family cook own only.
    (A.edit_own_profile, "admin", R_OTHER_PROFILE, {}, True),
    (A.edit_own_profile, "member", R_OWN_PROFILE, {}, True),
    (A.edit_own_profile, "member", R_OWN_MEMBER, {}, True),
    (A.edit_own_profile, "member", R_OTHER_PROFILE, {}, False),
    (A.edit_own_profile, "member", R_OTHER_MEMBER, {}, False),
    (A.edit_own_profile, "hired_cook", R_OWN_PROFILE, {}, False),
    (A.edit_own_profile, "family_cook", R_OWN_PROFILE, {}, True),
    (A.edit_own_profile, "family_cook", R_OTHER_MEMBER, {}, False),
    # Ask Maharaj: Admin, member, family cook yes; hired cook no (cook mode).
    (A.ask_maharaj, "admin", R_NONE, {}, True),
    (A.ask_maharaj, "member", R_NONE, {}, True),
    (A.ask_maharaj, "hired_cook", R_NONE, {}, False),
    (A.ask_maharaj, "family_cook", R_NONE, {}, True),
    # Add/remove dishes on a day menu: same row.
    (A.edit_day_menu, "admin", R_NONE, {}, True),
    (A.edit_day_menu, "member", R_NONE, {}, True),
    (A.edit_day_menu, "hired_cook", R_NONE, {}, False),
    (A.edit_day_menu, "family_cook", R_NONE, {}, True),
    # Confirm menu: admin yes; member if "Members can send to cook"; hired no; family own.
    (A.confirm_menu, "admin", R_NONE, {"members_can_send_to_cook": False}, True),
    (A.confirm_menu, "member", R_NONE, {"members_can_send_to_cook": True}, True),
    (A.confirm_menu, "member", R_NONE, {"members_can_send_to_cook": False}, False),
    (A.confirm_menu, "hired_cook", R_ASSIGNED_ME, {}, False),
    (A.confirm_menu, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.confirm_menu, "family_cook", R_ASSIGNED_OTHER, {}, False),
    # Edit a ticket: admin yes; member only confirmed-by-them before Accepted; hired no;
    # family cook own tickets.
    (A.edit_ticket, "admin", R_CONFIRMED_OTHER_NEW, {}, True),
    (A.edit_ticket, "member", R_CONFIRMED_ME_NEW, {}, True),
    (A.edit_ticket, "member", R_CONFIRMED_ME_UNASSIGNED, {}, True),
    (A.edit_ticket, "member", R_CONFIRMED_ME_ACCEPTED, {}, False),
    (A.edit_ticket, "member", R_CONFIRMED_OTHER_NEW, {}, False),
    (A.edit_ticket, "hired_cook", R_ASSIGNED_ME, {}, False),
    (A.edit_ticket, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.edit_ticket, "family_cook", R_ASSIGNED_OTHER, {}, False),
    # Cancel a ticket: same row.
    (A.cancel_ticket, "admin", R_CONFIRMED_OTHER_NEW, {}, True),
    (A.cancel_ticket, "member", R_CONFIRMED_ME_NEW, {}, True),
    (A.cancel_ticket, "member", R_CONFIRMED_ME_ACCEPTED, {}, False),
    (A.cancel_ticket, "member", R_CONFIRMED_OTHER_NEW, {}, False),
    (A.cancel_ticket, "hired_cook", R_ASSIGNED_ME, {}, False),
    (A.cancel_ticket, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.cancel_ticket, "family_cook", R_ASSIGNED_OTHER, {}, False),
    # Accept/start a ticket: admin no ("may mark Completed" only); member no; cooks own.
    (A.accept_ticket, "admin", R_ASSIGNED_OTHER, {}, False),
    (A.accept_ticket, "member", R_ASSIGNED_ME, {}, False),
    (A.accept_ticket, "hired_cook", R_ASSIGNED_ME, {}, True),
    (A.accept_ticket, "hired_cook", R_ASSIGNED_OTHER, {}, False),
    (A.accept_ticket, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.accept_ticket, "family_cook", R_ASSIGNED_OTHER, {}, False),
    # Complete a ticket: admin may mark Completed; member no; cooks own.
    (A.complete_ticket, "admin", R_ASSIGNED_OTHER, {}, True),
    (A.complete_ticket, "member", R_ASSIGNED_ME, {}, False),
    (A.complete_ticket, "hired_cook", R_ASSIGNED_ME, {}, True),
    (A.complete_ticket, "hired_cook", R_ASSIGNED_OTHER, {}, False),
    (A.complete_ticket, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.complete_ticket, "family_cook", R_ASSIGNED_OTHER, {}, False),
    # Mark item Out: cooks on own tickets only.
    (A.mark_item_out, "admin", R_ASSIGNED_OTHER, {}, False),
    (A.mark_item_out, "member", R_ASSIGNED_ME, {}, False),
    (A.mark_item_out, "hired_cook", R_ASSIGNED_ME, {}, True),
    (A.mark_item_out, "hired_cook", R_ASSIGNED_OTHER, {}, False),
    (A.mark_item_out, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.mark_item_out, "family_cook", R_ASSIGNED_OTHER, {}, False),
    # Approve alt recipe / swap: admin yes; member yes; hired if cook_can_approve_swaps
    # (default on); family cook self only.
    (A.approve_swap, "admin", R_REQ_OTHER, {}, True),
    (A.approve_swap, "member", R_REQ_OTHER, {}, True),
    (A.approve_swap, "hired_cook", R_REQ_ME, {"cook_can_approve_swaps": True}, True),
    (A.approve_swap, "hired_cook", R_REQ_ME, {"cook_can_approve_swaps": False}, False),
    (A.approve_swap, "family_cook", R_REQ_ME, {}, True),
    (A.approve_swap, "family_cook", R_REQ_OTHER, {}, False),
    # Approve dish change: admin yes; member yes; hired no; family cook self only.
    (A.approve_dish_change, "admin", R_REQ_OTHER, {}, True),
    (A.approve_dish_change, "member", R_REQ_OTHER, {}, True),
    (A.approve_dish_change, "hired_cook", R_REQ_ME, {}, False),
    (A.approve_dish_change, "family_cook", R_REQ_ME, {}, True),
    (A.approve_dish_change, "family_cook", R_REQ_OTHER, {}, False),
    # Raise ration request: admin, hired, family yes; member no.
    (A.raise_ration, "admin", R_NONE, {}, True),
    (A.raise_ration, "member", R_NONE, {}, False),
    (A.raise_ration, "hired_cook", R_NONE, {}, True),
    (A.raise_ration, "family_cook", R_NONE, {}, True),
    # Update stock: same row.
    (A.update_stock, "admin", R_NONE, {}, True),
    (A.update_stock, "member", R_NONE, {}, False),
    (A.update_stock, "hired_cook", R_NONE, {}, True),
    (A.update_stock, "family_cook", R_NONE, {}, True),
    # Approve ration request: admin yes; member no; hired no; family self (auto-approved).
    (A.approve_ration, "admin", R_REQ_OTHER, {}, True),
    (A.approve_ration, "member", R_REQ_OTHER, {}, False),
    (A.approve_ration, "hired_cook", R_REQ_ME, {}, False),
    (A.approve_ration, "family_cook", R_REQ_ME, {}, True),
    (A.approve_ration, "family_cook", R_REQ_OTHER, {}, False),
    # Mark Bought: same row.
    (A.mark_bought, "admin", R_REQ_OTHER, {}, True),
    (A.mark_bought, "member", R_REQ_OTHER, {}, False),
    (A.mark_bought, "hired_cook", R_REQ_ME, {}, False),
    (A.mark_bought, "family_cook", R_REQ_ME, {}, True),
    (A.mark_bought, "family_cook", R_REQ_OTHER, {}, False),
    # Rate a meal: admin, member, family yes; hired no.
    (A.rate_meal, "admin", R_NONE, {}, True),
    (A.rate_meal, "member", R_NONE, {}, True),
    (A.rate_meal, "hired_cook", R_NONE, {}, False),
    (A.rate_meal, "family_cook", R_NONE, {}, True),
    # Rate on behalf of a profile-only member: same.
    (A.rate_for_profile_member, "admin", R_NONE, {}, True),
    (A.rate_for_profile_member, "member", R_NONE, {}, True),
    (A.rate_for_profile_member, "hired_cook", R_NONE, {}, False),
    (A.rate_for_profile_member, "family_cook", R_NONE, {}, True),
    # See named ratings: admin yes; member own only; hired per F-5.10-01 (off by default);
    # family cook yes.
    (A.see_named_ratings, "admin", R_OTHER_PROFILE, {}, True),
    (A.see_named_ratings, "member", R_OWN_PROFILE, {}, True),
    (A.see_named_ratings, "member", R_OTHER_PROFILE, {}, False),
    (A.see_named_ratings, "hired_cook", R_OTHER_PROFILE, {"show_names_to_cook": False}, False),
    (A.see_named_ratings, "hired_cook", R_OTHER_PROFILE, {"show_names_to_cook": True}, True),
    (A.see_named_ratings, "family_cook", R_OTHER_PROFILE, {}, True),
    # Claim Chef for the day: admin, member, family yes; hired n/a.
    (A.claim_chef, "admin", R_NONE, {}, True),
    (A.claim_chef, "member", R_NONE, {}, True),
    (A.claim_chef, "hired_cook", R_NONE, {}, False),
    (A.claim_chef, "family_cook", R_NONE, {}, True),
    # Cook setup (add/remove cooks, primary/backup): Admin only.
    (A.manage_cooks, "admin", R_NONE, {}, True),
    (A.manage_cooks, "member", R_NONE, {}, False),
    (A.manage_cooks, "hired_cook", R_NONE, {}, False),
    (A.manage_cooks, "family_cook", R_NONE, {}, False),
    # On/Off duty: admin for anyone; member no; each cook her own only.
    (A.set_duty, "admin", R_OTHER_PROFILE, {}, True),
    (A.set_duty, "member", R_OWN_PROFILE, {}, False),
    (A.set_duty, "hired_cook", R_OWN_PROFILE, {}, True),
    (A.set_duty, "hired_cook", R_OTHER_PROFILE, {}, False),
    (A.set_duty, "family_cook", R_OWN_PROFILE, {}, True),
    (A.set_duty, "family_cook", R_OTHER_PROFILE, {}, False),
    # Ticket messages (K6): family roles on any ticket; cooks on their own tickets.
    (A.message_ticket, "admin", R_ASSIGNED_OTHER, {}, True),
    (A.message_ticket, "member", R_ASSIGNED_OTHER, {}, True),
    (A.message_ticket, "hired_cook", R_ASSIGNED_ME, {}, True),
    (A.message_ticket, "hired_cook", R_ASSIGNED_OTHER, {}, False),
    (A.message_ticket, "family_cook", R_ASSIGNED_ME, {}, True),
    (A.message_ticket, "family_cook", R_ASSIGNED_OTHER, {}, False),
]


def _case_id(c: Case) -> str:
    action, role, _, overrides, expected = c
    extra = "-".join(f"{k}={v}" for k, v in overrides.items())
    return f"{action.value}-{role}{'-' + extra if extra else ''}-{'yes' if expected else 'no'}"


@pytest.mark.parametrize("case", CELLS, ids=[_case_id(c) for c in CELLS])
def test_table_cell(case: Case) -> None:
    action, role, resource, overrides, expected = case
    actor = replace(ROLES[role], **overrides)
    # Include the resource index in the message so failures point at the cell.
    assert can(actor, action, resource) is expected, _case_id(case)


def test_every_action_and_role_has_a_cell() -> None:
    covered = {(c[0], c[1]) for c in CELLS}
    missing = [(a.value, r) for a in Action for r in ROLES if (a, r) not in covered]
    assert missing == []
    assert set(TABLE) == set(Action)


def test_no_role_means_no_permission() -> None:
    nobody = Actor(user_id=ME)
    assert not any(can(nobody, a, R_ASSIGNED_ME) for a in Action)


def test_family_cook_who_is_also_member_gets_member_rights() -> None:
    actor = Actor(user_id=ME, is_member=True, cook_kind=CookKind.family)
    # Member row allows confirming any menu while the setting is on.
    assert can(actor, A.confirm_menu, R_ASSIGNED_OTHER)
    # Member row allows approving someone else's dish change.
    assert can(actor, A.approve_dish_change, R_REQ_OTHER)
    # Neither role approves someone else's ration.
    assert not can(actor, A.approve_ration, R_REQ_OTHER)


def test_admin_who_is_also_cook_can_accept_own_ticket() -> None:
    actor = Actor(user_id=ME, is_admin=True, cook_kind=CookKind.family)
    assert can(actor, A.accept_ticket, R_ASSIGNED_ME)
    assert not can(actor, A.accept_ticket, R_ASSIGNED_OTHER)


# ---- self-approval rule (F-2-04 / FR-K19) ----------------------------------------------


@pytest.mark.parametrize("action", sorted(APPROVAL_ACTIONS))
def test_admin_self_approval_is_skipped_and_flagged(action: Action) -> None:
    outcome = resolve_approval(ROLES["admin"], action, R_REQ_ME)
    assert outcome.allowed
    assert outcome.self_approved
    assert outcome.skipped


@pytest.mark.parametrize("action", sorted(APPROVAL_ACTIONS))
def test_approving_someone_else_is_not_self_approved(action: Action) -> None:
    outcome = resolve_approval(ROLES["admin"], action, R_REQ_OTHER)
    assert outcome.allowed
    assert not outcome.self_approved


def test_family_cook_ration_is_auto_approved() -> None:
    outcome = resolve_approval(ROLES["family_cook"], A.approve_ration, R_REQ_ME)
    assert outcome.allowed and outcome.self_approved


def test_hired_cook_cannot_self_approve_ration() -> None:
    outcome = resolve_approval(ROLES["hired_cook"], A.approve_ration, R_REQ_ME)
    assert not outcome.allowed
    assert not outcome.self_approved


def test_resolve_approval_rejects_non_approval_actions() -> None:
    with pytest.raises(ValueError):
        resolve_approval(ROLES["admin"], A.edit_household, R_NONE)
