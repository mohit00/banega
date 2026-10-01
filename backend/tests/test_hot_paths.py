"""Hot paths and misc API hardening (review M4, M5, M9, lows; primary #5)."""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.models import Cook, CookKind, Recipe, RecipeStatus, Ticket, TicketStatus
from app.services import catalogue_cache
from tests.conftest import Login
from tests.kitchen_fixtures import IST, future_day, make_kitchen, seed_catalogue


async def test_catalogue_snapshot_reloads_only_on_change(monkeypatch: pytest.MonkeyPatch) -> None:
    await seed_catalogue()
    async with get_sessionmaker()() as db:
        first = await catalogue_cache.published(db)
        again = await catalogue_cache.published(db)
        assert again is first and len(first.views) == len(first.recipes) > 0
        r = (await db.execute(select(Recipe).where(Recipe.slug == "gatte"))).scalar_one()
        r.status = RecipeStatus.draft
        await db.commit()
        changed = await catalogue_cache.published(db)
        assert changed is not first and "gatte" not in {x.slug for x in changed.recipes}
    # With a TTL the stamp is not even re-read inside the window.
    monkeypatch.setattr(get_settings(), "CATALOGUE_CACHE_SECONDS", 60)
    async with get_sessionmaker()() as db:
        cached = await catalogue_cache.published(db)
        r = (await db.execute(select(Recipe).where(Recipe.slug == "gatte"))).scalar_one()
        r.status = RecipeStatus.published
        await db.commit()
        assert await catalogue_cache.published(db) is cached


async def test_ticket_list_needs_a_date_or_short_range(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t = await k.ticket(["gatte"])
    r = await client.get("/v1/tickets", headers=k.admin)
    assert r.status_code == 422 and r.json()["code"] == "date_required"
    day = t["date"]
    r = await client.get(f"/v1/tickets?from={day}&to={day}", headers=k.admin)
    assert r.status_code == 200 and [x["id"] for x in r.json()] == [t["id"]]
    start = datetime.fromisoformat(day).date()
    too_long = (start + timedelta(days=31)).isoformat()
    r = await client.get(f"/v1/tickets?from={day}&to={too_long}", headers=k.admin)
    assert r.status_code == 422 and r.json()["code"] == "range_too_long"
    today = datetime.now(IST).date()
    r = await client.get(f"/v1/tickets?from=today&to={today + timedelta(days=30)}", headers=k.admin)
    assert r.status_code == 200 and [x["id"] for x in r.json()] == [t["id"]]


async def test_sole_admin_must_transfer_first(client: AsyncClient, make_household: Any) -> None:
    admin = await make_household("+919800000901")
    r = await client.delete("/v1/me", headers=admin)
    assert r.status_code == 409 and r.json()["code"] == "transfer_admin_first"
    # After deleting the household the account can go.
    assert (await client.delete("/v1/household", headers=admin)).status_code == 200
    assert (await client.delete("/v1/me", headers=admin)).status_code == 200


async def test_hired_cook_leaving_archives_her_cook_row(client: AsyncClient, login: Login) -> None:
    from tests.pantry_fixtures import hired_ticket

    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)
    assert t["status"] == "new"
    assert (await client.delete("/v1/me", headers=cook_h)).status_code == 200
    async with get_sessionmaker()() as db:
        cook = (await db.execute(select(Cook).where(Cook.kind == CookKind.hired))).scalar_one()
        ticket = (await db.execute(select(Ticket))).scalar_one()
    assert cook.removed_at is not None
    assert ticket.status == TicketStatus.unassigned and ticket.assignee_cook_id is None
    assert "ticket_unassigned" in [
        i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()
    ]


async def test_menu_due_at_must_be_on_the_menu_day(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    menu = await k.menu(["gatte"])
    day = datetime.fromisoformat(menu["date"]).date() if "date" in menu else future_day()
    wrong = datetime.combine(day + timedelta(days=1), datetime.min.time(), tzinfo=IST).replace(
        hour=13
    )
    r = await client.patch(
        f"/v1/menus/{menu['id']}", json={"due_at": wrong.isoformat()}, headers=k.admin
    )
    assert r.status_code == 422 and r.json()["code"] == "due_at_wrong_day"
    right = wrong - timedelta(days=1)
    r = await client.patch(
        f"/v1/menus/{menu['id']}", json={"due_at": right.isoformat()}, headers=k.admin
    )
    assert r.status_code == 200, r.text


async def test_device_rebind_moves_the_token(client: AsyncClient, login: Login) -> None:
    a = await login("+919800000911")
    b = await login("+919800000912")
    body = {"platform": "android", "push_token": "shared-token-1", "app_version": "1"}
    first = (await client.post("/v1/devices", json=body, headers=a)).json()
    second = (await client.post("/v1/devices", json=body, headers=b)).json()
    assert first["id"] == second["id"]
    # The previous owner can no longer delete it.
    assert (await client.delete(f"/v1/devices/{first['id']}", headers=a)).status_code == 404


def test_openapi_disabled_in_prod(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.main import create_app

    monkeypatch.setattr(get_settings(), "ENV", "prod")
    assert create_app().openapi_url is None
    monkeypatch.setattr(get_settings(), "ENV", "staging")
    assert create_app().openapi_url == "/v1/openapi.json"
