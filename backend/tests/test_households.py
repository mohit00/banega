from __future__ import annotations

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import Headers, Login

MakeHousehold = Callable[..., Awaitable[Headers]]


async def test_create_household_makes_admin_and_trial(client: AsyncClient, login: Login) -> None:
    h = await login()
    r = await client.post(
        "/v1/households", json={"name": "Sharma ghar", "admin_member_name": "Neha"}, headers=h
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["household"]["timezone"] == "Asia/Kolkata"
    assert body["household"]["enabled_slots"] == ["nashta", "lunch", "dinner"]
    assert body["household"]["cook_can_approve_swaps"] is True
    assert body["household"]["members_can_send_to_cook"] is True
    assert body["membership"]["is_admin"] is True
    assert body["membership"]["is_member"] is True
    assert body["membership"]["member_id"] is not None
    assert body["subscription"]["status"] == "trial"
    assert body["subscription"]["trial_ends_at"]

    me = (await client.get("/v1/households/me", headers=h)).json()
    assert me["household"]["id"] == body["household"]["id"]


async def test_one_household_per_user(client: AsyncClient, make_household: MakeHousehold) -> None:
    h = await make_household()
    r = await client.post("/v1/households", json={"name": "Second"}, headers=h)
    assert r.status_code == 409
    assert r.json()["code"] == "already_in_household"


async def test_no_household_is_404(client: AsyncClient, login: Login) -> None:
    h = await login()
    r = await client.get("/v1/households/me", headers=h)
    assert r.status_code == 404
    assert r.json()["code"] == "no_household"


async def test_patch_household_admin_only(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    r = await client.patch(
        "/v1/households/me",
        json={"name": "Naya naam", "cook_can_approve_swaps": False},
        headers=admin,
    )
    assert r.status_code == 200
    assert r.json()["household"]["name"] == "Naya naam"
    assert r.json()["household"]["cook_can_approve_swaps"] is False

    # An invited adult member cannot edit the household.
    inv = await client.post("/v1/invites", json={"phone": "+919800000002"}, headers=admin)
    member = await login("+919800000002")
    await client.post(f"/v1/invites/{inv.json()['token']}/accept", headers=member)
    r = await client.patch("/v1/households/me", json={"name": "Hack"}, headers=member)
    assert r.status_code == 403


async def test_delete_household_with_undo(
    client: AsyncClient, make_household: MakeHousehold
) -> None:
    h = await make_household()
    r = await client.delete("/v1/household", headers=h)
    assert r.status_code == 200
    assert r.json()["undo_until"]
    assert (await client.get("/v1/households/me", headers=h)).status_code == 404
    assert (await client.get("/v1/members", headers=h)).status_code == 404
    r = await client.post("/v1/household/restore", headers=h)
    assert r.status_code == 200
    assert (await client.get("/v1/households/me", headers=h)).status_code == 200


async def test_idempotency_key_replays_create(client: AsyncClient, login: Login) -> None:
    h = await login()
    headers = {**h, "Idempotency-Key": "abc-123"}
    r1 = await client.post("/v1/households", json={"name": "Ghar"}, headers=headers)
    r2 = await client.post("/v1/households", json={"name": "Ghar"}, headers=headers)
    assert r1.status_code == 201
    assert r2.status_code == 201
    assert r2.headers.get("idempotent-replayed") == "true"
    assert r1.json() == r2.json()
    r3 = await client.post("/v1/households", json={"name": "Other"}, headers=headers)
    assert r3.status_code == 422
    assert r3.json()["code"] == "idempotency_key_reused"


async def test_invalid_timezone_rejected(client: AsyncClient, login: Login) -> None:
    h = await login()
    r = await client.post("/v1/households", json={"name": "G", "timezone": "Mars/Base"}, headers=h)
    assert r.status_code == 422


async def test_patch_null_is_ignored(client: AsyncClient, make_household: MakeHousehold) -> None:
    h = await make_household()
    r = await client.patch("/v1/households/me", json={"enabled_slots": None}, headers=h)
    assert r.status_code == 200
    assert r.json()["household"]["enabled_slots"] == ["nashta", "lunch", "dinner"]
