"""Nightly purge (FR-A8, review C2): runs on Postgres too (``TEST_DATABASE_URL``)."""

from __future__ import annotations

from datetime import timedelta

from httpx import AsyncClient
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import Household, HouseholdMembership, MembershipStatus, User
from app.workers.worker import purge_deleted
from tests.conftest import Login


async def test_purge_erases_phone_and_frees_the_number(client: AsyncClient, login: Login) -> None:
    phone = "+919800000071"
    headers = await login(phone)
    assert (
        await client.post("/v1/households", json={"name": "A"}, headers=headers)
    ).status_code == 201
    assert (await client.delete("/v1/household", headers=headers)).status_code == 200
    assert (await client.delete("/v1/me", headers=headers)).status_code == 200
    async with get_sessionmaker()() as db:
        user = (await db.execute(select(User).where(User.phone == phone))).scalar_one()
        uid = user.id
        user.deleted_at = utcnow() - timedelta(days=8)
        for h in (await db.execute(select(Household))).scalars():
            h.deleted_at = utcnow() - timedelta(days=8)
        await db.commit()

    result = await purge_deleted({})
    assert result == {"households": 1, "users": 1}
    async with get_sessionmaker()() as db:
        user = await db.get(User, uid)
        assert user is not None
        assert user.phone is None and user.name is None
        assert user.phone_deleted_at is not None
        rows = (
            await db.execute(select(HouseholdMembership).where(HouseholdMembership.user_id == uid))
        ).scalars()
        assert all(m.status == MembershipStatus.removed for m in rows)

    # A second run finds nothing; the number signs up again as a brand-new user.
    assert await purge_deleted({}) == {"households": 0, "users": 0}
    await login(phone)
    async with get_sessionmaker()() as db:
        again = (await db.execute(select(User).where(User.phone == phone))).scalar_one()
        assert again.id != uid


async def test_purge_two_users_leaves_both_phones_null(client: AsyncClient, login: Login) -> None:
    ids = []
    for phone in ("+919800000072", "+919800000073"):
        headers = await login(phone)
        assert (await client.delete("/v1/me", headers=headers)).status_code == 200
    async with get_sessionmaker()() as db:
        for u in (await db.execute(select(User))).scalars():
            u.deleted_at = utcnow() - timedelta(days=8)
            ids.append(u.id)
        await db.commit()
    assert (await purge_deleted({}))["users"] == 2
    async with get_sessionmaker()() as db:
        phones = [(await db.get(User, i)).phone for i in ids]  # type: ignore[union-attr]
    assert phones == [None, None]
