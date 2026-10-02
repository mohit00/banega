from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from datetime import timedelta

from httpx import AsyncClient
from sqlalchemy import update

from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import Invite
from tests.conftest import Headers, Login

MakeHousehold = Callable[..., Awaitable[Headers]]
INVITEE = "+919800000002"


async def _invite(client: AsyncClient, admin: Headers, **body: object) -> dict[str, object]:
    r = await client.post("/v1/invites", json={"phone": INVITEE, **body}, headers=admin)
    assert r.status_code == 201, r.text
    return dict(r.json())


async def test_accept_invite_as_member(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    assert str(inv["link"]).endswith(str(inv["token"]))
    listed = (await client.get("/v1/invites", headers=admin)).json()
    assert [i["id"] for i in listed] == [inv["id"]]

    invitee = await login(INVITEE)
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=invitee)
    assert r.status_code == 200, r.text
    assert r.json()["membership"]["is_member"] is True
    assert r.json()["membership"]["is_admin"] is False
    hh = await client.get("/v1/households/me", headers=invitee)
    assert hh.status_code == 200
    # Single use.
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=invitee)
    assert r.status_code == 410
    assert r.json()["message_hi"].startswith("Invite purana ho gaya")


async def test_accept_invite_as_cook(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin, role="cook")
    cook = await login(INVITEE)
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=cook)
    assert r.status_code == 200
    assert r.json()["cook_kind"] == "hired"
    assert r.json()["membership"]["cook_id"] is not None
    assert r.json()["membership"]["is_member"] is False
    # Hired cook cannot manage members.
    assert (await client.post("/v1/members", json={"name": "X"}, headers=cook)).status_code == 403


async def test_invite_bound_to_phone(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    stranger = await login("+919877777777")
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=stranger)
    assert r.status_code == 403
    assert r.json()["code"] == "invite_phone_mismatch"


async def test_revoked_invite_cannot_be_used(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    assert (await client.delete(f"/v1/invites/{inv['id']}", headers=admin)).status_code == 204
    invitee = await login(INVITEE)
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=invitee)
    assert r.status_code == 410


async def test_expired_invite(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    async with get_sessionmaker()() as db:
        await db.execute(update(Invite).values(expires_at=utcnow() - timedelta(minutes=1)))
        await db.commit()
    invitee = await login(INVITEE)
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=invitee)
    assert r.status_code == 410


async def test_unknown_token_is_404(client: AsyncClient, login: Login) -> None:
    h = await login(INVITEE)
    assert (await client.post("/v1/invites/nope/accept", headers=h)).status_code == 404


async def test_invite_requires_login(client: AsyncClient, make_household: MakeHousehold) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    assert (await client.post(f"/v1/invites/{inv['token']}/accept")).status_code == 401


async def test_user_in_other_household_cannot_accept(
    client: AsyncClient, make_household: MakeHousehold
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    other = await make_household(INVITEE, "Other ghar")
    r = await client.post(f"/v1/invites/{inv['token']}/accept", headers=other)
    assert r.status_code == 409


async def test_only_admin_can_invite(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    member = await login(INVITEE)
    await client.post(f"/v1/invites/{inv['token']}/accept", headers=member)
    r = await client.post("/v1/invites", json={"phone": "+919866666666"}, headers=member)
    assert r.status_code == 403


async def test_cross_household_invite_revoke_is_404(
    client: AsyncClient, make_household: MakeHousehold
) -> None:
    a = await make_household("+919800000001", "A")
    b = await make_household("+919800000009", "B")
    inv = await _invite(client, a)
    assert (await client.delete(f"/v1/invites/{inv['id']}", headers=b)).status_code == 404


# ---- short invite code ("Join my family with a code") ---------------------------------


async def test_invite_returns_code_and_share_text(
    client: AsyncClient, make_household: MakeHousehold
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    code = str(inv["code"])
    assert len(code) == 6
    assert not set(code) & set("0O1I")
    text = str(inv["share_text"])
    assert code in text and str(inv["link"]) in text
    assert "Namaste" in text and "Join my family with a code" in text
    assert inv["expires_at"]
    # Hashed at rest: the plain code is not stored anywhere on the row.
    async with get_sessionmaker()() as db:
        row = await db.get(Invite, uuid.UUID(str(inv["id"])))
        assert row is not None and row.code_hash and code not in row.code_hash


async def test_accept_by_code(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    invitee = await login(INVITEE)
    typed = f" {str(inv['code'])[:3].lower()}-{str(inv['code'])[3:]} "
    r = await client.post("/v1/invites/accept-code", json={"code": typed}, headers=invitee)
    assert r.status_code == 200, r.text
    assert r.json()["membership"]["is_member"] is True
    me = (await client.get("/v1/me", headers=invitee)).json()
    assert me["membership"]["household_id"]
    # Single use: the same code again is gone.
    r = await client.post("/v1/invites/accept-code", json={"code": inv["code"]}, headers=invitee)
    assert r.status_code == 410
    assert r.json()["code"] == "invite_expired"


async def test_accept_code_errors(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    stranger = await login("+919877777777")
    r = await client.post("/v1/invites/accept-code", json={"code": "ZZZZZZ"}, headers=stranger)
    assert r.status_code == 404
    assert r.json()["code"] == "invite_code_invalid"
    r = await client.post("/v1/invites/accept-code", json={"code": inv["code"]}, headers=stranger)
    assert r.status_code == 403
    assert r.json()["code"] == "invite_phone_mismatch"
    # Revoked -> 410.
    assert (await client.delete(f"/v1/invites/{inv['id']}", headers=admin)).status_code == 204
    invitee = await login(INVITEE)
    r = await client.post("/v1/invites/accept-code", json={"code": inv["code"]}, headers=invitee)
    assert r.status_code == 410
    assert r.json()["code"] == "invite_expired"


async def test_accept_code_expired(
    client: AsyncClient, make_household: MakeHousehold, login: Login
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    async with get_sessionmaker()() as db:
        await db.execute(update(Invite).values(expires_at=utcnow() - timedelta(minutes=1)))
        await db.commit()
    invitee = await login(INVITEE)
    r = await client.post("/v1/invites/accept-code", json={"code": inv["code"]}, headers=invitee)
    assert r.status_code == 410


async def test_accept_code_already_in_household(
    client: AsyncClient, make_household: MakeHousehold
) -> None:
    admin = await make_household()
    inv = await _invite(client, admin)
    other = await make_household(INVITEE, "Other ghar")
    r = await client.post("/v1/invites/accept-code", json={"code": inv["code"]}, headers=other)
    assert r.status_code == 409
    assert r.json()["code"] == "already_in_household"


async def test_accept_code_locks_after_many_wrong(client: AsyncClient, login: Login) -> None:
    h = await login(INVITEE)
    for _ in range(10):
        r = await client.post("/v1/invites/accept-code", json={"code": "ZZZZZZ"}, headers=h)
        assert r.status_code == 404
    r = await client.post("/v1/invites/accept-code", json={"code": "ZZZZZZ"}, headers=h)
    assert r.status_code == 429
    assert r.json()["code"] == "invite_code_locked"


async def test_accept_code_requires_login(client: AsyncClient) -> None:
    r = await client.post("/v1/invites/accept-code", json={"code": "ABCDEF"})
    assert r.status_code == 401


async def test_new_invite_gets_new_code(client: AsyncClient, make_household: MakeHousehold) -> None:
    admin = await make_household()
    first = await _invite(client, admin)
    second = await _invite(client, admin)
    assert first["code"] != second["code"]
