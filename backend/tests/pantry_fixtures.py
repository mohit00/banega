"""Shared helpers for the Phase 6-7 tests (stock, ladder, ratings, billing)."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.models import Household, Ingredient, Subscription
from tests.kitchen_fixtures import Kitchen


async def ing(slug: str) -> str:
    async with get_sessionmaker()() as db:
        row = (await db.execute(select(Ingredient.id).where(Ingredient.slug == slug))).scalar_one()
        return str(row)


async def hired_ticket(
    k: Kitchen, slugs: list[str] | None = None, **patch: Any
) -> tuple[dict[str, Any], dict[str, str]]:
    """A hired primary cook with her own login and a ticket assigned to her (status new)."""
    if "Ramesh ji" not in k.cooks:
        await k.add_hired()
    cook_h = await k.cook_login()
    return await k.ticket(slugs or ["gatte", "daltadka"], **patch), cook_h


async def complete(k: Kitchen, t: dict[str, Any], cook_h: dict[str, str]) -> dict[str, Any]:
    for to in ("accepted", "cooking", "completed"):
        r = await k.move(t, to, cook_h)
        assert r.status_code == 200, (to, r.text)
    return dict(r.json())


async def inbox_events(k: Kitchen, headers: dict[str, str]) -> list[str]:
    r = await k.client.get("/v1/inbox", headers=headers)
    assert r.status_code == 200, r.text
    return [i["event"] for i in r.json()]


async def inbox(k: Kitchen, headers: dict[str, str]) -> list[dict[str, Any]]:
    r = await k.client.get("/v1/inbox", headers=headers)
    assert r.status_code == 200, r.text
    return list(r.json())


async def household_id(k: Kitchen) -> uuid.UUID:
    r = await k.client.get("/v1/households/me", headers=k.admin)
    return uuid.UUID(r.json()["household"]["id"])


async def set_subscription(hid: uuid.UUID, **fields: Any) -> None:
    async with get_sessionmaker()() as db:
        sub = (
            await db.execute(select(Subscription).where(Subscription.household_id == hid))
        ).scalar_one()
        for key, value in fields.items():
            setattr(sub, key, value)
        await db.commit()


async def get_household(hid: uuid.UUID) -> Household:
    async with get_sessionmaker()() as db:
        h = await db.get(Household, hid)
        assert h is not None
        return h
