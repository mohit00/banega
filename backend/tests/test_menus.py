"""Day menus (contract §Menus; F-5.6-01 eaters/servings/guests, F-5.7-01 due time)."""

from __future__ import annotations

from datetime import datetime, timedelta
from decimal import Decimal

from httpx import AsyncClient

from app.models import Diet, Member
from app.services import menus as menu_svc
from tests.conftest import Login
from tests.kitchen_fixtures import IST, future_day, make_kitchen


async def test_put_dishes_creates_menu_with_defaults(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    day = future_day()
    menu = await k.menu(["gatte", "daltadka", "gatte"], day=day)
    assert [d["name"] for d in menu["dishes"]] == ["Gatte ki Sabzi", "Dal Tadka & Jeera Rice"]
    assert menu["date"] == day.isoformat() and menu["slot"] == "lunch"
    # Eaters default to all active members; Beta is a kid (0.5).
    assert {e["name"] for e in menu["eaters"]} == {"Papa", "Mummy", "Dadi", "Beta"}
    assert menu["servings"] == 3.5
    # Default due time 13:30 household-local (F-5.7-01).
    due = datetime.fromisoformat(menu["due_at"]).astimezone(IST)
    assert (due.date(), due.hour, due.minute) == (day, 13, 30)
    assert menu["guests"] == {"adults": 0, "kids": 0, "diet": None}
    assert menu["assignee"] is None and menu["ticket_id"] is None
    assert menu["dishes"][0]["summary"]["badge"] in {"fit", "tweak", "no"}
    assert menu["version"] == 2  # created (1) + dishes set (2)

    # Same list again: nothing changes, version stays.
    again = await k.menu(["gatte", "daltadka"], day=day)
    assert again["id"] == menu["id"] and again["version"] == 2

    # GET by date+slot and by date.
    r = await client.get(f"/v1/menus?date={day}&slot=lunch", headers=k.admin)
    assert r.status_code == 200 and r.json()["id"] == menu["id"]
    r = await client.get(f"/v1/menus?date={day}", headers=k.admin)
    assert [m["id"] for m in r.json()] == [menu["id"]]
    r = await client.get(f"/v1/menus?date={day}&slot=dinner", headers=k.admin)
    assert r.status_code == 404


async def test_slot_due_defaults(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    day = future_day()
    expected = {"nashta": (8, 30), "dinner": (20, 30), "tiffin": (7, 30), "shaam": (17, 30)}
    for slot, hm in expected.items():
        m = await k.menu(["poha"], day=day, slot=slot)
        due = datetime.fromisoformat(m["due_at"]).astimezone(IST)
        assert (due.hour, due.minute) == hm, slot
    r = await client.put(f"/v1/menus/{day}/brunch/dishes", json={"recipe_ids": []}, headers=k.admin)
    assert r.status_code == 422 and r.json()["code"] == "invalid_slot"


async def test_unknown_or_unpublished_recipe_is_422(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    r = await client.put(
        f"/v1/menus/{future_day()}/lunch/dishes",
        json={"recipe_ids": ["00000000-0000-0000-0000-000000000001"]},
        headers=k.admin,
    )
    assert r.status_code == 422 and r.json()["code"] == "unknown_recipe"


async def test_patch_eaters_guests_servings_and_remembered_defaults(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    day = future_day()
    menu = await k.menu(["gatte"], day=day)
    r = await client.patch(
        f"/v1/menus/{menu['id']}",
        json={
            "eaters": [k.members["Papa"], k.members["Beta"]],
            "guests": {"adults": 2, "kids": 1, "diet": "veg"},
            "notes": "Kam tel",
        },
        headers=k.admin,
    )
    assert r.status_code == 200, r.text
    m = r.json()
    # Papa 1 + Beta 0.5 + 2 adult guests + 1 kid guest 0.5 = 4.0
    assert m["servings"] == 4.0
    assert m["notes"] == "Kam tel"
    assert [e["name"] for e in m["eaters"]] == ["Papa", "Beta"]

    # Explicit servings override.
    r = await client.patch(f"/v1/menus/{menu['id']}", json={"servings": 6}, headers=k.admin)
    assert r.json()["servings"] == 6.0

    # Remembered per (slot, weekday): the same weekday next week starts with Papa + Beta...
    next_week = await k.menu(["gatte"], day=day + timedelta(days=7))
    assert [e["name"] for e in next_week["eaters"]] == ["Papa", "Beta"]
    # ...another weekday or slot does not.
    other = await k.menu(["gatte"], day=day + timedelta(days=1))
    assert len(other["eaters"]) == 4
    dinner = await k.menu(["bhindi"], day=day, slot="dinner")
    assert len(dinner["eaters"]) == 4

    # Foreign member id -> 404.
    r = await client.patch(
        f"/v1/menus/{menu['id']}",
        json={"eaters": ["00000000-0000-0000-0000-000000000009"]},
        headers=k.admin,
    )
    assert r.status_code == 404


async def test_coverage_names_uncovered_eaters_and_guests(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    menu = await k.menu(["bhindi"])
    # Bhindi is not Jain-safe: Dadi (Jain) is not covered.
    assert menu["coverage"] == {"all_covered": False, "uncovered": ["Dadi"]}
    menu = await k.menu(["bhindi", "gatte"])
    assert menu["coverage"] == {"all_covered": True, "uncovered": []}

    # Guests without a diet take the strictest eater diet (Dadi: Jain).
    r = await client.patch(
        f"/v1/menus/{menu['id']}", json={"guests": {"adults": 1, "kids": 0}}, headers=k.admin
    )
    assert r.json()["coverage"]["all_covered"] is True
    menu = await k.menu(["bhindi"])
    assert menu["coverage"]["uncovered"] == ["Dadi", "Mehmaan"]
    # Without Dadi eating, a veg guest is fine with bhindi.
    r = await client.patch(
        f"/v1/menus/{menu['id']}",
        json={"eaters": [k.members["Papa"], k.members["Mummy"]]},
        headers=k.admin,
    )
    assert r.json()["coverage"] == {"all_covered": True, "uncovered": []}
    # A non-veg guest with only chicken: the veg eaters are uncovered, the guest is not.
    menu = await k.menu(["chicken"], guests={"adults": 1, "kids": 0, "diet": "non_veg"})
    assert menu["coverage"]["uncovered"] == ["Papa", "Mummy"]


async def test_required_items_merged_with_staple_status(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    menu = await k.menu(["gatte", "daltadka"])
    items = menu["required_items"]
    ids = [i["ingredient_id"] for i in items]
    assert len(ids) == len(set(ids)) > 3
    assert {i["status"] for i in items} <= {"in", "untracked"}
    assert any(i["status"] == "in" for i in items)  # seeded staples read "in" in Phase 5


async def test_share_text_is_hinglish_whatsapp_message(client: AsyncClient, login: Login) -> None:
    k = await make_kitchen(client, login)
    cook = await k.add_hired()
    menu = await k.menu(
        ["gatte", "daltadka"],
        guests={"adults": 2, "kids": 0},
        notes="Dadi ke liye alag katori",
        assignee_cook_id=cook["id"],
    )
    r = await client.get(f"/v1/menus/{menu['id']}/share-text", headers=k.admin)
    text = r.json()["text"]
    assert text.startswith("*Lunch - ")
    assert "Ramesh ji, namaste." in text
    assert "Kab tak: 1:30 PM" in text
    assert "1. Gatte ki Sabzi" in text and "2. Dal Tadka & Jeera Rice" in text
    assert "Kaun kha raha hai: Papa, Mummy, Dadi, Beta + 2 mehmaan" in text
    assert "Kitne logon ka: 5.5" in text
    assert "Note: Dadi ke liye alag katori" in text
    assert "*Saaman:*" in text and "\n- " in text


def test_servings_and_strictest_diet_pure() -> None:
    adult = Member(name="A", is_kid=False, diet=Diet.veg)
    kid = Member(name="K", is_kid=True, diet=Diet.eggetarian)
    guests = {"adults": 1, "kids": 3}
    assert menu_svc.compute_servings([adult, kid], guests) == Decimal("4.00")
    assert menu_svc.strictest_diet([Diet.non_veg, Diet.eggetarian]) == Diet.eggetarian
    assert menu_svc.strictest_diet([Diet.veg, Diet.jain]) == Diet.jain
    assert menu_svc.strictest_diet([]) == Diet.veg
    view = menu_svc.guest_view({"adults": 1, "kids": 0, "diet": None}, [adult, kid])
    assert view is not None and view.diet == Diet.veg
    assert menu_svc.guest_view({"adults": 0, "kids": 0}, [adult]) is None


async def test_hired_cook_and_members_permissions_on_menus(
    client: AsyncClient, login: Login
) -> None:
    k = await make_kitchen(client, login)
    member = await k.invite_member()
    # Adult members may add dishes (edit_day_menu).
    menu = await k.menu(["gatte"], headers=member)
    assert menu["dishes"]
    await k.add_hired()
    cook = await k.cook_login()
    r = await client.put(
        f"/v1/menus/{future_day()}/lunch/dishes", json={"recipe_ids": []}, headers=cook
    )
    assert r.status_code == 403
