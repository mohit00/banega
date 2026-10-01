"""Shared FastAPI dependencies: DB session, authenticated user, household context."""

from __future__ import annotations

import re
import uuid
from dataclasses import dataclass
from typing import Annotated

from fastapi import Depends, Header, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.errors import AppError, Forbidden, NotFound, PreconditionFailed, Unauthorized
from app.core.security import decode_token, utcnow
from app.models import (
    AuthSession,
    Cook,
    CookKind,
    Household,
    HouseholdMembership,
    MembershipStatus,
    User,
)
from app.permissions import Action, Actor, Resource, can

DB = Annotated[AsyncSession, Depends(get_session)]


@dataclass
class AuthContext:
    user: User
    session_id: uuid.UUID


async def get_auth(db: DB, authorization: Annotated[str | None, Header()] = None) -> AuthContext:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise Unauthorized()
    claims = decode_token(authorization.split(" ", 1)[1].strip(), "access")
    session = await db.get(AuthSession, claims.session_id)
    if (
        session is None
        or session.user_id != claims.user_id
        or session.revoked_at is not None
        or session.expires_at <= utcnow()
    ):
        raise Unauthorized("session_revoked")
    user = await db.get(User, claims.user_id)
    if user is None:
        raise Unauthorized()
    return AuthContext(user=user, session_id=session.id)


Auth = Annotated[AuthContext, Depends(get_auth)]


async def active_membership(db: AsyncSession, user_id: uuid.UUID) -> HouseholdMembership | None:
    """v1: a user belongs to at most one household (F-2-06 / FR-K20)."""
    stmt = (
        select(HouseholdMembership)
        .join(Household, Household.id == HouseholdMembership.household_id)
        .where(
            HouseholdMembership.user_id == user_id,
            HouseholdMembership.status == MembershipStatus.active,
            Household.deleted_at.is_(None),
        )
        .limit(1)
    )
    return (await db.execute(stmt)).scalar_one_or_none()


@dataclass
class HouseholdContext:
    user: User
    session_id: uuid.UUID
    membership: HouseholdMembership
    household: Household
    actor: Actor
    cook: Cook | None = None

    @property
    def cook_only(self) -> bool:
        """A hired cook with no family role: the app shows cook mode only."""
        return self.actor.is_hired_cook and not (self.actor.is_admin or self.actor.is_member)

    def require(self, action: Action, resource: Resource | None = None) -> None:
        if not can(self.actor, action, resource):
            raise Forbidden(details={"action": action.value})


def build_actor(
    user: User, membership: HouseholdMembership, household: Household, cook_kind: CookKind | None
) -> Actor:
    return Actor(
        user_id=user.id,
        household_id=household.id,
        is_admin=membership.is_admin,
        is_member=membership.is_member,
        cook_kind=cook_kind,
        member_id=membership.member_id,
        members_can_send_to_cook=household.members_can_send_to_cook,
        cook_can_approve_swaps=household.cook_can_approve_swaps,
        show_names_to_cook=household.show_names_to_cook,
    )


# Cook mode (contract §Cook mode): the only household-scoped endpoints a cook-only login may
# call. Everything else is 403 before the handler runs. /v1/me and /v1/devices are not
# household-scoped and stay open.
_COOK_MODE_ALLOW: tuple[tuple[frozenset[str], re.Pattern[str]], ...] = tuple(
    (frozenset(methods.split()), re.compile(pattern))
    for methods, pattern in (
        ("GET", r"^/v1/tickets$"),
        ("GET", r"^/v1/tickets/[^/]+$"),
        ("POST", r"^/v1/tickets/[^/]+/transitions$"),
        ("POST", r"^/v1/tickets/[^/]+/items/[^/]+/out$"),
        ("GET POST", r"^/v1/tickets/[^/]+/messages$"),
        ("GET", r"^/v1/tickets/[^/]+/recipes/[^/]+$"),
        ("PATCH", r"^/v1/cooks/[^/]+$"),
        ("GET", r"^/v1/cooks/[^/]+/duty-history$"),
        ("GET", r"^/v1/inbox$"),
        ("POST", r"^/v1/inbox/[^/]+/read$"),
        # Phase 6: pantry, own ration requests, the out-of-stock ladder.
        ("GET", r"^/v1/stock$"),
        ("PUT", r"^/v1/stock/[^/]+$"),
        ("POST", r"^/v1/stock/bulk$"),
        ("GET POST", r"^/v1/ration-requests$"),
        ("GET", r"^/v1/ration-requests/suggest$"),
        ("POST", r"^/v1/tickets/[^/]+/stock-issue/resolve$"),
        # Phase 7: "Meri ratings" (names masked, F-5.10-01) and the plan banner.
        ("GET", r"^/v1/ratings/summary$"),
        ("GET", r"^/v1/subscription$"),
    )
)


def cook_mode_allows(method: str, path: str) -> bool:
    return any(method in methods and rx.match(path) for methods, rx in _COOK_MODE_ALLOW)


async def get_household_ctx(db: DB, auth: Auth, request: Request) -> HouseholdContext:
    if auth.user.deleted_at is not None:
        raise Forbidden(
            "account_pending_deletion",
            "Your account is scheduled for deletion. Restore it first.",
            "Aapka account delete hone wala hai. Pehle use wapas laaiye.",
        )
    membership = await active_membership(db, auth.user.id)
    if membership is None:
        raise NotFound(
            "no_household",
            "You are not part of a household yet.",
            "Aap abhi kisi ghar mein nahi hain.",
        )
    household = await db.get(Household, membership.household_id)
    assert household is not None
    cook_kind: CookKind | None = None
    cook: Cook | None = None
    if membership.cook_id is not None:
        cook = await db.get(Cook, membership.cook_id)
        if cook is not None and cook.removed_at is not None:
            cook = None
        cook_kind = cook.kind if cook else None
    ctx = HouseholdContext(
        user=auth.user,
        session_id=auth.session_id,
        membership=membership,
        household=household,
        actor=build_actor(auth.user, membership, household, cook_kind),
        cook=cook,
    )
    if ctx.cook_only and not cook_mode_allows(request.method, request.url.path):
        raise Forbidden(
            message_en="Cook mode cannot open this.",
            message_hi="Cook mode mein ye nahi khulta.",
            details={"reason": "cook_mode"},
        )
    # F-5.1-05: an expired plan is read-only (402), except today's/tomorrow's ticket work.
    from app.services.subscription import enforce

    await enforce(db, household, request.method, request.url.path)
    return ctx


HouseholdCtx = Annotated[HouseholdContext, Depends(get_household_ctx)]


def parse_if_match(value: str | None) -> int | None:
    """If-Match carries the bare version (``7``); ``"7"`` and ``W/"7"`` are accepted too."""
    if value is None or not value.strip():
        return None
    raw = value.strip()
    if raw.startswith("W/"):
        raw = raw[2:]
    raw = raw.strip('"')
    try:
        return int(raw)
    except ValueError as exc:
        raise AppError(
            "invalid_if_match", "If-Match must be a version number.", "If-Match galat hai."
        ) from exc


def check_version(if_match: str | None, current: int) -> None:
    expected = parse_if_match(if_match)
    if expected is not None and expected != current:
        raise PreconditionFailed(details={"current_version": current})


IfMatch = Annotated[str | None, Header(alias="If-Match")]
