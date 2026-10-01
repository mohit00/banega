"""Shared setup for the Phase 5 tests: a seeded catalogue and a household with members,
cooks, menus and tickets created through the API."""

from __future__ import annotations

import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from typing import Any
from zoneinfo import ZoneInfo

from httpx import AsyncClient, Response
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.models import Recipe, RecipeStatus
from app.services.importer import seed_all
from tests.conftest import Headers, Login

ADMIN_PHONE = "+919800000101"
MEMBER_PHONE = "+919800000102"
COOK_PHONE = "+919800000103"
IST = ZoneInfo("Asia/Kolkata")


async def seed_catalogue() -> dict[str, uuid.UUID]:
    async with get_sessionmaker()() as db:
        await seed_all(db, publish="clean", with_demo_household=False)
        rows = await db.execute(select(Recipe).where(Recipe.status == RecipeStatus.published))
        return {r.slug: r.id for r in rows.scalars()}


def future_day(days: int = 2) -> date:
    return datetime.now(IST).date() + timedelta(days=days)


@dataclass
class Kitchen:
    client: AsyncClient
    login: Login
    admin: Headers
    members: dict[str, str]
    recipes: dict[str, uuid.UUID]
    cooks: dict[str, dict[str, Any]] = field(default_factory=dict)

    # ---- people -------------------------------------------------------------------------

    async def add_member(self, name: str, **fields: Any) -> str:
        r = await self.client.post("/v1/members", json={"name": name, **fields}, headers=self.admin)
        assert r.status_code == 201, r.text
        self.members[name] = r.json()["id"]
        return str(r.json()["id"])

    async def invite_member(self, phone: str = MEMBER_PHONE, member: str | None = None) -> Headers:
        body: dict[str, Any] = {"phone": phone, "role": "member"}
        if member:
            body["member_id"] = self.members[member]
        r = await self.client.post("/v1/invites", json=body, headers=self.admin)
        assert r.status_code == 201, r.text
        h = await self.login(phone)
        acc = await self.client.post(f"/v1/invites/{r.json()['token']}/accept", headers=h)
        assert acc.status_code == 200, acc.text
        return h

    async def add_hired(
        self, phone: str = COOK_PHONE, name: str = "Ramesh ji", login_mode: str = "own"
    ) -> dict[str, Any]:
        r = await self.client.post(
            "/v1/cooks",
            json={"kind": "hired", "phone": phone, "name": name, "login_mode": login_mode},
            headers=self.admin,
        )
        assert r.status_code == 201, r.text
        self.cooks[name] = r.json()
        return dict(r.json())

    async def add_family(self, member: str, **extra: Any) -> dict[str, Any]:
        r = await self.client.post(
            "/v1/cooks",
            json={"kind": "family", "member_id": self.members[member], **extra},
            headers=self.admin,
        )
        assert r.status_code == 201, r.text
        self.cooks[member] = r.json()
        return dict(r.json())

    async def cook_login(self, phone: str = COOK_PHONE) -> Headers:
        return await self.login(phone)

    async def patch_cook(self, name: str, headers: Headers | None = None, **body: Any) -> Response:
        return await self.client.patch(
            f"/v1/cooks/{self.cooks[name]['id']}", json=body, headers=headers or self.admin
        )

    # ---- menus and tickets --------------------------------------------------------------

    async def menu(
        self,
        slugs: list[str],
        *,
        day: date | None = None,
        slot: str = "lunch",
        headers: Headers | None = None,
        **patch: Any,
    ) -> dict[str, Any]:
        day = day or future_day()
        r = await self.client.put(
            f"/v1/menus/{day.isoformat()}/{slot}/dishes",
            json={"recipe_ids": [str(self.recipes[s]) for s in slugs]},
            headers=headers or self.admin,
        )
        assert r.status_code == 200, r.text
        menu = dict(r.json())
        if patch:
            r = await self.client.patch(
                f"/v1/menus/{menu['id']}", json=patch, headers=headers or self.admin
            )
            assert r.status_code == 200, r.text
            menu = dict(r.json())
        return menu

    async def confirm(self, menu: dict[str, Any], headers: Headers | None = None) -> Response:
        return await self.client.post(
            f"/v1/menus/{menu['id']}/confirm", headers=headers or self.admin
        )

    async def ticket(
        self, slugs: list[str], headers: Headers | None = None, **patch: Any
    ) -> dict[str, Any]:
        menu = await self.menu(slugs, headers=headers, **patch)
        r = await self.confirm(menu, headers)
        assert r.status_code == 200, r.text
        return dict(r.json()["ticket"])

    async def move(
        self, ticket: dict[str, Any], to: str, headers: Headers | None = None, **body: Any
    ) -> Response:
        return await self.client.post(
            f"/v1/tickets/{ticket['id']}/transitions",
            json={"to": to, **body},
            headers=headers or self.admin,
        )

    async def get(self, ticket: dict[str, Any], headers: Headers | None = None) -> dict[str, Any]:
        r = await self.client.get(f"/v1/tickets/{ticket['id']}", headers=headers or self.admin)
        assert r.status_code == 200, r.text
        return dict(r.json())


async def make_kitchen(client: AsyncClient, login: Login) -> Kitchen:
    recipes = await seed_catalogue()
    admin = await login(ADMIN_PHONE)
    r = await client.post(
        "/v1/households",
        json={"name": "Test ghar", "admin_member_name": "Papa"},
        headers=admin,
    )
    assert r.status_code == 201, r.text
    papa = r.json()["membership"]["member_id"]
    k = Kitchen(client=client, login=login, admin=admin, members={"Papa": papa}, recipes=recipes)
    await k.add_member("Mummy", diet="veg")
    await k.add_member("Dadi", diet="jain")
    await k.add_member("Beta", is_kid=True)
    return k
