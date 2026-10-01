"""Tickets over HTTP: confirm variants, lifecycle, 409 body, edit rules (FR-K7), claim (K16),
item out, messages (K6), the recipe scaled to the ticket (K5), lists and concurrency."""

from __future__ import annotations

from typing import Any

from httpx import AsyncClient

from tests.conftest import Login
from tests.kitchen_fixtures import COOK_PHONE, Kitchen, future_day, make_kitchen

# ---- confirm variants ---------------------------------------------------------------------


async def test_confirm_with_hired_cook_is_new_and_notifies_cook(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    cook = await k.add_hired()
    assert cook["is_primary"]  # the first cook becomes primary
    cook_h = await k.cook_login()
    menu = await k.menu(["gatte", "daltadka"], notes="Kam tel")
    assert menu["assignee"] == {"cook_id": cook["id"], "name": "Ramesh ji", "kind": "hired"}
    r = await k.confirm(menu)
    assert r.status_code == 200, r.text
    body = r.json()
    t = body["ticket"]
    assert t["status"] == "new" and t["assignee"]["cook_id"] == cook["id"]
    assert [d["name"] for d in t["dishes"]] == ["Gatte ki Sabzi", "Dal Tadka & Jeera Rice"]
    assert t["servings"] == 3.5 and t["notes"] == "Kam tel" and t["updated"] is False
    assert t["required_items"] and t["stock_issue_open"] is False
    assert t["change_log"][0]["action"] == "created"
    assert t["change_log"][0]["by"]["user_id"] is not None
    assert t["allowed_next"] == ["cancelled"]  # admin: cancel only; the cook accepts
    assert "*Lunch - " in body["share_text"]
    # Menu now points at its ticket.
    m = (await client.get(f"/v1/menus?date={menu['date']}&slot=lunch", headers=k.admin)).json()
    assert m["ticket_id"] == t["id"]
    # The cook got ticket_created in the inbox.
    inbox = (await client.get("/v1/inbox", headers=cook_h)).json()
    assert [i["event"] for i in inbox] == ["ticket_created"]
    assert inbox[0]["ticket_id"] == t["id"]


async def test_confirm_with_family_cook_is_accepted(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    mummy = await k.add_family("Mummy")
    assert mummy["login_mode"] == "via_admin"  # profile-only member (F-2-03)
    t = await k.ticket(["gatte"], assignee_cook_id=mummy["id"])
    assert t["status"] == "accepted" and t["accepted_at"] is not None
    # The admin runs a via-admin cook's buttons: start and complete.
    assert t["allowed_next"] == ["cooking", "cancelled"]
    assert (await k.move(t, "cooking")).json()["status"] == "cooking"
    done = (await k.move(t, "completed")).json()
    assert done["status"] == "completed" and done["completed_by"] is not None


async def test_confirm_self_is_accepted_and_self_approved(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    papa = await k.add_family("Papa")  # the admin's own profile: her own login
    assert papa["login_mode"] == "own" and papa["user_id"] is not None
    t = await k.ticket(["gatte"], assignee_cook_id=papa["id"])
    assert t["status"] == "accepted"
    created = t["change_log"][0]
    assert created["detail"]["reason"] == "self" and created["detail"]["self_approved"] is True
    # She is not notified about her own ticket.
    assert (await client.get("/v1/inbox", headers=k.admin)).json() == []


async def test_confirm_without_assignee_is_unassigned_and_alerts_admin(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    t = await k.ticket(["gatte"], headers=member)  # no cooks at all
    assert t["status"] == "unassigned" and t["assignee"] is None
    inbox = (await client.get("/v1/inbox", headers=k.admin)).json()
    assert [i["event"] for i in inbox] == ["ticket_unassigned"]
    # Explicit null assignee also gives unassigned.
    cook = await k.add_hired()
    menu = await k.menu(["bhindi"], slot="dinner", assignee_cook_id=None)
    assert menu["assignee"] is None
    assert (await k.confirm(menu)).json()["ticket"]["status"] == "unassigned"
    assert cook["id"]


async def test_confirm_off_duty_cook_goes_to_backup_or_unassigned(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    mummy = await k.add_family("Mummy")
    r = await k.patch_cook("Ramesh ji", on_duty=False)
    assert r.status_code == 200 and r.json()["on_duty"] is False
    # No backup yet -> unassigned.
    t = await k.ticket(["gatte"])
    assert t["status"] == "unassigned"
    assert t["change_log"][0]["detail"]["reason"] == "off_duty_unassigned"
    # Mummy is the on-duty backup -> the dinner goes to her, accepted.
    assert (await k.patch_cook("Mummy", is_backup=True)).json()["is_backup"] is True
    menu = await k.menu(["bhindi"], slot="dinner")
    t2 = (await k.confirm(menu)).json()["ticket"]
    assert t2["status"] == "accepted" and t2["assignee"]["cook_id"] == mummy["id"]
    assert t2["change_log"][0]["detail"]["reason"] == "off_duty_backup"


async def test_confirm_rules(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    empty = await k.menu([])
    r = await k.confirm(empty)
    assert r.status_code == 422 and r.json()["code"] == "menu_empty"
    menu = await k.menu(["gatte"], slot="dinner")
    # Wrong If-Match -> 412 version_mismatch.
    r = await client.post(f"/v1/menus/{menu['id']}/confirm", headers={**k.admin, "If-Match": "99"})
    assert r.status_code == 412 and r.json()["code"] == "version_mismatch"
    # Idempotency-Key: a retried confirm replays the first response.
    headers = {**k.admin, "Idempotency-Key": "confirm-1", "If-Match": str(menu["version"])}
    first = await client.post(f"/v1/menus/{menu['id']}/confirm", headers=headers)
    again = await client.post(f"/v1/menus/{menu['id']}/confirm", headers=headers)
    assert first.status_code == again.status_code == 200
    assert again.headers.get("idempotent-replayed") == "true"
    assert first.json()["ticket"]["id"] == again.json()["ticket"]["id"]
    # Without the key, a second confirm is 409 menu_already_confirmed.
    r = await k.confirm(menu)
    assert r.status_code == 409 and r.json()["code"] == "menu_already_confirmed"
    # Cancelled: the menu can be confirmed again into a new ticket.
    tid = first.json()["ticket"]["id"]
    assert (await k.move({"id": tid}, "cancelled")).status_code == 200
    r = await k.confirm(menu)
    assert r.status_code == 200 and r.json()["ticket"]["id"] != tid


async def test_members_confirm_only_when_setting_on(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    await client.patch(
        "/v1/households/me", json={"members_can_send_to_cook": False}, headers=k.admin
    )
    menu = await k.menu(["gatte"], headers=member)
    assert (await k.confirm(menu, member)).status_code == 403


# ---- lifecycle ------------------------------------------------------------------------------


async def _hired_ticket(k: Kitchen, **patch: Any) -> tuple[dict[str, Any], dict[str, str]]:
    await k.add_hired()
    cook_h = await k.cook_login()
    return await k.ticket(["gatte", "daltadka"], **patch), cook_h


async def test_hired_lifecycle_and_notifications(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await _hired_ticket(k)
    r = await k.move(t, "accepted", cook_h)
    assert r.status_code == 200 and r.json()["status"] == "accepted"
    assert r.json()["allowed_next"] == ["cooking"]
    assert (await k.move(t, "cooking", cook_h)).json()["started_at"] is not None
    assert (await k.move(t, "ready", cook_h)).json()["status"] == "ready"
    done = (await k.move(t, "completed", cook_h)).json()
    assert done["status"] == "completed" and done["completed_at"] is not None
    actions = [e["action"] for e in done["change_log"]]
    assert actions == ["created", "accepted", "cooking", "ready", "completed"]
    assert done["change_log"][1]["by"]["name"] == ""  # the cook's login has no name yet
    events = [i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()]
    # Newest first: completed (confirmer + admin, deduplicated), accepted (confirmer).
    # Phase 7: completion also prompts the confirmer/admin to rate.
    assert "rate_prompt" in events
    assert [e for e in events if e != "rate_prompt"] == ["ticket_completed", "ticket_accepted"]


async def test_invalid_transition_body(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await _hired_ticket(k)
    r = await k.move(t, "cooking", cook_h)  # must accept first
    assert r.status_code == 409
    body = r.json()
    assert body["code"] == "invalid_transition"
    assert body["allowed"] == ["accepted"] == body["details"]["allowed"]
    # A pair that exists but not for this caller: 403.
    r = await k.move(t, "accepted")  # the admin cannot accept for an app-using cook
    assert r.status_code == 403 and r.json()["details"]["allowed"] == ["cancelled"]


async def test_cancel_rules(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    await k.add_hired()
    cook_h = await k.cook_login()
    t = await k.ticket(["gatte"], headers=member)
    # The confirming member may cancel before Accepted...
    t2 = await k.ticket(["bhindi"], slot="dinner", headers=member)
    assert (await k.move(t2, "cancelled", member)).json()["status"] == "cancelled"
    # ...not after.
    await k.move(t, "accepted", cook_h)
    assert (await k.move(t, "cancelled", member)).status_code == 403
    await k.move(t, "cooking", cook_h)
    # Cancel while cooking: admin only, reason required.
    r = await k.move(t, "cancelled")
    assert r.status_code == 422 and r.json()["code"] == "reason_required"
    r = await k.move(t, "cancelled", reason="Bahar kha rahe hain")
    assert r.status_code == 200 and r.json()["cancel_reason"] == "Bahar kha rahe hain"
    cancelled = [i["event"] for i in (await client.get("/v1/inbox", headers=cook_h)).json()]
    assert "ticket_cancelled" in cancelled


async def test_admin_reassigns_unassigned(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t = await k.ticket(["gatte"])
    assert t["status"] == "unassigned"
    cook = await k.add_hired()
    mummy = await k.add_family("Mummy")
    r = await k.move(t, "new")
    assert r.status_code == 422 and r.json()["code"] == "assignee_required"
    r = await k.move(t, "accepted", assignee_cook_id=cook["id"])  # hired -> must be new
    assert r.status_code == 409 and r.json()["allowed"] == ["new"]
    r = await k.move(t, "new", assignee_cook_id=cook["id"])
    assert r.status_code == 200 and r.json()["assignee"]["cook_id"] == cook["id"]
    t2 = await k.ticket(["bhindi"], slot="dinner", assignee_cook_id=None)
    r = await k.move(t2, "accepted", assignee_cook_id=mummy["id"])
    assert r.json()["status"] == "accepted"


# ---- edit rules (FR-K7) ------------------------------------------------------------------------


async def test_edit_hired_ticket_returns_to_new_updated(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await _hired_ticket(k)
    await k.move(t, "accepted", cook_h)
    v = (await k.get(t))["version"]
    r = await client.patch(
        f"/v1/tickets/{t['id']}",
        json={"dishes": [str(k.recipes["gatte"])], "notes": "Bina lahsun"},
        headers={**k.admin, "If-Match": str(v)},
    )
    assert r.status_code == 200, r.text
    e = r.json()
    assert e["status"] == "new" and e["updated"] is True and e["version"] == v + 1
    edited = e["change_log"][-1]
    assert edited["action"] == "edited"
    assert edited["detail"]["changes"]["dishes"]["after"] == ["Gatte ki Sabzi"]
    assert set(edited["detail"]["changes"]) == {"dishes", "notes"}
    # The menu follows the ticket.
    m = (await client.get(f"/v1/menus?date={t['date']}&slot=lunch", headers=k.admin)).json()
    assert [d["name"] for d in m["dishes"]] == ["Gatte ki Sabzi"] and m["notes"] == "Bina lahsun"
    # The cook is told and re-accepts; accepting clears the tag.
    assert "ticket_updated" in [
        i["event"] for i in (await client.get("/v1/inbox", headers=cook_h)).json()
    ]
    again = (await k.move(t, "accepted", cook_h)).json()
    assert again["status"] == "accepted" and again["updated"] is False
    # Stale If-Match -> 412.
    r = await client.patch(
        f"/v1/tickets/{t['id']}", json={"notes": "x"}, headers={**k.admin, "If-Match": str(v)}
    )
    assert r.status_code == 412


async def test_edit_family_ticket_stays_accepted(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member(member="Mummy")
    mummy = await k.add_family("Mummy")
    assert mummy["login_mode"] == "own"
    t = await k.ticket(["gatte"], assignee_cook_id=mummy["id"])
    r = await client.patch(
        f"/v1/tickets/{t['id']}", json={"guests": {"adults": 2, "kids": 0}}, headers=k.admin
    )
    e = r.json()
    assert e["status"] == "accepted" and e["updated"] is True
    assert e["servings"] == 5.5  # recomputed from eaters + guests
    # Her own edit is self-approved: no "updated" tag.
    r = await client.patch(
        f"/v1/tickets/{t['id']}", json={"notes": "Main bana rahi hoon"}, headers=member
    )
    assert r.status_code == 200
    assert r.json()["updated"] is False
    assert r.json()["change_log"][-1]["detail"]["self_approved"] is True


async def test_edit_during_cooking_only_notes_and_closed_not_at_all(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await _hired_ticket(k)
    await k.move(t, "accepted", cook_h)
    await k.move(t, "cooking", cook_h)
    r = await client.patch(f"/v1/tickets/{t['id']}", json={"servings": 8}, headers=k.admin)
    assert r.status_code == 409 and r.json()["code"] == "edit_locked"
    r = await client.patch(f"/v1/tickets/{t['id']}", json={"notes": "Jaldi"}, headers=k.admin)
    assert r.status_code == 200 and r.json()["status"] == "cooking"
    await k.move(t, "completed", cook_h)
    r = await client.patch(f"/v1/tickets/{t['id']}", json={"notes": "x"}, headers=k.admin)
    assert r.status_code == 409 and r.json()["code"] == "ticket_closed"
    # A hired cook cannot edit at all.
    t2 = await k.ticket(["bhindi"], slot="dinner")
    r = await client.patch(f"/v1/tickets/{t2['id']}", json={"notes": "x"}, headers=cook_h)
    assert r.status_code == 403


async def test_member_edits_only_own_before_accept(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    t, cook_h = await _hired_ticket(k)  # confirmed by the admin
    r = await client.patch(f"/v1/tickets/{t['id']}", json={"notes": "x"}, headers=member)
    assert r.status_code == 403
    mine = await k.ticket(["bhindi"], slot="dinner", headers=member)
    r = await client.patch(f"/v1/tickets/{mine['id']}", json={"notes": "x"}, headers=member)
    assert r.status_code == 200
    await k.move(mine, "accepted", cook_h)
    r = await client.patch(f"/v1/tickets/{mine['id']}", json={"notes": "y"}, headers=member)
    assert r.status_code == 403


# ---- claim (Chef for the day) ------------------------------------------------------------------


async def test_claim_first_wins(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member(member="Mummy")
    t = await k.ticket(["gatte"])
    assert t["status"] == "unassigned"
    r = await client.post(f"/v1/tickets/{t['id']}/claim", headers=member)
    assert r.status_code == 200, r.text
    c = r.json()
    assert c["status"] == "accepted" and c["assignee"]["name"] == "Mummy"
    assert c["assignee"]["kind"] == "family" and c["change_log"][-1]["action"] == "claimed"
    # Second claim loses.
    r = await client.post(f"/v1/tickets/{t['id']}/claim", headers=k.admin)
    assert r.status_code == 409 and r.json()["code"] == "already_claimed"
    # She now holds a family cook role and sees the ticket as hers.
    me = (await client.get("/v1/me", headers=member)).json()
    assert me["modes"] == ["family", "cook"] and me["cook"]["kind"] == "family"
    mine = (await client.get(f"/v1/tickets?mine=true&date={t['date']}", headers=member)).json()
    assert [x["id"] for x in mine] == [t["id"]]
    assert "chef_claimed" in [
        i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()
    ]


async def test_claim_with_stale_version_is_412(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    t = await k.ticket(["gatte"])
    r = await client.post(
        f"/v1/tickets/{t['id']}/claim", headers={**member, "If-Match": str(t["version"] + 1)}
    )
    assert r.status_code == 412


async def test_hired_cook_cannot_claim(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook_h = await k.cook_login()
    t = await k.ticket(["gatte"], assignee_cook_id=None)
    # Claiming is not part of cook mode (hired: "n/a" in §2.1).
    assert (await client.post(f"/v1/tickets/{t['id']}/claim", headers=cook_h)).status_code == 403


# ---- item out, messages, recipe, lists -----------------------------------------------------------


async def test_item_out_sets_flag_and_alerts(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    t, cook_h = await _hired_ticket(k)
    ing = t["required_items"][0]["ingredient_id"]
    r = await client.post(
        f"/v1/tickets/{t['id']}/items/{ing}/out",
        headers={**cook_h, "Idempotency-Key": "out-1"},
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["stock_issue_open"] is True and body["status"] == "new"
    assert body["change_log"][-1]["action"] == "item_out"
    assert body["change_log"][-1]["detail"]["ingredient_id"] == ing
    for h in (k.admin, member):  # admin + approvers
        events = [i["event"] for i in (await client.get("/v1/inbox", headers=h)).json()]
        assert "stock_issue" in events
    # Members cannot mark items out.
    r = await client.post(f"/v1/tickets/{t['id']}/items/{ing}/out", headers=member)
    assert r.status_code == 403


async def test_messages_thread(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await _hired_ticket(k)
    r = await client.post(
        f"/v1/tickets/{t['id']}/messages",
        json={"text": "Dahi khatam hai, kya karoon?"},
        headers=cook_h,
    )
    assert r.status_code == 201, r.text
    msg = r.json()
    assert msg["author"] == {
        "user_id": msg["author"]["user_id"],
        "name": "Ramesh ji",
        "role": "cook",
    }
    await client.post(
        f"/v1/tickets/{t['id']}/messages", json={"text": "Raita skip karo"}, headers=k.admin
    )
    thread = (await client.get(f"/v1/tickets/{t['id']}/messages", headers=cook_h)).json()
    assert [(m["text"], m["author"]["role"]) for m in thread] == [
        ("Dahi khatam hai, kya karoon?", "cook"),
        ("Raita skip karo", "family"),
    ]
    admin_events = [i["event"] for i in (await client.get("/v1/inbox", headers=k.admin)).json()]
    cook_events = [i["event"] for i in (await client.get("/v1/inbox", headers=cook_h)).json()]
    assert "cook_message" in admin_events and "family_message" in cook_events


async def test_recipe_scaled_to_ticket(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    t, cook_h = await _hired_ticket(k, guests={"adults": 2, "kids": 1})
    assert t["servings"] == 6.0
    gatte = str(k.recipes["gatte"])
    r = await client.get(f"/v1/tickets/{t['id']}/recipes/{gatte}", headers=cook_h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["servings"] == 6 and body["scale_factor"] == 1.5
    assert body["fits"] == []  # F-5.7-05: no member reasons in cook mode
    assert len(body["audio"]["steps_hi"]) == len(body["steps_hi"] or body["steps_en"])
    assert all(x is None for x in body["audio"]["steps_hi"])
    # Explicit servings; a recipe that is not in the ticket is 404.
    r = await client.get(f"/v1/tickets/{t['id']}/recipes/{gatte}?servings=2", headers=k.admin)
    assert r.json()["servings"] == 2 and r.json()["fits"]
    other = str(k.recipes["bhindi"])
    r = await client.get(f"/v1/tickets/{t['id']}/recipes/{other}", headers=cook_h)
    assert r.status_code == 404


async def test_list_filters_and_sorting(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    await k.add_hired()
    cook_h = await k.cook_login()
    day = future_day()
    dinner = await k.ticket(["bhindi"], slot="dinner")
    nashta = await k.ticket(["poha"], slot="nashta")
    unassigned = await k.ticket(["gatte"], assignee_cook_id=None)
    all_ = (await client.get(f"/v1/tickets?date={day}", headers=k.admin)).json()
    assert [t["slot"] for t in all_] == ["nashta", "lunch", "dinner"]  # by due_at
    new = (await client.get(f"/v1/tickets?date={day}&status=new", headers=k.admin)).json()
    assert {t["id"] for t in new} == {dinner["id"], nashta["id"]}
    # A cook-only login always gets her own tickets.
    mine = (await client.get(f"/v1/tickets?date={day}", headers=cook_h)).json()
    assert [t["id"] for t in mine] == [nashta["id"], dinner["id"]]
    assert (await client.get(f"/v1/tickets/{unassigned['id']}", headers=cook_h)).status_code == 404
    other_day = (await client.get("/v1/tickets?date=today&mine=true", headers=cook_h)).json()
    assert other_day == []
    r = await client.get("/v1/tickets?date=kal", headers=k.admin)
    assert r.status_code == 422


async def test_cook_logs_in_by_phone_and_gets_cook_mode(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    cook = await k.add_hired()
    h = await login(COOK_PHONE)
    me = (await client.get("/v1/me", headers=h)).json()
    assert me["modes"] == ["cook"]
    assert me["cook"]["id"] == cook["id"] and me["cook"]["kind"] == "hired"
    assert me["cook"]["login_mode"] == "own" and me["cook"]["on_duty"] is True
    admin_me = (await client.get("/v1/me", headers=k.admin)).json()
    assert admin_me["modes"] == ["family"] and admin_me["cook"] is None
