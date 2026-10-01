"""The single canonical permission and approval table (FRD review F-2-02, §2.1).

Every endpoint that changes household state asks ``can(actor, action, resource)``. Roles are
not exclusive (F-8-01): a user can be admin, adult member and family cook at once, and the
answer is "yes" if **any** role the actor holds allows the action.

The table itself is ``TABLE`` below (one row per action, one rule per role column), copied
from docs/frd-review.md F-2-02. Cells are the proposed defaults; household settings
(members_can_send_to_cook, cook_can_approve_swaps, show_names_to_cook) toggle three of them.

Self-approval rule (F-2-04 / FR-K19): when the approver is the requester and the actor is
eligible to approve, the approval step is skipped and flagged ``self_approved`` for the
change log. See :func:`resolve_approval`.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from dataclasses import dataclass
from enum import StrEnum

from app.models.enums import CookKind


class Action(StrEnum):
    edit_household = "edit_household"
    manage_members = "manage_members"
    edit_own_profile = "edit_own_profile"
    ask_maharaj = "ask_maharaj"
    edit_day_menu = "edit_day_menu"
    confirm_menu = "confirm_menu"
    edit_ticket = "edit_ticket"
    cancel_ticket = "cancel_ticket"
    accept_ticket = "accept_ticket"
    complete_ticket = "complete_ticket"
    mark_item_out = "mark_item_out"
    approve_swap = "approve_swap"
    approve_dish_change = "approve_dish_change"
    raise_ration = "raise_ration"
    update_stock = "update_stock"
    approve_ration = "approve_ration"
    mark_bought = "mark_bought"
    rate_meal = "rate_meal"
    rate_for_profile_member = "rate_for_profile_member"
    see_named_ratings = "see_named_ratings"
    claim_chef = "claim_chef"
    # Phase 5 additions (same §2.1 semantics; see the TABLE comments).
    manage_cooks = "manage_cooks"
    set_duty = "set_duty"
    message_ticket = "message_ticket"


APPROVAL_ACTIONS: frozenset[Action] = frozenset(
    {Action.approve_swap, Action.approve_dish_change, Action.approve_ration, Action.mark_bought}
)

# Ticket statuses before a hired cook accepts (F-5.7-02). Members may edit/cancel only here.
PRE_ACCEPT_STATUSES: frozenset[str] = frozenset({"new", "unassigned"})


@dataclass(frozen=True, slots=True)
class Actor:
    """Who is acting, derived from HouseholdMembership + Cook + household settings."""

    user_id: uuid.UUID
    household_id: uuid.UUID | None = None
    is_admin: bool = False
    is_member: bool = False
    cook_kind: CookKind | None = None
    member_id: uuid.UUID | None = None
    # Household settings that change table cells.
    members_can_send_to_cook: bool = True
    cook_can_approve_swaps: bool = True
    show_names_to_cook: bool = False

    @property
    def is_hired_cook(self) -> bool:
        return self.cook_kind == CookKind.hired

    @property
    def is_family_cook(self) -> bool:
        return self.cook_kind == CookKind.family


@dataclass(frozen=True, slots=True)
class Resource:
    """What the action is applied to. Only the fields relevant to the action are read."""

    # Profile edits and named ratings: the user whose profile / rating it is.
    owner_user_id: uuid.UUID | None = None
    owner_member_id: uuid.UUID | None = None
    # Tickets / menus.
    confirmed_by_user_id: uuid.UUID | None = None
    assignee_user_id: uuid.UUID | None = None
    ticket_status: str | None = None
    # Approvals: who raised the request.
    requested_by_user_id: uuid.UUID | None = None


Rule = Callable[[Actor, Resource], bool]


def _yes(_: Actor, __: Resource) -> bool:
    return True


def _no(_: Actor, __: Resource) -> bool:
    return False


def _own_profile(a: Actor, r: Resource) -> bool:
    if r.owner_user_id is not None:
        return r.owner_user_id == a.user_id
    if r.owner_member_id is not None:
        return a.member_id is not None and r.owner_member_id == a.member_id
    return False


def _assigned_to_self(a: Actor, r: Resource) -> bool:
    return r.assignee_user_id is not None and r.assignee_user_id == a.user_id


def _requested_by_self(a: Actor, r: Resource) -> bool:
    return r.requested_by_user_id is not None and r.requested_by_user_id == a.user_id


def _member_confirm(a: Actor, _: Resource) -> bool:
    return a.members_can_send_to_cook


def _member_edit_ticket(a: Actor, r: Resource) -> bool:
    return (
        r.confirmed_by_user_id is not None
        and r.confirmed_by_user_id == a.user_id
        and r.ticket_status in PRE_ACCEPT_STATUSES
    )


def _hired_approve_swap(a: Actor, _: Resource) -> bool:
    return a.cook_can_approve_swaps


def _hired_named_ratings(a: Actor, _: Resource) -> bool:
    return a.show_names_to_cook


# action -> (admin, adult member, hired cook, family cook)
TABLE: dict[Action, tuple[Rule, Rule, Rule, Rule]] = {
    Action.edit_household: (_yes, _no, _no, _no),
    Action.manage_members: (_yes, _no, _no, _no),
    Action.edit_own_profile: (_yes, _own_profile, _no, _own_profile),
    Action.ask_maharaj: (_yes, _yes, _no, _yes),
    Action.edit_day_menu: (_yes, _yes, _no, _yes),
    Action.confirm_menu: (_yes, _member_confirm, _no, _assigned_to_self),
    Action.edit_ticket: (_yes, _member_edit_ticket, _no, _assigned_to_self),
    Action.cancel_ticket: (_yes, _member_edit_ticket, _no, _assigned_to_self),
    Action.accept_ticket: (_no, _no, _assigned_to_self, _assigned_to_self),
    Action.complete_ticket: (_yes, _no, _assigned_to_self, _assigned_to_self),
    Action.mark_item_out: (_no, _no, _assigned_to_self, _assigned_to_self),
    Action.approve_swap: (_yes, _yes, _hired_approve_swap, _requested_by_self),
    Action.approve_dish_change: (_yes, _yes, _no, _requested_by_self),
    Action.raise_ration: (_yes, _no, _yes, _yes),
    Action.update_stock: (_yes, _no, _yes, _yes),
    Action.approve_ration: (_yes, _no, _no, _requested_by_self),
    Action.mark_bought: (_yes, _no, _no, _requested_by_self),
    Action.rate_meal: (_yes, _yes, _no, _yes),
    Action.rate_for_profile_member: (_yes, _yes, _no, _yes),
    Action.see_named_ratings: (_yes, _own_profile, _hired_named_ratings, _yes),
    Action.claim_chef: (_yes, _yes, _no, _yes),
    # "Edit household, cook setup": adding/removing cooks, primary/backup are admin only.
    Action.manage_cooks: (_yes, _no, _no, _no),
    # FR-K8: every cook toggles her own On/Off duty; the admin can do it for anyone
    # (profile-only family cooks, WhatsApp-only hired cooks). Resource.owner_user_id = cook.
    Action.set_duty: (_yes, _no, _own_profile, _own_profile),
    # K6: cook <-> family thread. Family roles post on any household ticket; cooks on their own.
    Action.message_ticket: (_yes, _yes, _assigned_to_self, _assigned_to_self),
}

_EMPTY = Resource()


def can(actor: Actor, action: Action, resource: Resource | None = None) -> bool:
    """True when any role the actor holds allows ``action`` on ``resource``."""
    admin_rule, member_rule, hired_rule, family_rule = TABLE[action]
    r = resource or _EMPTY
    return (
        (actor.is_admin and admin_rule(actor, r))
        or (actor.is_member and member_rule(actor, r))
        or (actor.is_hired_cook and hired_rule(actor, r))
        or (actor.is_family_cook and family_rule(actor, r))
    )


@dataclass(frozen=True, slots=True)
class ApprovalOutcome:
    allowed: bool
    # True when approver == requester: the approval step is skipped and logged as self-approved.
    self_approved: bool = False

    @property
    def skipped(self) -> bool:
        return self.self_approved


def resolve_approval(actor: Actor, action: Action, resource: Resource) -> ApprovalOutcome:
    """Apply the table plus the self-approval rule to an approval-type action."""
    if action not in APPROVAL_ACTIONS:
        raise ValueError(f"{action} is not an approval action")
    allowed = can(actor, action, resource)
    return ApprovalOutcome(
        allowed=allowed, self_approved=allowed and _requested_by_self(actor, resource)
    )
