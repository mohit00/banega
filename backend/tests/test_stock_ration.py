"""Phase 6: pantry levels, required_items, ration requests (raise / self-approval / decide /
bought / suggest), auto-decrement and the cook-mode surface."""

from __future__ import annotations

from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.db import get_sessionmaker
from app.models import Staple
from tests.conftest import Login
from tests.kitchen_fixtures import make_kitchen
from tests.pantry_fixtures import complete, hired_ticket, inbox, inbox_events, ing


async def _staple_count() -> int:
    async with get_sessionmaker()() as db:
        return int((await db.execute(select(func.count(Staple.id)))).scalar_one())


async def test_stock_defaults_in_and_levels_flow_into_required_items(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    r = await client.get("/v1/stock", headers=k.admin)
    assert r.status_code == 200, r.text
    items = r.json()
    assert len(items) == await _staple_count() > 50
    assert {i["level"] for i in items} == {"in"}
    curd = next(i for i in items if i["name"] == "Curd")
    assert curd["category"] == "dairy" and curd["ingredient_category"] == "dairy"
    assert next(i for i in items if i["name"] == "Onion")["category"] == "sabzi"

    t, cook_h = await hired_ticket(k, ["gatte", "bhindi"])
    curd_id, okra_id = await ing("curd"), await ing("okra")
    status = {i["ingredient_id"]: i["status"] for i in t["required_items"]}
    assert status[curd_id] == "in" and status[okra_id] == "untracked"

    # The cook sets dahi out: the admin hears stock_low; the ticket shows it at render time.
    r = await client.put(f"/v1/stock/{curd_id}", json={"level": "out"}, headers=cook_h)
    assert r.status_code == 200, r.text
    assert r.json()["level"] == "out" and r.json()["updated_by"]["id"]
    assert "stock_low" in await inbox_events(k, k.admin)
    after = {i["ingredient_id"]: i["status"] for i in (await k.get(t))["required_items"]}
    assert after[curd_id] == "out"
    menu = await client.get(f"/v1/menus/{t['menu_id']}", headers=k.admin)
    assert menu.status_code == 200, menu.text
    menu_items = {i["ingredient_id"]: i["status"] for i in menu.json()["required_items"]}
    assert menu_items[curd_id] == "out" and menu_items[okra_id] == "untracked"

    # qty is optional; omitted keeps it, null clears it.
    r = await client.put(
        f"/v1/stock/{curd_id}", json={"level": "low", "qty": 0.5, "unit": "kg"}, headers=k.admin
    )
    assert r.json()["qty"] == 0.5 and r.json()["unit"] == "kg"
    r = await client.put(f"/v1/stock/{curd_id}", json={"level": "in"}, headers=k.admin)
    assert r.json()["qty"] == 0.5
    r = await client.put(f"/v1/stock/{curd_id}", json={"level": "in", "qty": None}, headers=k.admin)
    assert r.json()["qty"] is None

    # Bulk, and the permission / tracking rules.
    tomato, paneer = await ing("tomato"), await ing("paneer")
    r = await client.post(
        "/v1/stock/bulk",
        json={
            "items": [
                {"ingredient_id": tomato, "level": "low"},
                {"ingredient_id": paneer, "level": "out"},
            ]
        },
        headers=k.admin,
    )
    assert r.status_code == 200 and [i["level"] for i in r.json()] == ["low", "out"]
    member = await k.invite_member()
    assert (
        await client.put(f"/v1/stock/{tomato}", json={"level": "in"}, headers=member)
    ).status_code == 403
    assert (await client.get("/v1/stock", headers=member)).status_code == 200
    r = await client.put(f"/v1/stock/{okra_id}", json={"level": "out"}, headers=k.admin)
    assert r.status_code == 422 and r.json()["code"] == "not_tracked"


async def test_ration_hired_cook_raise_decide_bought(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)
    curd_id = await ing("curd")
    await client.put(f"/v1/stock/{curd_id}", json={"level": "out"}, headers=k.admin)
    r = await client.post(
        "/v1/ration-requests",
        json={
            "ticket_id": t["id"],
            "items": [
                {"ingredient_id": curd_id, "qty": 1, "unit": "kg"},
                {"name": "pyaaz", "qty": 2},
                {"name": "kuch naya masala", "note": "blue packet"},
            ],
        },
        headers=cook_h,
    )
    assert r.status_code == 201, r.text
    req = r.json()
    assert req["status"] == "pending" and req["auto_approved"] is False
    assert req["raised_by"]["id"]
    names = [(i["name"], i["ingredient_id"]) for i in req["items"]]
    assert names[1][0] == "pyaaz" and names[1][1] == await ing("onion")  # alias match
    assert names[2] == ("kuch naya masala", None)  # free text kept
    admin_inbox = await inbox(k, k.admin)
    ration_item = next(i for i in admin_inbox if i["event"] == "ration_request")
    assert ration_item["ration_request_id"] == req["id"]
    pending = (await client.get("/v1/approvals?status=pending", headers=k.admin)).json()
    assert [a["type"] for a in pending] == ["ration"] and "Ration" in pending[0]["detail"]

    # Bought before approval: 409 not_approved.
    r = await client.post(f"/v1/ration-requests/{req['id']}/bought", headers=k.admin)
    assert r.status_code == 409 and r.json()["code"] == "not_approved"
    # The cook cannot approve; the admin can; the second answer loses.
    r = await client.post(
        f"/v1/ration-requests/{req['id']}/decide", json={"decision": "approved"}, headers=cook_h
    )
    assert r.status_code == 403
    r = await client.post(
        f"/v1/ration-requests/{req['id']}/decide", json={"decision": "approved"}, headers=k.admin
    )
    assert r.status_code == 200 and r.json()["status"] == "approved"
    assert r.json()["decided_by"]["id"]
    r = await client.post(
        f"/v1/ration-requests/{req['id']}/decide", json={"decision": "rejected"}, headers=k.admin
    )
    assert r.status_code == 409 and r.json()["code"] == "already_decided"
    assert "ration_decided" in await inbox_events(k, cook_h)
    assert (await client.get("/v1/approvals?status=pending", headers=k.admin)).json() == []

    r = await client.post(f"/v1/ration-requests/{req['id']}/bought", headers=k.admin)
    assert r.status_code == 200 and r.json()["status"] == "bought"
    stock = {
        i["ingredient_id"]: i["level"]
        for i in (await client.get("/v1/stock", headers=k.admin)).json()
    }
    assert stock[curd_id] == "in"
    assert "ration_bought" in await inbox_events(k, cook_h)
    log = [e["action"] for e in (await k.get(t))["change_log"]]
    assert "ration_requested" in log and "ration_bought" in log

    # Lists: status filter; a cook-only login sees her own requests only.
    await client.post("/v1/ration-requests", json={"items": [{"name": "cheeni"}]}, headers=k.admin)
    assert len((await client.get("/v1/ration-requests", headers=k.admin)).json()) == 2
    mine = (await client.get("/v1/ration-requests", headers=cook_h)).json()
    assert [r["id"] for r in mine] == [req["id"]]
    bought = (await client.get("/v1/ration-requests?status=bought", headers=k.admin)).json()
    assert [r["id"] for r in bought] == [req["id"]]


async def test_ration_self_raise_is_auto_approved_and_rules(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    r = await client.post(
        "/v1/ration-requests", json={"items": [{"name": "dahi", "qty": 1}]}, headers=k.admin
    )
    assert r.status_code == 201
    body = r.json()
    assert body["status"] == "approved" and body["auto_approved"] is True
    assert body["note"] == "self_approved" and body["decision_note"] == "self_approved"
    assert body["items"][0]["ingredient_id"] == await ing("curd")
    approvals = (await client.get("/v1/approvals", headers=k.admin)).json()
    assert approvals[0]["auto"] is True and approvals[0]["status"] == "approved"
    # Bought straight away.
    r = await client.post(f"/v1/ration-requests/{body['id']}/bought", headers=k.admin)
    assert r.status_code == 200

    # Family cook with her own login: self-approved too (F-2-04), the admin is told.
    member_h = await k.invite_member(member="Mummy")
    await k.add_family("Mummy")
    r = await client.post(
        "/v1/ration-requests", json={"items": [{"name": "aata"}]}, headers=member_h
    )
    assert r.status_code == 201 and r.json()["auto_approved"] is True
    assert "ration_request" in await inbox_events(k, k.admin)

    # An adult member without a cook role cannot raise; empty lists are refused.
    other = await k.invite_member(phone="+919800000109")
    r = await client.post("/v1/ration-requests", json={"items": [{"name": "aata"}]}, headers=other)
    assert r.status_code == 403
    r = await client.post("/v1/ration-requests", json={"items": []}, headers=k.admin)
    assert r.status_code == 409 and r.json()["code"] == "ration_empty"


async def test_ration_suggest_from_tickets(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, _ = await hired_ticket(k)
    curd_id, paneer_id = await ing("curd"), await ing("paneer")
    await client.post(
        "/v1/stock/bulk",
        json={
            "items": [
                {"ingredient_id": curd_id, "level": "out"},
                {"ingredient_id": paneer_id, "level": "low"},
            ]
        },
        headers=k.admin,
    )
    rows = (await client.get("/v1/ration-requests/suggest?days=7", headers=k.admin)).json()
    by_id = {r["ingredient_id"]: r for r in rows}
    assert by_id[curd_id]["level"] == "out"
    assert [n["ticket_id"] for n in by_id[curd_id]["needed_for"]] == [t["id"]]
    # Low in the pantry but not on a ticket: suggested without a ticket reference.
    assert by_id[paneer_id]["needed_for"] == []
    # The window excludes the ticket 2 days out when days=1.
    rows = (await client.get("/v1/ration-requests/suggest?days=1", headers=k.admin)).json()
    assert {r["ingredient_id"]: r for r in rows}[curd_id]["needed_for"] == []


async def test_auto_decrement_on_completed(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    # Off by default: completing changes nothing.
    t, cook_h = await hired_ticket(k)
    await complete(k, t, cook_h)
    levels = {
        i["name"]: i["level"] for i in (await client.get("/v1/stock", headers=k.admin)).json()
    }
    assert set(levels.values()) == {"in"}

    r = await client.patch("/v1/households/me", json={"auto_decrement": True}, headers=k.admin)
    assert r.status_code == 200 and r.json()["household"]["auto_decrement"] is True
    # Tomato is already low: it stays low (never to out).
    tomato = await ing("tomato")
    await client.put(f"/v1/stock/{tomato}", json={"level": "low"}, headers=k.admin)
    menu = await k.menu(["gatte", "daltadka"], slot="dinner")
    t2 = (await k.confirm(menu)).json()["ticket"]
    done = await complete(k, t2, cook_h)
    levels = {
        i["name"]: i["level"] for i in (await client.get("/v1/stock", headers=k.admin)).json()
    }
    # Perishable tracked items used by the dishes drop in -> low; dry goods stay in.
    assert levels["Curd"] == "low" and levels["Garlic"] == "low" and levels["Tomato"] == "low"
    assert levels["Gram flour"] == "in" and levels["Toor dal"] == "in"
    decrement = next(e for e in done["change_log"] if e["action"] == "stock_decremented")
    assert {i["name"] for i in decrement["detail"]["items"]} >= {"Curd", "Garlic"}
    assert "Tomato" not in {i["name"] for i in decrement["detail"]["items"]}


async def test_cook_mode_pantry_surface(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    _, cook_h = await hired_ticket(k)
    assert (await client.get("/v1/stock", headers=cook_h)).status_code == 200
    curd = await ing("curd")
    assert (
        await client.put(f"/v1/stock/{curd}", json={"level": "low"}, headers=cook_h)
    ).status_code == 200
    r = await client.post("/v1/ration-requests", json={"items": [{"name": "dahi"}]}, headers=cook_h)
    assert r.status_code == 201
    assert (await client.get("/v1/ration-requests", headers=cook_h)).status_code == 200
    assert (await client.get("/v1/ration-requests/suggest", headers=cook_h)).status_code == 200
    assert (await client.get("/v1/ratings/summary", headers=cook_h)).status_code == 200
    assert (await client.get("/v1/subscription", headers=cook_h)).json()["status"] == "trial"
    for path in ("/v1/approvals", "/v1/insights/weekly"):
        r = await client.get(path, headers=cook_h)
        assert r.status_code == 403 and r.json()["details"]["reason"] == "cook_mode", path
    r = await client.post("/v1/export", headers=cook_h)
    assert r.status_code == 403 and r.json()["details"]["reason"] == "cook_mode"
