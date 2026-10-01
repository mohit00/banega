"""Seed importer, scaling and the catalogue / recommendations APIs."""

from __future__ import annotations

from collections import Counter
from collections.abc import Awaitable, Callable
from decimal import Decimal
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import func, select

from app.core.db import get_sessionmaker
from app.core.kv import get_kv
from app.models import (
    AppConfig,
    Household,
    HouseholdMembership,
    Ingredient,
    Member,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
    ScalingRule,
    Staple,
    User,
)
from app.services.catalogue import default_slot, rule_multiplier, scale_factor, scale_qty
from app.services.importer import DEMO_COOK_PHONE, AliasMatcher, PublishMode, load_json, seed_all
from tests.conftest import Headers, Login

MakeHousehold = Callable[..., Awaitable[Headers]]


async def _seed(publish: PublishMode = "clean", demo: bool = True) -> Any:
    async with get_sessionmaker()() as db:
        return await seed_all(db, publish=publish, with_demo_household=demo)


async def _count(model: Any) -> int:
    async with get_sessionmaker()() as db:
        return int((await db.execute(select(func.count()).select_from(model))).scalar_one())


# ---- importer --------------------------------------------------------------------------


def test_ingredient_seed_shape() -> None:
    rows = load_json("ingredients.seed.json")
    assert 140 <= len(rows) <= 800  # "~600-800 at launch" (models/catalogue.py)
    slugs = [r["slug"] for r in rows]
    assert len(slugs) == len(set(slugs))
    aliases = Counter(a for r in rows for a in r["aliases"])
    assert [a for a, n in aliases.items() if n > 1] == []
    for r in rows:
        assert r["name_hi"] and any("ऀ" <= ch <= "ॿ" for ch in r["name_hi"]), r["slug"]
        assert set(r["flags"]) >= {"root_veg", "onion_garlic", "meat_type", "egg", "dairy"}
        assert set(r["allergens"]) <= {
            "peanut", "tree_nut", "milk", "gluten", "sesame", "soy", "egg", "fish",
            "shellfish", "mustard",
        }  # fmt: skip


def test_every_seed_line_maps_to_an_ingredient() -> None:
    ings = load_json("ingredients.seed.json")
    m = AliasMatcher((i["slug"], i["name_en"], i["aliases"]) for i in ings)
    unmatched = [
        (r["id"], line)
        for r in load_json("recipes.seed.json")
        for line in r["ingredients_text"]
        if not m.match(line)
    ]
    assert unmatched == []


def test_alias_matcher_longest_match_and_qty() -> None:
    m = AliasMatcher(
        [
            ("coriander-leaves", "Coriander leaves", ["dhaniya"]),
            ("coriander-powder", "Coriander powder", ["dhaniya powder"]),
            ("ginger", "Ginger", ["adrak"]),
            ("garlic", "Garlic", ["lahsun"]),
            ("chana-dal", "Chana dal", ["chana dal"]),
        ]
    )
    assert m.match("Dhaniya powder") == ["coriander-powder"]
    assert m.match("Dhaniya") == ["coriander-leaves"]
    assert m.match("Adrak-lahsun") == ["ginger", "garlic"]
    line = m.parse_line("Chana dal 1/2 cup")
    assert line.qty == Decimal("0.5") and line.unit == "cup"
    assert m.parse_line("Adrak-lahsun 2 tsp").qty is None  # multi-ingredient line


async def test_seed_is_idempotent_and_records_violations() -> None:
    first = await _seed()
    assert first.ingredients.created == await _count(Ingredient)
    assert first.recipes.created == 22
    assert first.recipes.unmatched == {}
    assert set(first.recipes.violations) == {"cheela", "lauki", "curdrice", "pbm"}
    assert len(first.recipes.published) == 18
    counts = [await _count(m) for m in (Ingredient, Staple, Recipe, RecipeIngredient, AppConfig)]
    second = await _seed()
    assert second.recipes.created == 0 and second.recipes.updated == 22
    assert [await _count(m) for m in (Ingredient, Staple, Recipe, RecipeIngredient,
                                      AppConfig)] == counts  # fmt: skip
    assert await _count(Household) == 1
    assert await _count(Member) == 5

    async with get_sessionmaker()() as db:
        cheela = (await db.execute(select(Recipe).where(Recipe.slug == "cheela"))).scalar_one()
        assert cheela.editorial_jain_safe and not cheela.jain_safe
        assert cheela.status == RecipeStatus.draft
        assert cheela.policy_violations[0]["reason"] == "root_veg"
        assert cheela.policy_violations[0]["ingredients"] == ["ginger"]
        assert cheela.version == 2
        gatte = (await db.execute(select(Recipe).where(Recipe.slug == "gatte"))).scalar_one()
        assert gatte.jain_safe and gatte.status == RecipeStatus.published
        main = [ri for ri in gatte.ingredients if ri.is_main]
        assert [ri.ingredient.slug for ri in main] == ["besan"]
        assert main[0].qty == Decimal("1") and main[0].unit == "cup"
        assert main[0].display_text == "Besan 1 cup"
        rajma = (await db.execute(select(Recipe).where(Recipe.slug == "rajma"))).scalar_one()
        assert not rajma.no_onion_garlic and rajma.is_veg
        rows = [ri for ri in rajma.ingredients if ri.display_text == "Adrak-lahsun"]
        assert {ri.ingredient.slug for ri in rows} == {"ginger", "garlic"}
        assert len({ri.sort_order for ri in rows}) == 1
        chicken = (await db.execute(select(Recipe).where(Recipe.slug == "chicken"))).scalar_one()
        assert chicken.has_nonveg and chicken.meat_types == ["chicken"]


