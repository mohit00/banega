from __future__ import annotations

from collections.abc import Awaitable, Callable

from httpx import AsyncClient

from tests.conftest import Headers, Login

MakeHousehold = Callable[..., Awaitable[Headers]]


async def test_member_crud(client: AsyncClient, make_household: MakeHousehold) -> None:
    h = await make_household()
    r = await client.post(
        "/v1/members",
        json={"name": "Papa", "diet": "jain", "spice": "kam", "needs": ["diabetic"]},
        headers=h,
    )
    assert r.status_code == 201, r.text
    mid = r.json()["id"]
    assert r.json()["diet"] == "jain"
    assert r.json()["allergens"] == []

    r = await client.patch(f"/v1/members/{mid}", json={"spice": "teekha"}, headers=h)
    assert r.status_code == 200
    assert r.json()["spice"] == "teekha"

    r = await client.get(f"/v1/members/{mid}", headers=h)
    assert r.json()["name"] == "Papa"

    assert (await client.delete(f"/v1/members/{mid}", headers=h)).status_code == 204
    listed = (await client.get("/v1/members", headers=h)).json()
    assert listed["items"] == []
    archived = (await client.get("/v1/members?include_archived=true", headers=h)).json()
    assert archived["items"][0]["archived_at"] is not None


async def test_invalid_diet_rejected(client: AsyncClient, make_household: MakeHousehold) -> None:
    h = await make_household()
    r = await client.post("/v1/members", json={"name": "X", "diet": "vegan"}, headers=h)
    assert r.status_code == 422


async def test_members_pagination(client: AsyncClient, make_household: MakeHousehold) -> None:
    h = await make_household()
    for i in range(5):
        await client.post("/v1/members", json={"name": f"M{i}"}, headers=h)
    page1 = (await client.get("/v1/members?limit=2", headers=h)).json()
    assert len(page1["items"]) == 2
    assert page1["next_cursor"]
    seen = [m["name"] for m in page1["items"]]
    cursor = page1["next_cursor"]
    while cursor:
        page = (await client.get(f"/v1/members?limit=2&cursor={cursor}", headers=h)).json()
        seen += [m["name"] for m in page["items"]]
        cursor = page["next_cursor"]
    assert sorted(seen) == [f"M{i}" for i in range(5)]


async def test_cross_household_ids_are_404(
    client: AsyncClient, make_household: MakeHousehold
) -> None:
    a = await make_household("+919800000001", "A")
    b = await make_household("+919800000009", "B")
    mid = (await client.post("/v1/members", json={"name": "Dadi"}, headers=a)).json()["id"]
    assert (await client.get(f"/v1/members/{mid}", headers=b)).status_code == 404
    assert (
        await client.patch(f"/v1/members/{mid}", json={"name": "x"}, headers=b)
    ).status_code == 404
    assert (await client.delete(f"/v1/members/{mid}", headers=b)).status_code == 404
    assert (await client.get("/v1/members", headers=b)).json()["items"] == []


async def test_adult_member_edits_own_profile_only(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    own = (await client.post("/v1/members", json={"name": "Rahul"}, headers=admin)).json()["id"]
    other = (await client.post("/v1/members", json={"name": "Dadi"}, headers=admin)).json()["id"]
    token = (
        await client.post(
            "/v1/invites", json={"phone": "+919800000002", "member_id": own}, headers=admin
        )
    ).json()["token"]
    member = await login("+919800000002")
    assert (await client.post(f"/v1/invites/{token}/accept", headers=member)).status_code == 200

    r = await client.patch(f"/v1/members/{own}", json={"spice": "teekha"}, headers=member)
    assert r.status_code == 200
    r = await client.patch(f"/v1/members/{other}", json={"spice": "teekha"}, headers=member)
    assert r.status_code == 403
    assert (await client.post("/v1/members", json={"name": "X"}, headers=member)).status_code == 403
    assert (await client.delete(f"/v1/members/{other}", headers=member)).status_code == 403
    # Members can still read the family list.
    assert len((await client.get("/v1/members", headers=member)).json()["items"]) == 2
