"""Household membership helpers shared by the API and the services."""

from __future__ import annotations

import uuid

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Household, HouseholdMembership, MembershipStatus


async def release_deleted_memberships(db: AsyncSession, user_id: uuid.UUID) -> int:
    """Before a user creates or joins a household: active memberships in soft-deleted
    households become ``removed`` (the user moved on; that household can no longer be
    restored by them). Keeps the one-active-membership unique index satisfied."""
    deleted = select(Household.id).where(Household.deleted_at.is_not(None))
    result = await db.execute(
        update(HouseholdMembership)
        .where(
            HouseholdMembership.user_id == user_id,
            HouseholdMembership.status == MembershipStatus.active,
            HouseholdMembership.household_id.in_(deleted),
        )
        .values(status=MembershipStatus.removed)
        .execution_options(synchronize_session="fetch")
    )
    return int(getattr(result, "rowcount", 0) or 0)