async def test_seed_publish_modes() -> None:
    assert (await _seed(publish="none", demo=False)).recipes.published == []
    assert len((await _seed(publish="all", demo=False)).recipes.published) == 22


async def test_demo_household_admin() -> None:
    await _seed()
    async with get_sessionmaker()() as db:
        user = (await db.execute(select(User).where(User.phone == "+919999999999"))).scalar_one()
        ms = (
            await db.execute(
                select(HouseholdMembership).where(HouseholdMembership.user_id == user.id)
            )
        ).scalar_one()
        hh = await db.get(Household, ms.household_id)
        assert hh is not None and hh.name == "Purohit Parivaar"
        assert ms.is_admin and ms.member_id is not None
        dadi = (await db.execute(select(Member).where(Member.name == "Dadi"))).scalar_one()
        assert dadi.diet == "jain" and dadi.spice == "kam"


# ---- scaling (F-5.5-05) ------------------------------------------------------------------


def test_scaling_rules() -> None:
    assert rule_multiplier(ScalingRule.linear, 2) == 2
    assert rule_multiplier(ScalingRule.sublinear, 2) == pytest.approx(1.5)
    assert rule_multiplier(ScalingRule.sublinear, 4) == pytest.approx(2.25)
    assert rule_multiplier(ScalingRule.sublinear, 0.5) == pytest.approx(1 / 1.5)
    assert rule_multiplier(ScalingRule.fixed, 3) == 1
    # base-4 dal to 8: 1.5x salt, same tadka
    assert scale_qty(Decimal("1"), "tsp", ScalingRule.sublinear, 2) == Decimal("1.5")
    assert scale_qty(Decimal("1"), "tsp", ScalingRule.fixed, 2) == Decimal("1")
    assert scale_qty(Decimal("300"), "g", ScalingRule.linear, 1.25) == Decimal("375")
    assert scale_qty(Decimal("2"), "cup", ScalingRule.linear, 1.25) == Decimal("2.5")
    assert scale_qty(Decimal("3"), "pc", ScalingRule.linear, 0.25) == Decimal("1")
    assert scale_qty(None, None, ScalingRule.linear, 2) is None
    assert scale_factor(13, 4).batch_suggested and not scale_factor(12, 4).batch_suggested


def test_default_slot() -> None:
    from datetime import datetime

    def at(h: int, m: int = 0) -> datetime:
        return datetime(2026, 10, 5, h, m)

    assert default_slot(at(8)) == "nashta"
    assert default_slot(at(11)) == "lunch"
    assert default_slot(at(17)) == "dinner"
    assert default_slot(at(17), ["nashta", "lunch", "shaam", "dinner"]) == "shaam"
    assert default_slot(at(0, 30)) == "dinner"


# ---- APIs --------------------------------------------------------------------------------


async def _demo_headers(login: Login) -> Headers:
    return await login("+919999999999")


