"""Database constraints behind the "one per" rules (review H5, primary #1): they hold even
when two requests race past the service checks; a lost race is a 409, never a 500."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from app.core.db import get_sessionmaker
from app.models import (
    Cook,
    CookKind,
    Household,
    HouseholdMembership,
    Subscription,
    User,
)
from app.services import cooks as cook_svc
from tests.conftest import Login
from tests.kitchen_fixtures import COOK_PHONE, make_kitchen


async def test_delete_create_restore_never_gives_two_households(
    client: AsyncClient, make_household: Any
) -> None:
    admin = await make_household("+919800000601", "Pehla ghar")
    assert (await client.delete("/v1/household", headers=admin)).status_code == 200
    # Starting over during the undo window releases the old membership...
    r = await client.post("/v1/households", json={"name": "Doosra ghar"}, headers=admin)
    assert r.status_code == 201, r.text
    # ...so the old household cannot come back on top of the new one.
    r = await client.post("/v1/household/restore", headers=admin)
    assert r.status_code == 409 and r.json()["code"] == "already_in_household"
    assert (await client.get("/v1/cooks", headers=admin)).status_code == 200
    me = (await client.get("/v1/households/me", headers=admin)).json()
    assert me["household"]["name"] == "Doosra ghar"
    async with get_sessionmaker()() as db:
        rows = list((await db.execute(select(HouseholdMembership))).scalars())
        assert sorted(m.status.value for m in rows) == ["active", "removed"]


async def test_restore_still_works_without_another_household(
    client: AsyncClient, make_household: Any
) -> None:
    admin = await make_household("+919800000602")
    assert (await client.delete("/v1/household", headers=admin)).status_code == 200
    r = await client.post("/v1/household/restore", headers=admin)
    assert r.status_code == 200, r.text


async def test_db_refuses_two_active_memberships() -> None:
    async with get_sessionmaker()() as db:
        user = User(phone="+919800000603")
        a, b = Household(name="A"), Household(name="B")
        db.add_all([user, a, b])
        await db.flush()
        db.add(HouseholdMembership(user_id=user.id, household_id=a.id, is_admin=True))
        await db.flush()
        db.add(HouseholdMembership(user_id=user.id, household_id=b.id, is_admin=True))
        with pytest.raises(IntegrityError):
            await db.flush()
        await db.rollback()


async def test_db_refuses_second_hired_cook_and_duplicate_purchase() -> None:
    async with get_sessionmaker()() as db:
        h = Household(name="C")
        db.add(h)
        await db.flush()
        db.add(Cook(household_id=h.id, kind=CookKind.hired, phone="+919800000611"))
        await db.flush()
        db.add(Cook(household_id=h.id, kind=CookKind.hired, phone="+919800000612"))
        with pytest.raises(IntegrityError):
            await db.flush()
        await db.rollback()
    async with get_sessionmaker()() as db:
        h1, h2 = Household(name="D"), Household(name="E")
        db.add_all([h1, h2])
        await db.flush()
        db.add(Subscription(household_id=h1.id, purchase_token="tok-dup"))
        db.add(Subscription(household_id=h2.id, purchase_token="tok-dup"))
        with pytest.raises(IntegrityError):
            await db.flush()
        await db.rollback()


async def test_lost_race_is_409_conflict(
    client: AsyncClient, login: Login, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Simulate two admins adding a hired cook at once: the service check passes for both,
    the partial unique index stops the second, the API answers 409 conflict."""
    k = await make_kitchen(client, login)
    await k.add_hired()

    async def _no_check(*args: Any, **kwargs: Any) -> None:
        return None

    monkeypatch.setattr(cook_svc, "check_hired_limit", _no_check)
    r = await client.post(
        "/v1/cooks",
        json={"kind": "hired", "phone": "+919800000699", "name": "Doosra"},
        headers=k.admin,
    )
    assert r.status_code == 409, r.text
    assert r.json()["code"] == "conflict"


async def test_cook_phone_in_deleted_household_is_free(
    client: AsyncClient, login: Login, make_household: Any
) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    assert (await client.delete("/v1/household", headers=k.admin)).status_code == 200
    other = await make_household("+919800000620", "Naya ghar")
    r = await client.post(
        "/v1/cooks", json={"kind": "hired", "phone": COOK_PHONE, "name": "Ramesh ji"}, headers=other
    )
    assert r.status_code == 201, r.text


async def test_cook_invite_checks_phone_in_other_household(
    client: AsyncClient, login: Login, make_household: Any
) -> None:
    other = await make_household("+919800000630", "Doosra ghar")
    r = await client.post("/v1/invites", json={"phone": COOK_PHONE, "role": "cook"}, headers=other)
    assert r.status_code == 201, r.text
    # Meanwhile another household adds the same number as its hired cook (no own login).
    k = await make_kitchen(client, login)
    await k.add_hired(login_mode="via_admin")
    cook = await login(COOK_PHONE)
    accept = await client.post(f"/v1/invites/{r.json()['token']}/accept", headers=cook)
    assert accept.status_code == 409 and accept.json()["code"] == "phone_in_other_household"
