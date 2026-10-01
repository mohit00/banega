"""Admin panel smoke + workflow tests (starlette-admin app from admin/main.py)."""

from __future__ import annotations

import importlib
import os
import sys
from collections.abc import AsyncIterator
from pathlib import Path
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.models import Recipe, RecipeStatus
from app.services.importer import seed_all

ADMIN_DIR = Path(__file__).resolve().parents[2] / "admin"


def _admin_module(tmp_media: Path) -> Any:
    os.environ["ADMIN_PASSWORD"] = "test-admin-password"
    os.environ["MEDIA_DIR"] = str(tmp_media)
    if str(ADMIN_DIR) not in sys.path:
        sys.path.insert(0, str(ADMIN_DIR))
    import catalogue_admin
    import main

    importlib.reload(catalogue_admin)
    return importlib.reload(main)


@pytest.fixture
async def admin(tmp_path: Path) -> AsyncIterator[AsyncClient]:
    async with get_sessionmaker()() as db:
        await seed_all(db, publish="clean", with_demo_household=False)
    module = _admin_module(tmp_path)
    app = module.create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        r = await c.get("/admin/login")
        token = c.cookies.get("starlette_admin_csrftoken")
        r = await c.post(
            "/admin/login",
            data={"username": "admin", "password": "test-admin-password", "csrftoken": token},
            follow_redirects=False,
        )
        assert r.status_code in (302, 303), r.text[:500]
        yield c


def _csrf(c: AsyncClient) -> dict[str, str]:
    return {"X-CSRFToken": c.cookies.get("starlette_admin_csrftoken") or ""}


async def _recipe(slug: str) -> Recipe:
    async with get_sessionmaker()() as db:
        return (await db.execute(select(Recipe).where(Recipe.slug == slug))).scalar_one()


@pytest.mark.parametrize(
    "path",
    [
        "/admin/ingredient/list",
        "/admin/staple/list",
        "/admin/recipe/list",
        "/admin/substitution-rule/list",
        "/admin/app-config/list",
        "/admin/recipe/create",
        "/admin/card-preview",
        "/admin/catalogue-csv",
        "/admin/maharaj-golden",
        "/admin/menu/list",
        "/admin/ticket/list",
        "/admin/cook-duty-log/list",
        "/admin/inbox-item/list",
        "/admin/cook/list",
        "/admin/ticket-board",
        "/admin/stock-item/list",
        "/admin/ration-request/list",
        "/admin/approval/list",
        "/admin/rating/list",
        "/admin/consent/list",
        "/admin/subscription/list",
        "/admin/kitchen-health",
    ],
)
async def test_admin_pages_render(admin: AsyncClient, path: str) -> None:
    r = await admin.get(path)
    assert r.status_code == 200, (path, r.status_code, r.text[:300])


async def test_admin_recipe_list_detail_edit(admin: AsyncClient) -> None:
    cheela = await _recipe("cheela")
    assert (await admin.get("/admin/recipe/list")).status_code == 200
    detail = await admin.get(f"/admin/recipe/detail?pk={cheela.id}")
    assert detail.status_code == 200 and "jain_claim_contradicted" in detail.text
    edit = await admin.get(f"/admin/recipe/edit?pk={cheela.id}")
    assert edit.status_code == 200
    assert "Peeli moong dal 1 cup (bhigi)" in edit.text  # inline ingredient rows


async def test_publish_action_refuses_violations(admin: AsyncClient) -> None:
    cheela = await _recipe("cheela")
    gatte = await _recipe("gatte")
    r = await admin.post(
        "/admin/_api/recipe/action",
        params={"name": "publish", "pks": [str(cheela.id)]},
        headers=_csrf(admin),
    )
    assert r.status_code == 400, r.text
    assert "policy violations" in r.text
    assert (await _recipe("cheela")).status == RecipeStatus.draft

    # gatte is published by the seed: unpublish -> review -> publish round trip.
    for name in ("unpublish", "mark_reviewed", "publish"):
        r = await admin.post(
            "/admin/_api/recipe/action",
            params={"name": name, "pks": [str(gatte.id)]},
            headers=_csrf(admin),
        )
        assert r.status_code == 200, (name, r.text)
    after = await _recipe("gatte")
    assert after.status == RecipeStatus.published and after.version == gatte.version + 1


async def test_card_preview_and_csv_roundtrip(admin: AsyncClient) -> None:
    gatte = await _recipe("gatte")
    page = await admin.get(f"/admin/card-preview?id={gatte.id}")
    assert "Gatte ki Sabzi" in page.text and "40 MIN" in page.text and "Jain-safe" in page.text

    csv_text = (await admin.get("/admin/catalogue-csv/recipes.csv")).text
    assert csv_text.startswith("slug,name,")
    assert "Adrak-lahsun" in csv_text
    ing_csv = (await admin.get("/admin/catalogue-csv/ingredients.csv")).text
    assert "onion,Onion,प्याज़" in ing_csv

    new_recipe = (
        "slug,name,dish_category,cuisine,meal_slots,mins,spice,tags,base_servings,"
        "editorial_diet,editorial_jain_safe,status,ingredients_text,steps_en\n"
        "jeera-aloo,Jeera Aloo,sabzi,North Indian,lunch|dinner,20,2,kid,4,veg,true,published,"
        "Aloo 4|Jeera|Haldi,Aloo ubaalo|Jeera tadka\n"
    )
    r = await admin.post(
        "/admin/catalogue-csv/import/recipes",
        files={"file": ("r.csv", new_recipe.encode(), "text/csv")},
        data={"csrftoken": admin.cookies.get("starlette_admin_csrftoken") or ""},
        follow_redirects=False,
    )
    assert r.status_code == 303, r.text[:300]
    jeera = await _recipe("jeera-aloo")
    # Claimed Jain + published, but aloo is a root vegetable: stored as reviewed.
    assert jeera.status == RecipeStatus.reviewed
    assert jeera.policy_violations[0]["reason"] == "root_veg"


