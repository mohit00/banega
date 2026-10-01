"""Cooks and duty: limits and collisions (F-2-05, FR-K20), primary/backup, the off-duty rule
(F-5.7-06, all four cases), removal (F-5.7-10), duty history (FR-K13)."""

from __future__ import annotations

from datetime import datetime, timedelta

from httpx import AsyncClient

from tests.conftest import Login
from tests.kitchen_fixtures import COOK_PHONE, future_day, make_kitchen


async def test_one_hired_cook_per_household(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    r = await client.post(
        "/v1/cooks",
        json={"kind": "hired", "phone": "+919800000177", "name": "Shyam"},
        headers=k.admin,
    )
    assert r.status_code == 409 and r.json()["code"] == "hired_cook_limit"
    # Inviting a second hired cook is refused the same way.
    r = await client.post(
        "/v1/invites", json={"phone": "+919800000177", "role": "cook"}, headers=k.admin
    )
    assert r.status_code == 409 and r.json()["code"] == "hired_cook_limit"
    # Family cooks are unlimited.
    await k.add_family("Mummy")
    await k.add_family("Dadi")
    assert len((await client.get("/v1/cooks", headers=k.admin)).json()) == 3


async def test_phone_in_other_household(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    other = await login("+919800000188")
    await client.post("/v1/households", json={"name": "Dusra ghar"}, headers=other)
    r = await client.post(
        "/v1/cooks", json={"kind": "hired", "phone": COOK_PHONE, "name": "R"}, headers=other
    )
    assert r.status_code == 409 and r.json()["code"] == "phone_in_other_household"
    # A number that is a member login elsewhere is refused too.
    r = await client.post(
        "/v1/cooks",
        json={"kind": "hired", "phone": "+919800000188", "name": "X"},
        headers=k.admin,
    )
    assert r.status_code == 409


async def test_cook_list_shape_and_admin_only(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    cook = await k.add_hired()
    assert cook["phone_masked"] == "+91******0103"
    assert cook["kind"] == "hired" and cook["login_mode"] == "own" and cook["on_duty"] is True
    member = await k.invite_member()
    r = await client.post(
        "/v1/cooks", json={"kind": "family", "member_id": k.members["Mummy"]}, headers=member
    )
    assert r.status_code == 403
    assert (await k.patch_cook("Ramesh ji", member, is_backup=True)).status_code == 403
    r = await client.post("/v1/cooks", json={"kind": "hired"}, headers=k.admin)
    assert r.status_code == 422 and r.json()["code"] == "phone_required"
    r = await client.post("/v1/cooks", json={"kind": "family"}, headers=k.admin)
    assert r.status_code == 422 and r.json()["code"] == "member_required"


async def test_primary_and_backup_are_exclusive(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    await k.add_family("Mummy")
    await k.add_family("Dadi")
    await k.patch_cook("Mummy", is_backup=True)
    await k.patch_cook("Dadi", is_backup=True)
    cooks = {c["name"]: c for c in (await client.get("/v1/cooks", headers=k.admin)).json()}
    assert [n for n, c in cooks.items() if c["is_backup"]] == ["Dadi"]
    await k.patch_cook("Dadi", is_primary=True)
    cooks = {c["name"]: c for c in (await client.get("/v1/cooks", headers=k.admin)).json()}
    assert [n for n, c in cooks.items() if c["is_primary"]] == ["Dadi"]
    assert not any(c["is_backup"] for c in cooks.values())
    r = await k.patch_cook("Mummy", is_primary=True, is_backup=True)
    assert r.status_code == 422


# ---- off duty (F-5.7-06) ----------------------------------------------------------------------


async def _setup(client: AsyncClient, login: Login):  # type: ignore[no-untyped-def]
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook_h = await k.cook_login()
    mummy = await k.add_family("Mummy")
    await k.patch_cook("Mummy", is_backup=True)
    return k, cook_h, mummy


async def test_off_duty_case1_cooking_stays(client: AsyncClient, login: Login) -> None:
    k, cook_h, _ = await _setup(client, login)
    t = await k.ticket(["gatte"])
    await k.move(t, "accepted", cook_h)
    await k.move(t, "cooking", cook_h)
    assert (await k.patch_cook("Ramesh ji", cook_h, on_duty=False)).status_code == 200
    after = await k.get(t)
    assert after["status"] == "cooking" and after["assignee"]["name"] == "Ramesh ji"


async def test_off_duty_case2_to_backup_else_unassigned(client: AsyncClient, login: Login) -> None:
    k, cook_h, mummy = await _setup(client, login)
    lunch = await k.ticket(["gatte"])
    await k.move(lunch, "accepted", cook_h)
    dinner = await k.ticket(["bhindi"], slot="dinner")
    # Backup on duty -> both go to Mummy (family: accepted).
    r = await k.patch_cook("Ramesh ji", cook_h, on_duty=False, reason="beemar")
    assert r.status_code == 200 and r.json()["on_duty"] is False
    for t in (lunch, dinner):
        after = await k.get(t)
        assert after["status"] == "accepted" and after["assignee"]["cook_id"] == mummy["id"]
        assert after["change_log"][-1]["action"] == "moved_to_backup"
        assert after["change_log"][-1]["by"]["name"] == "System"
    inbox = [i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()]
    assert "cook_off_duty" in inbox
    # Mummy (the backup herself) goes off: no other backup -> unassigned.
    await k.patch_cook("Ramesh ji", cook_h, on_duty=True)
    await k.patch_cook("Mummy", on_duty=False)
    after = await k.get(dinner)
    assert after["status"] == "unassigned" and after["assignee"] is None
    assert "ticket_unassigned" in [
        i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()
    ]


async def test_off_duty_only_tickets_due_in_the_period(client: AsyncClient, login: Login) -> None:
    k, cook_h, mummy = await _setup(client, login)
    day = future_day()
    lunch = await k.ticket(["gatte"])
    later = await k.ticket(["bhindi"], day=day + timedelta(days=3), slot="dinner")
    until = datetime.fromisoformat(lunch["due_at"]) + timedelta(hours=2)
    r = await k.patch_cook("Ramesh ji", cook_h, on_duty=False, off_duty_until=until.isoformat())
    assert r.status_code == 200 and r.json()["off_duty_until"] is not None
    assert (await k.get(lunch))["assignee"]["cook_id"] == mummy["id"]
    assert (await k.get(later))["assignee"]["name"] == "Ramesh ji"
    past = (datetime.fromisoformat(lunch["due_at"]) - timedelta(days=30)).isoformat()
    r = await k.patch_cook("Ramesh ji", cook_h, on_duty=False, off_duty_until=past)
    assert r.status_code == 422


async def test_off_duty_case3_nothing_moves_back(client: AsyncClient, login: Login) -> None:
    k, cook_h, mummy = await _setup(client, login)
    t = await k.ticket(["gatte"])
    await k.patch_cook("Ramesh ji", cook_h, on_duty=False)
    await k.patch_cook("Ramesh ji", cook_h, on_duty=True)
    after = await k.get(t)
    assert after["assignee"]["cook_id"] == mummy["id"] and after["status"] == "accepted"
    assert "cook_on_duty" in [
        i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()
    ]


async def test_off_duty_case4_new_tickets_follow_the_rule(
    client: AsyncClient, login: Login
) -> None:
    k, cook_h, mummy = await _setup(client, login)
    await k.patch_cook("Ramesh ji", cook_h, on_duty=False)
    t = await k.ticket(["gatte"])  # menu pre-filled with the (off-duty) primary
    assert t["status"] == "accepted" and t["assignee"]["cook_id"] == mummy["id"]
    await k.patch_cook("Mummy", on_duty=False)
    t2 = await k.ticket(["bhindi"], slot="dinner")
    assert t2["status"] == "unassigned"


async def test_duty_permissions_and_history(client: AsyncClient, login: Login) -> None:
    k, cook_h, _ = await _setup(client, login)
    # The cook may toggle her own duty, nothing else.
    assert (await k.patch_cook("Ramesh ji", cook_h, is_primary=False)).status_code == 403
    assert (await k.patch_cook("Mummy", cook_h, on_duty=False)).status_code == 403
    await k.patch_cook("Ramesh ji", cook_h, on_duty=False, reason="chhutti")
    await k.patch_cook("Ramesh ji", cook_h, on_duty=True)
    cid = k.cooks["Ramesh ji"]["id"]
    hist = (await client.get(f"/v1/cooks/{cid}/duty-history", headers=cook_h)).json()
    assert [(h["on_duty"], h["reason"]) for h in hist] == [(False, "chhutti"), (True, None)]
    r = await client.get(f"/v1/cooks/{cid}/duty-history?month=2020-01", headers=k.admin)
    assert r.json() == []
    me = (await client.get("/v1/me", headers=cook_h)).json()
    assert me["cook"]["on_duty"] is True


async def test_remove_cook_unassigns_and_revokes(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    cook = await k.add_hired()
    cook_h = await k.cook_login()
    t = await k.ticket(["gatte"])
    r = await client.delete(f"/v1/cooks/{cook['id']}", headers=k.admin)
    assert r.status_code == 204
    after = await k.get(t)
    assert after["status"] == "unassigned" and after["assignee"] is None
    assert after["change_log"][-1]["detail"]["reason"] == "cook_removed"
    assert (await client.get("/v1/cooks", headers=k.admin)).json() == []
    # Hired cook's sessions are revoked (F-5.7-10).
    assert (await client.get("/v1/me", headers=cook_h)).status_code == 401
    # The slot is free again.
    await k.add_hired(phone="+919800000199", name="Naya cook")


async def test_seed_demo_cooks_idempotent() -> None:
    from sqlalchemy import select

    from app.core.db import get_sessionmaker
    from app.models import Cook
    from app.services.importer import DEMO_COOK_PHONE, load_demo_household, load_json

    async with get_sessionmaker()() as db:
        for _ in range(2):
            await load_demo_household(db, load_json("demo-household.seed.json"))
        await db.commit()
        cooks = {c.name: c for c in (await db.execute(select(Cook))).scalars()}
    assert set(cooks) == {"Ramesh ji", "Mummy"}
    ramesh, mummy = cooks["Ramesh ji"], cooks["Mummy"]
    assert (ramesh.kind, ramesh.phone, ramesh.is_primary, ramesh.on_duty) == (
        "hired",
        DEMO_COOK_PHONE,
        True,
        True,
    )
    assert (mummy.kind, mummy.login_mode, mummy.is_backup) == ("family", "via_admin", True)
