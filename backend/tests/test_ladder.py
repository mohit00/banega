"""Phase 6: the out-of-stock ladder (FRD §5.9, F-5.9-01): save_dish / swap / change_dish,
engine re-check for every eater (allergen-safe swaps), §2.1 approvals (self-approval, first
response wins) and the 30-minute expiry with a fake clock."""

from __future__ import annotations

from datetime import timedelta
from typing import Any

from httpx import AsyncClient

from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.services import ladder
from tests.conftest import Login
from tests.kitchen_fixtures import Kitchen, make_kitchen
from tests.pantry_fixtures import hired_ticket, inbox, inbox_events, ing


async def _out(k: Kitchen, t: dict[str, Any], slug: str, headers: dict[str, str]) -> dict[str, Any]:
    r = await k.client.post(
        f"/v1/tickets/{t['id']}/items/{await ing(slug)}/out",
        headers={**headers, "Idempotency-Key": f"out-{t['id']}-{slug}"},
    )
    assert r.status_code == 200, r.text
    return dict(r.json())


async def _resolve(k: Kitchen, t: dict[str, Any], headers: dict[str, str], **body: Any) -> Any:
    return await k.client.post(
        f"/v1/tickets/{t['id']}/stock-issue/resolve", json=body, headers=headers
    )


def _actions(ticket: dict[str, Any]) -> list[str]:
    return [e["action"] for e in ticket["change_log"]]


async def test_save_dish_skip_needs_no_approval(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k, ["bhindi"])
    body = await _out(k, t, "onion", cook_h)
    ladder_ = body["ladder"]
    assert ladder_["step"] == "save_dish"
    skip = ladder_["options"]["save_dish"]
    assert skip["type"] == "skip" and skip["ok"] is True
    # Dadi is Jain: leaving out the onion is always fine (and the curated rule agrees).
    assert skip["reason"] in ("jain", "rule")
    assert skip["ingredient"]["ingredient_id"] == await ing("onion")
    assert body["stock_issue"]["state"] == "open"
    item_out = next(e for e in body["change_log"] if e["action"] == "item_out")
    assert item_out["detail"]["step"] == "save_dish"

    r = await _resolve(k, t, cook_h, action="skip")
    assert r.status_code == 200, r.text
    after = r.json()
    assert after["stock_issue_open"] is False
    assert after["stock_issue"]["state"] == "resolved" and after["stock_issue"]["action"] == "skip"
    assert "stock_skip" in _actions(after)
    swap = after["dishes"][0]["swaps"][0]
    assert swap["from_ingredient_id"] == await ing("onion") and swap["to_ingredient_id"] is None
    assert await ing("onion") not in {i["ingredient_id"] for i in after["required_items"]}
    # Nothing left to resolve.
    r = await _resolve(k, t, cook_h, action="skip")
    assert r.status_code == 409 and r.json()["code"] == "no_stock_issue"


async def test_swap_self_approved_by_hired_cook(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)
    body = await _out(k, t, "curd", cook_h)
    ladder_ = body["ladder"]
    assert ladder_["step"] == "swap"
    assert ladder_["options"]["save_dish"]["ok"] is False
    swaps = ladder_["options"]["swap"]
    milk = await ing("milk")
    assert [s["substitute_ingredient_id"] for s in swaps] == [milk]
    assert swaps[0]["fit_after"]["badge"] in ("fit", "tweak", "no") and swaps[0]["note_hi"]
    assert len(ladder_["options"]["change_dish"]) <= 3
    # The pantry now says dahi is out.
    stock = {
        i["ingredient_id"]: i["level"]
        for i in (await client.get("/v1/stock", headers=k.admin)).json()
    }
    assert stock[await ing("curd")] == "out"

    r = await _resolve(k, t, cook_h, action="skip")
    assert r.status_code == 422 and r.json()["code"] == "skip_not_allowed"
    r = await _resolve(k, t, cook_h, action="swap", substitute_ingredient_id=await ing("paneer"))
    assert r.status_code == 422 and r.json()["code"] == "invalid_substitute"

    # cook_can_approve_swaps (default on): the hired cook's swap is applied at once.
    r = await _resolve(k, t, cook_h, action="swap", substitute_ingredient_id=milk)
    assert r.status_code == 200, r.text
    after = r.json()
    assert after["stock_issue_open"] is False
    assert after["stock_issue"]["state"] == "resolved" and after["stock_issue"]["action"] == "swap"
    assert "Curd" in after["stock_issue"]["detail"] and "Milk" in after["stock_issue"]["detail"]
    assert _actions(after)[-2:] == ["approval_requested", "stock_swap"]
    assert after["change_log"][-2]["detail"]["self_approved"] is True
    gatte = next(d for d in after["dishes"] if d["name"].startswith("Gatte"))
    assert gatte["swaps"][0]["to_ingredient_id"] == milk
    items = {i["ingredient_id"] for i in after["required_items"]}
    assert milk in items and await ing("curd") not in items
    approvals = (await client.get("/v1/approvals", headers=k.admin)).json()
    assert approvals[0]["auto"] is True and approvals[0]["decision"] == "approved"