async def test_admin_create_recipe_with_inline_rows_and_photo(
    admin: AsyncClient, tmp_path: Path
) -> None:
    from app.models import Ingredient

    async with get_sessionmaker()() as db:
        ids = {
            i.slug: str(i.id)
            for i in (
                await db.execute(select(Ingredient).where(Ingredient.slug.in_(["potato", "cumin"])))
            ).scalars()
        }
    await admin.get("/admin/recipe/create")
    data: list[tuple[str, str]] = [
        ("csrftoken", admin.cookies.get("starlette_admin_csrftoken") or ""),
        ("slug", "sukhe-aloo"),
        ("name", "Sukhe Aloo"),
        ("dish_category", "sabzi"),
        ("cuisine", "North Indian"),
        ("meal_slots", "lunch"),
        ("mins", "20"),
        ("spice", "2"),
        ("tags", "kid"),
        ("base_servings", "4"),
        ("editorial_diet", "veg"),
        ("editorial_jain_safe", "on"),
        ("inlines.recipe-ingredient.0.ingredient", ids["potato"]),
        ("inlines.recipe-ingredient.0.display_text", "Aloo 4"),
        ("inlines.recipe-ingredient.0.qty", "4"),
        ("inlines.recipe-ingredient.0.unit", "pc"),
        ("inlines.recipe-ingredient.0.is_main", "on"),
        ("inlines.recipe-ingredient.0.sort_order", "0"),
        ("inlines.recipe-ingredient.1.ingredient", ids["cumin"]),
        ("inlines.recipe-ingredient.1.display_text", "Jeera"),
        ("inlines.recipe-ingredient.1.sort_order", "1"),
    ]
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 64
    r = await admin.post(
        "/admin/recipe/create",
        data=dict(data),
        files={"image_upload": ("aloo.png", png, "image/png")},
        follow_redirects=False,
    )
    assert r.status_code in (302, 303), r.text[:2000]
    async with get_sessionmaker()() as db:
        recipe = (await db.execute(select(Recipe).where(Recipe.slug == "sukhe-aloo"))).scalar_one()
        assert {ri.ingredient.slug for ri in recipe.ingredients} == {"potato", "cumin"}
        assert recipe.has_root_veg and not recipe.jain_safe and recipe.no_onion_garlic
        assert recipe.policy_violations[0]["code"] == "jain_claim_contradicted"
        assert recipe.status == RecipeStatus.draft
        assert recipe.image_url is not None and recipe.image_url.startswith("/media/recipes/")
        assert (tmp_path / "recipes" / recipe.image_url.rsplit("/", 1)[1]).read_bytes() == png


async def test_admin_golden_set_download(admin: AsyncClient) -> None:
    page = await admin.get("/admin/maharaj-golden")
    assert "Rule parser accuracy" in page.text and "golden-queries.json" in page.text
    r = await admin.get("/admin/maharaj-golden/golden-queries.json")
    assert r.status_code == 200
    assert "attachment" in r.headers["content-disposition"]
    assert len(r.json()["queries"]) >= 60


async def test_ticket_board_and_ticket_detail(admin: AsyncClient) -> None:
    from app.services.demo import create_demo_day
    from app.services.importer import load_demo_household, load_json

    async with get_sessionmaker()() as db:
        await load_demo_household(db, load_json("demo-household.seed.json"))
        await db.commit()
        demo = await create_demo_day(db)
    assert demo.status == "new"  # Ramesh ji (hired, primary) gets the lunch
    board = await admin.get("/admin/ticket-board")
    assert board.status_code == 200
    assert "Purohit Parivaar" in board.text and "Gatte ki Sabzi" in board.text
    assert "new (1)" in board.text and "Ramesh ji" in board.text
    detail = await admin.get(f"/admin/ticket/detail?pk={demo.ticket_id}")
    assert detail.status_code == 200 and "created" in detail.text
    other_day = await admin.get("/admin/ticket-board?date=2020-01-01")
    assert "0 ticket(s)" in other_day.text


async def test_kitchen_health_and_subscription_status_search(admin: AsyncClient) -> None:
    from app.models import Household, StockItem, StockLevel, Subscription, SubscriptionStatus
    from app.models import Ingredient as Ing

    async with get_sessionmaker()() as db:
        h = Household(name="Health ghar")
        db.add(h)
        await db.flush()
        curd = (await db.execute(select(Ing).where(Ing.slug == "curd"))).scalar_one()
        db.add(StockItem(household_id=h.id, ingredient_id=curd.id, level=StockLevel.out))
        db.add(Subscription(household_id=h.id, status=SubscriptionStatus.grace))
        await db.commit()
    page = await admin.get("/admin/kitchen-health")
    assert page.status_code == 200
    assert "Health ghar" in page.text and "Curd" in page.text and "grace" in page.text
    async with get_sessionmaker()() as db:
        other = Household(name="Trial ghar")
        db.add(other)
        await db.flush()
        db.add(Subscription(household_id=other.id, status=SubscriptionStatus.trial))
        await db.commit()
    r = await admin.get("/admin/subscription/list", params={"q": "grace"})
    assert r.status_code == 200, r.text[:300]
    assert str(h.id) in r.text and str(other.id) not in r.text
