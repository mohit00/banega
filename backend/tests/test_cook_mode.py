"""Cook mode (contract §Cook mode): a hired cook's login reaches only her tickets, their
transitions / item-out / messages / recipes, her own duty, the inbox and devices."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

from app.api.deps import cook_mode_allows
from tests.conftest import Login
from tests.kitchen_fixtures import future_day, make_kitchen

ZERO = "00000000-0000-0000-0000-000000000001"


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/v1/members"),
        ("POST", "/v1/members"),
        ("GET", "/v1/households/me"),
        ("PATCH", "/v1/households/me"),
        ("GET", "/v1/recipes"),
        ("GET", f"/v1/recipes/{ZERO}"),
        ("GET", "/v1/recommendations"),
        ("POST", "/v1/chat/sessions"),
        ("GET", "/v1/invites"),
        ("GET", "/v1/menus?date=2026-10-01"),
        ("PUT", "/v1/menus/2026-10-01/lunch/dishes"),
        ("PATCH", f"/v1/menus/{ZERO}"),
        ("POST", f"/v1/menus/{ZERO}/confirm"),
        ("GET", f"/v1/menus/{ZERO}/share-text"),
        ("PATCH", f"/v1/tickets/{ZERO}"),
        ("POST", f"/v1/tickets/{ZERO}/claim"),
        ("GET", "/v1/cooks"),
        ("POST", "/v1/cooks"),
        ("DELETE", f"/v1/cooks/{ZERO}"),
    ],
)
async def test_cook_mode_forbids_everything_else(
    client: AsyncClient, login: Login, method: str, path: str
) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook = await k.cook_login()
    r = await client.request(method, path, headers=cook, json={})
    assert r.status_code == 403, (method, path, r.status_code, r.text)
    assert r.json()["details"].get("reason") == "cook_mode"


async def test_cook_mode_allowed_surface(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    cook_row = await k.add_hired()
    cook = await k.cook_login()
    t = await k.ticket(["gatte"])
    tid = t["id"]
    gatte = k.recipes["gatte"]
    ok = [
        await client.get("/v1/me", headers=cook),
        await client.get(f"/v1/tickets?mine=true&date={future_day()}", headers=cook),
        await client.get(f"/v1/tickets/{tid}", headers=cook),
        await client.post(f"/v1/tickets/{tid}/transitions", json={"to": "accepted"}, headers=cook),
        await client.get(f"/v1/tickets/{tid}/recipes/{gatte}", headers=cook),
        await client.post(f"/v1/tickets/{tid}/messages", json={"text": "Aa gaya"}, headers=cook),
        await client.get(f"/v1/tickets/{tid}/messages", headers=cook),
        await client.post(
            f"/v1/tickets/{tid}/items/{t['required_items'][0]['ingredient_id']}/out",
            headers=cook,
        ),
        await client.patch(f"/v1/cooks/{cook_row['id']}", json={"on_duty": True}, headers=cook),
        await client.get(f"/v1/cooks/{cook_row['id']}/duty-history", headers=cook),
        await client.get("/v1/inbox", headers=cook),
        await client.post(
            "/v1/devices",
            json={"platform": "android", "push_token": "tok-cook", "app_version": "1.0"},
            headers=cook,
        ),
        await client.get("/v1/me/notification-prefs", headers=cook),
    ]
    assert [r.status_code for r in ok] == [200] * 5 + [201, 200, 200, 200, 200, 200, 201, 200]
    item = (await client.get("/v1/inbox", headers=cook)).json()[0]
    assert (await client.post(f"/v1/inbox/{item['id']}/read", headers=cook)).status_code == 200


def test_allowlist_matcher() -> None:
    assert cook_mode_allows("GET", "/v1/tickets")
    assert cook_mode_allows("POST", f"/v1/tickets/{ZERO}/transitions")
    assert not cook_mode_allows("PATCH", f"/v1/tickets/{ZERO}")
    assert not cook_mode_allows("GET", f"/v1/tickets/{ZERO}/transitions")
    assert not cook_mode_allows("GET", "/v1/cooks")
    assert cook_mode_allows("PATCH", f"/v1/cooks/{ZERO}")


async def test_family_cook_keeps_family_mode(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member(member="Mummy")
    await k.add_family("Mummy")
    assert (await client.get("/v1/members", headers=member)).status_code == 200
    me = (await client.get("/v1/me", headers=member)).json()
    assert me["modes"] == ["family", "cook"]