async def test_recipes_list_and_detail(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await _demo_headers(login)
    r = await client.get("/v1/recipes?limit=100", headers=h)
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert len(items) == 18  # published only
    assert "cheela" not in {i["slug"] for i in items}
    rajma = next(i for i in items if i["slug"] == "rajma")
    assert rajma["summary"]["label_key"] == "some"
    assert rajma["summary"]["label_params"] == {"can": 4, "n": 5}
    assert rajma["mark"] == "veg" and rajma["flags"]["no_onion_garlic"] is False

    lunch = (await client.get("/v1/recipes?slot=lunch&limit=100", headers=h)).json()["items"]
    assert all("lunch" in i["meal_slots"] for i in lunch)
    q = (await client.get("/v1/recipes?q=paneer", headers=h)).json()["items"]
    assert [i["slug"] for i in q] == ["palak"]  # pbm is unpublished (policy violation)

    page1 = (await client.get("/v1/recipes?limit=5", headers=h)).json()
    assert len(page1["items"]) == 5 and page1["next_cursor"]
    seen = [i["slug"] for i in page1["items"]]
    cursor = page1["next_cursor"]
    while cursor:
        page = (await client.get(f"/v1/recipes?limit=5&cursor={cursor}", headers=h)).json()
        seen += [i["slug"] for i in page["items"]]
        cursor = page["next_cursor"]
    assert sorted(seen) == sorted(i["slug"] for i in items)

    rid = rajma["id"]
    d = (await client.get(f"/v1/recipes/{rid}", headers=h)).json()
    assert d["servings"] == 5 and d["base_servings"] == 4
    assert d["scale_factor"] == 1.25 and d["batch_suggested"] is False
    dadi = next(f for f in d["fits"] if f["name"] == "Dadi")
    assert dadi["status"] == "no" and dadi["reason_key"] == "onion_garlic"
    main = next(i for i in d["ingredients"] if i["is_main"])
    assert main["slug"] == "rajma" and main["scaled_qty"] == 1.25  # JSON number
    assert d["allergy_notice"] is False

    d8 = (await client.get(f"/v1/recipes/{rid}?servings=8", headers=h)).json()
    assert next(i for i in d8["ingredients"] if i["is_main"])["scaled_qty"] == 2
    big = (await client.get(f"/v1/recipes/{rid}?servings=13", headers=h)).json()
    assert big["batch_suggested"] is True
    assert all(i["scaled_qty"] is None for i in big["ingredients"])


async def test_recipe_detail_eaters_and_404(
    client: AsyncClient, login: Login, make_household: MakeHousehold
) -> None:
    await _seed()
    h = await _demo_headers(login)
    members = (await client.get("/v1/members", headers=h)).json()["items"]
    dadi = next(m for m in members if m["name"] == "Dadi")
    rajma = next(i for i in (await client.get("/v1/recipes?q=rajma", headers=h)).json()["items"])
    papa = next(m for m in members if m["name"] == "Papa")
    d = (await client.get(f"/v1/recipes/{rajma['id']}?eaters={papa['id']}", headers=h)).json()
    assert [f["name"] for f in d["fits"]] == ["Papa"]
    assert d["summary"]["badge"] == "tweak"

    other = await make_household("+919800000055", "Other")
    r = await client.get(f"/v1/recipes/{rajma['id']}?eaters={dadi['id']}", headers=other)
    assert r.status_code == 404
    assert (
        await client.get("/v1/recipes/00000000-0000-0000-0000-000000000000", headers=h)
    ).status_code == 404
    bad = await client.get(f"/v1/recipes/{rajma['id']}?eaters=nope", headers=h)
    assert bad.status_code == 400


async def test_recipes_need_household(client: AsyncClient, login: Login) -> None:
    h = await login("+919800000077")
    assert (await client.get("/v1/recipes", headers=h)).status_code == 404
    assert (await client.get("/v1/recipes")).status_code == 401


async def test_recommendations(client: AsyncClient, login: Login) -> None:
    await _seed(publish="all")
    h = await _demo_headers(login)
    r = await client.get("/v1/recommendations?slot=lunch&date=2026-10-05", headers=h)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["slot"] == "lunch" and body["cached"] is False
    assert len(body["tiles"]) == 8
    pick = body["pick"]["recipe"]
    assert pick["slug"] not in {t["recipe"]["slug"] for t in body["tiles"]}
    cats = Counter(t["recipe"]["dish_category"] for t in body["tiles"])
    assert max(cats.values()) <= 2
    scores = [body["pick"]["score"]] + [t["score"] for t in body["tiles"]]
    assert scores[0] >= max(scores[1:])
    assert body["constraint_line"]["items"][0]["key"] == "jain"

    again = (await client.get("/v1/recommendations?slot=lunch&date=2026-10-05", headers=h)).json()
    assert again["cached"] is True
    assert again["pick"] == body["pick"] and again["tiles"] == body["tiles"]

    # A profile edit changes the cache key.
    members = (await client.get("/v1/members", headers=h)).json()["items"]
    dadi = next(m for m in members if m["name"] == "Dadi")
    await client.patch(f"/v1/members/{dadi['id']}", json={"diet": "veg"}, headers=h)
    fresh = (await client.get("/v1/recommendations?slot=lunch&date=2026-10-05", headers=h)).json()
    assert fresh["cached"] is False

    only = (
        await client.get(f"/v1/recommendations?slot=dinner&eaters={dadi['id']}", headers=h)
    ).json()
    assert only["eater_ids"] == [dadi["id"]]
    assert only["pick"]["recipe"]["summary"]["n"] == 1


async def test_recommendations_bad_slot_and_default(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await _demo_headers(login)
    assert (await client.get("/v1/recommendations?slot=brunch", headers=h)).status_code == 422
    r = await client.get("/v1/recommendations", headers=h)
    assert r.status_code == 200 and r.json()["slot"] in {"nashta", "lunch", "dinner"}


async def test_recommendations_cache_uses_kv(client: AsyncClient, login: Login) -> None:
    await _seed()
    h = await _demo_headers(login)
    await client.get("/v1/recommendations?slot=dinner&date=2026-10-05", headers=h)
    kv = get_kv()
    keys = [k for k in getattr(kv, "_data", {}) if k.startswith("reco:")]
    assert len(keys) == 1
    assert await kv.ttl(keys[0]) <= 60


async def test_ingredients_staples_config(client: AsyncClient, login: Login) -> None:
    await _seed(demo=False)
    h = await login("+919800000088")
    r = (await client.get("/v1/ingredients?q=pyaaz", headers=h)).json()
    assert [i["slug"] for i in r["items"]] == ["onion", "shallot", "spring-onion"]
    assert r["items"][0]["flags"]["onion_garlic"] is True
    hindi = (await client.get("/v1/ingredients?q=अदरक", headers=h)).json()["items"]
    assert [i["slug"] for i in hindi] == ["ginger"]
    page = (await client.get("/v1/ingredients?limit=20", headers=h)).json()
    assert len(page["items"]) == 20 and page["next_cursor"]
    nxt = (
        await client.get(f"/v1/ingredients?limit=20&cursor={page['next_cursor']}", headers=h)
    ).json()
    assert not {i["slug"] for i in nxt["items"]} & {i["slug"] for i in page["items"]}

    staples = (await client.get("/v1/staples", headers=h)).json()["items"]
    assert len(staples) == await _count(Staple) and staples[0]["ingredient"]["trackable"]
    assert [s["sort_order"] for s in staples] == sorted(s["sort_order"] for s in staples)

    cfg = (await client.get("/v1/config", headers=h)).json()
    assert cfg["quick_asks"][0] == "15 min mein kuch"
    assert set(cfg) >= {"quick_asks", "follow_ups", "ticker_asks", "cuisines", "needs", "slots"}
    assert (await client.get("/v1/config")).status_code == 401


async def test_hired_cook_cannot_get_recommendations(client: AsyncClient, login: Login) -> None:
    await _seed()
    await _demo_headers(login)
    # The seeded hired cook (Ramesh ji) gets cook mode on first OTP login (FR-K1).
    cook = await login(DEMO_COOK_PHONE)
    assert (await client.get("/v1/me", headers=cook)).json()["modes"] == ["cook"]
    assert (await client.get("/v1/recommendations", headers=cook)).status_code == 403
    # Cook mode (Phase 5): recipes open only through a ticket
    # (/v1/tickets/{id}/recipes/{recipe_id}); the catalogue itself is 403.
    assert (await client.get("/v1/recipes", headers=cook)).status_code == 403


async def test_ingredient_flag_change_pulls_published_recipes() -> None:
    from app.services import publishing

    await _seed(demo=False)
    async with get_sessionmaker()() as db:
        hing = (
            await db.execute(select(Ingredient).where(Ingredient.slug == "asafoetida"))
        ).scalar_one()
        hing.flags = {**hing.flags, "fermented": True}
        await db.flush()
        pulled = await publishing.recompute_for_ingredient(db, hing.id)
        await db.commit()
    assert "gatte" in pulled and "khichdi" in pulled
    async with get_sessionmaker()() as db:
        gatte = (await db.execute(select(Recipe).where(Recipe.slug == "gatte"))).scalar_one()
        assert gatte.status == RecipeStatus.reviewed and not gatte.jain_safe


def test_publish_workflow_rules() -> None:
    from app.services import publishing

    r = Recipe(slug="x", name="X", status=RecipeStatus.draft, editorial_jain_safe=False)
    r.ingredients = []
    with pytest.raises(publishing.PublishError, match="no_ingredients"):
        publishing.publish(r)