async def test_swap_needs_approval_first_response_wins(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    r = await client.patch(
        "/v1/households/me", json={"cook_can_approve_swaps": False}, headers=k.admin
    )
    assert r.status_code == 200
    t, cook_h = await hired_ticket(k)
    await _out(k, t, "curd", cook_h)
    r = await _resolve(k, t, cook_h, action="swap", substitute_ingredient_id=await ing("milk"))
    assert r.status_code == 200, r.text
    pending_ticket = r.json()
    assert pending_ticket["stock_issue_open"] is True
    card = pending_ticket["stock_issue"]
    assert card["state"] == "pending_approval" and card["approval_id"] and card["expires_at"]
    # A second resolve while waiting: 409.
    r = await _resolve(k, t, cook_h, action="swap", substitute_ingredient_id=await ing("milk"))
    assert r.status_code == 409 and r.json()["code"] == "approval_pending"

    for h in (k.admin, member):
        items = await inbox(k, h)
        req = next(i for i in items if i["event"] == "approval_request")
        assert req["approval_id"] == card["approval_id"]
    pending = (await client.get("/v1/approvals?status=pending", headers=member)).json()
    assert len(pending) == 1 and pending[0]["type"] == "swap"
    assert pending[0]["detail"] == "Curd → Milk" and pending[0]["requested_by"]["id"]

    # An adult member answers first; the admin's later answer loses.
    r = await client.post(
        f"/v1/approvals/{card['approval_id']}/decide", json={"decision": "approved"}, headers=member
    )
    assert r.status_code == 200 and r.json()["status"] == "approved"
    r = await client.post(
        f"/v1/approvals/{card['approval_id']}/decide",
        json={"decision": "rejected"},
        headers=k.admin,
    )
    assert r.status_code == 409 and r.json()["code"] == "already_decided"
    after = await k.get(t)
    assert after["stock_issue_open"] is False
    assert _actions(after)[-2:] == ["approval_approved", "stock_swap"]
    assert "approval_decided" in await inbox_events(k, cook_h)
    # The hired cook cannot decide approvals at all (cook mode).
    r = await client.post(
        f"/v1/approvals/{card['approval_id']}/decide", json={"decision": "approved"}, headers=cook_h
    )
    assert r.status_code == 403


async def test_rejected_swap_keeps_issue_open(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await client.patch("/v1/households/me", json={"cook_can_approve_swaps": False}, headers=k.admin)
    t, cook_h = await hired_ticket(k)
    await _out(k, t, "curd", cook_h)
    r = await _resolve(k, t, cook_h, action="swap", substitute_ingredient_id=await ing("milk"))
    approval_id = r.json()["stock_issue"]["approval_id"]
    r = await client.post(
        f"/v1/approvals/{approval_id}/decide", json={"decision": "rejected"}, headers=k.admin
    )
    assert r.status_code == 200 and r.json()["decision"] == "rejected"
    after = await k.get(t)
    assert after["stock_issue_open"] is True and after["stock_issue"]["state"] == "open"
    assert "approval_rejected" in _actions(after)


async def test_swaps_are_allergen_safe(client: AsyncClient, login: Login) -> None:
    """moongphali -> kaju is offered, except when someone at the table is tree-nut allergic
    (O2: the engine re-checks every eater; the swap would add a new No)."""
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k, ["poha"])
    ladder_ = (await _out(k, t, "peanut", cook_h))["ladder"]
    assert await ing("cashew") in [
        s["substitute_ingredient_id"] for s in ladder_["options"]["swap"]
    ]

    await k.add_member("Chacha", allergens=["tree_nut"])
    menu = await k.menu(["poha"], slot="dinner", eaters=list(k.members.values()))
    t2 = (await k.confirm(menu)).json()["ticket"]
    assert "Chacha" in [e["name"] for e in t2["eaters"]]
    ladder_ = (await _out(k, t2, "peanut", cook_h))["ladder"]
    assert await ing("cashew") not in [
        s["substitute_ingredient_id"] for s in ladder_["options"]["swap"]
    ]
    assert ladder_["step"] == "change_dish"
    for card in ladder_["options"]["change_dish"]:
        assert "tree_nut" not in card["flags"]["allergens"]


async def test_swap_dropped_when_substitute_out_then_change_dish(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    await client.put(f"/v1/stock/{await ing('milk')}", json={"level": "out"}, headers=k.admin)
    await client.put(f"/v1/stock/{await ing('toor-dal')}", json={"level": "out"}, headers=k.admin)
    t, cook_h = await hired_ticket(k)
    ladder_ = (await _out(k, t, "curd", cook_h))["ladder"]
    assert ladder_["options"]["swap"] == [] and ladder_["step"] == "change_dish"
    alts = ladder_["options"]["change_dish"]
    assert 1 <= len(alts) <= 3
    names = {a["slug"] for a in alts}
    assert not names & {"gatte", "daltadka"}  # not already on the ticket
    assert "daltadka" not in names and "curdrice" not in names and "kadhi" not in names
    for a in alts:
        assert "lunch" in a["meal_slots"]


async def test_change_dish_needs_approval_and_expires(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await hired_ticket(k)
    ladder_ = (await _out(k, t, "curd", cook_h))["ladder"]
    alt = ladder_["options"]["change_dish"][0]
    r = await _resolve(k, t, cook_h, action="change_dish", recipe_id=await ing("curd"))
    assert r.status_code == 422 and r.json()["code"] == "invalid_recipe"
    # A hired cook never approves a dish change herself.
    r = await _resolve(k, t, cook_h, action="change_dish", recipe_id=alt["id"])
    assert r.status_code == 200, r.text
    card = r.json()["stock_issue"]
    assert card["state"] == "pending_approval"

    # 30 minutes with no answer: expired, the admin is alerted, the ticket stays flagged.
    async with get_sessionmaker()() as db:
        assert await ladder.expire_approvals(db, utcnow() + timedelta(minutes=29)) == []
        done = await ladder.expire_approvals(db, utcnow() + timedelta(minutes=31))
        await db.commit()
    assert [str(x) for x in done] == [card["approval_id"]]
    after = await k.get(t)
    assert after["stock_issue_open"] is True and after["stock_issue"]["state"] == "timed_out"
    assert "stock_issue_timeout" in _actions(after)
    timeout = next(i for i in await inbox(k, k.admin) if i["event"] == "stock_issue_timeout")
    assert timeout["approval_id"] == card["approval_id"]
    r = await client.post(
        f"/v1/approvals/{card['approval_id']}/decide",
        json={"decision": "approved"},
        headers=k.admin,
    )
    assert r.status_code == 409 and r.json()["code"] == "already_decided"
    expired = (await client.get("/v1/approvals?status=expired", headers=k.admin)).json()
    assert [a["id"] for a in expired] == [card["approval_id"]]

    # The cook asks again; this time the admin approves and the dish is replaced.
    r = await _resolve(k, t, cook_h, action="change_dish", recipe_id=alt["id"])
    approval_id = r.json()["stock_issue"]["approval_id"]
    r = await client.post(
        f"/v1/approvals/{approval_id}/decide", json={"decision": "approved"}, headers=k.admin
    )
    assert r.status_code == 200
    final = await k.get(t)
    assert alt["id"] in [d["recipe_id"] for d in final["dishes"]]
    assert "gatte" not in [d["name"].lower().split()[0] for d in final["dishes"]]
    assert final["stock_issue_open"] is False and "stock_change_dish" in _actions(final)
    menu = await client.get(f"/v1/menus?date={t['date']}&slot=lunch", headers=k.admin)
    assert alt["id"] in [d["recipe_id"] for d in menu.json()["dishes"]]


async def test_family_cook_dish_change_self_approved_admin_notified(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    mummy_h = await k.invite_member(member="Mummy")
    mummy = await k.add_family("Mummy")
    t = await k.ticket(["gatte"], assignee_cook_id=mummy["id"])
    assert t["status"] == "accepted"
    ladder_ = (await _out(k, t, "curd", mummy_h))["ladder"]
    alt = ladder_["options"]["change_dish"][0]
    r = await _resolve(k, t, mummy_h, action="change_dish", recipe_id=alt["id"])
    assert r.status_code == 200, r.text
    after = r.json()
    assert after["stock_issue"]["state"] == "resolved"
    assert [d["recipe_id"] for d in after["dishes"]] == [alt["id"]]
    assert "stock_issue_resolved" in await inbox_events(k, k.admin)
    # Members cannot mark items out on somebody else's ticket.
    member2 = await k.invite_member(phone="+919800000119")
    r = await client.post(f"/v1/tickets/{t['id']}/items/{await ing('besan')}/out", headers=member2)
    assert r.status_code == 403
