"""Household create/read/update and delete with a 7-day undo window (FR-A8)."""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, status
from sqlalchemy import select, update

from app.api.deps import DB, Auth, HouseholdCtx, active_membership
from app.core.config import get_settings
from app.core.errors import Conflict, Forbidden, Gone, NotFound
from app.core.security import utcnow
from app.models import (
    AuthSession,
    Consent,
    Household,
    HouseholdMembership,
    Member,
    MembershipStatus,
    Subscription,
)
from app.models.household import DEFAULT_SLOTS
from app.permissions import Action
from app.schemas import (
    DeletionOut,
    HouseholdConsentOut,
    HouseholdIn,
    HouseholdMeOut,
    HouseholdOut,
    HouseholdPatch,
    MembershipOut,
    SubscriptionOut,
)
from app.services import subscription as sub_svc
from app.services.membership import release_deleted_memberships

router = APIRouter(tags=["households"])


async def _household_me(
    db: DB, household: Household, membership: HouseholdMembership
) -> HouseholdMeOut:
    sub = (
        await db.execute(select(Subscription).where(Subscription.household_id == household.id))
    ).scalar_one_or_none()
    out = HouseholdOut.model_validate(household)
    if household.deleted_at is not None:
        out.undo_until = household.deleted_at + timedelta(days=get_settings().UNDO_WINDOW_DAYS)
    consent = (
        await db.execute(
            select(Consent)
            .where(Consent.household_id == household.id)
            .order_by(Consent.accepted_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    sub_out = None
    if sub is not None:
        # Time-based transitions (trial end, grace) show up without waiting for the worker.
        sub_svc.refresh(sub, utcnow())
        sub_out = SubscriptionOut.model_validate(sub)
    return HouseholdMeOut(
        household=out,
        membership=MembershipOut.model_validate(membership),
        subscription=sub_out,
        consent=HouseholdConsentOut(dpdp_accepted_at=consent.accepted_at, version=consent.version)
        if consent is not None
        else None,
    )


@router.post("/households", response_model=HouseholdMeOut, status_code=status.HTTP_201_CREATED)
async def create_household(body: HouseholdIn, auth: Auth, db: DB) -> HouseholdMeOut:
    if auth.user.deleted_at is not None:
        raise Forbidden("account_pending_deletion")
    if await active_membership(db, auth.user.id) is not None:
        raise Conflict(
            "already_in_household",
            "You already belong to a household.",
            "Aap pehle se ek ghar mein hain.",
        )
    await release_deleted_memberships(db, auth.user.id)
    household = Household(
        name=body.name,
        timezone=body.timezone,
        default_servings=body.default_servings,
        enabled_slots=body.enabled_slots or list(DEFAULT_SLOTS),
        slot_defaults=body.slot_defaults or {},
    )
    db.add(household)
    await db.flush()
    member_id = None
    if body.admin_member_name:
        member = Member(household_id=household.id, name=body.admin_member_name)
        db.add(member)
        await db.flush()
        member_id = member.id
    membership = HouseholdMembership(
        user_id=auth.user.id,
        household_id=household.id,
        is_admin=True,
        is_member=True,
        member_id=member_id,
        status=MembershipStatus.active,
    )
    db.add(membership)
    # F-3-03: server-side 7-day trial, one per phone number and device id.
    session = await db.get(AuthSession, auth.session_id)
    await sub_svc.start_trial(
        db, household, auth.user, session.device_id if session is not None else None
    )
    # A consent accepted on the first-run screen (before the household existed) moves in.
    await db.execute(
        update(Consent)
        .where(Consent.user_id == auth.user.id, Consent.household_id.is_(None))
        .values(household_id=household.id)
    )
    await db.commit()
    return await _household_me(db, household, membership)


@router.get("/households/me", response_model=HouseholdMeOut)
async def get_my_household(ctx: HouseholdCtx, db: DB) -> HouseholdMeOut:
    return await _household_me(db, ctx.household, ctx.membership)


@router.patch("/households/me", response_model=HouseholdMeOut)
async def update_my_household(body: HouseholdPatch, ctx: HouseholdCtx, db: DB) -> HouseholdMeOut:
    changes = body.model_dump(exclude_unset=True)
    # F-5.10-04: a family cook may turn ratings off (or on) from her own settings.
    family_cook_only = set(changes) <= {"ratings_enabled"} and ctx.actor.is_family_cook
    if not family_cook_only:
        ctx.require(Action.edit_household)
    for field, value in changes.items():
        if value is not None:  # every household column is NOT NULL
            setattr(ctx.household, field, value)
    await db.commit()
    await db.refresh(ctx.household)
    return await _household_me(db, ctx.household, ctx.membership)


@router.delete("/household", response_model=DeletionOut)
async def delete_household(ctx: HouseholdCtx, db: DB) -> DeletionOut:
    """Soft delete. The worker hard-deletes after UNDO_WINDOW_DAYS."""
    ctx.require(Action.edit_household)
    now = utcnow()
    ctx.household.deleted_at = now
    await db.commit()
    # TODO: store subscriptions must be cancelled in the store; the app shows the store link.
    return DeletionOut(
        deleted_at=now, undo_until=now + timedelta(days=get_settings().UNDO_WINDOW_DAYS)
    )


@router.post("/household/restore", response_model=HouseholdMeOut)
async def restore_household(auth: Auth, db: DB) -> HouseholdMeOut:
    if await active_membership(db, auth.user.id) is not None:
        # One household per login (v1): created / joined another one in the meantime.
        raise Conflict(
            "already_in_household",
            "You already belong to another household.",
            "Aap pehle se dusre ghar mein hain.",
        )
    row = (
        await db.execute(
            select(HouseholdMembership, Household)
            .join(Household, Household.id == HouseholdMembership.household_id)
            .where(
                HouseholdMembership.user_id == auth.user.id,
                HouseholdMembership.status == MembershipStatus.active,
                HouseholdMembership.is_admin.is_(True),
                Household.deleted_at.is_not(None),
            )
            .limit(1)
        )
    ).first()
    if row is None:
        raise NotFound()
    membership, household = row
    assert household.deleted_at is not None
    if household.deleted_at + timedelta(days=get_settings().UNDO_WINDOW_DAYS) <= utcnow():
        raise Gone(
            "undo_window_over", "The undo window has closed.", "Wapas laane ka samay khatam."
        )
    household.deleted_at = None
    await db.commit()
    return await _household_me(db, household, membership)
