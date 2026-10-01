"""The recipe master CSV template (content/templates) imports cleanly through the admin path."""

from __future__ import annotations

from pathlib import Path

from sqlalchemy import select

from app.core.db import get_sessionmaker
from app.models import Recipe
from app.services.csv_io import RECIPE_COLUMNS, import_recipes_csv, recipe_rows_from_csv
from app.services.importer import seed_all

TEMPLATE = (
    Path(__file__).resolve().parents[2] / "content" / "templates" / "banega-recipes-master.csv"
)


def test_template_has_every_import_column() -> None:
    header = TEMPLATE.read_text(encoding="utf-8-sig").splitlines()[0].split(",")
    assert header[: len(RECIPE_COLUMNS)] == RECIPE_COLUMNS
    rows = recipe_rows_from_csv(TEMPLATE.read_text(encoding="utf-8-sig"))
    assert len(rows) >= 6
    for r in rows:
        assert r["steps_en"] and len(r["steps_en"]) == len(r["steps_hi"]), r["slug"]
        # The template ships placeholder links (example.com); the import drops those.
        assert r["image_url"] is None, r["slug"]


async def test_template_imports_with_optional_marker_and_no_unmatched() -> None:
    async with get_sessionmaker()() as db:
        await seed_all(db, publish="none")
        await db.commit()
    async with get_sessionmaker()() as db:
        report = await import_recipes_csv(db, TEMPLATE.read_text(encoding="utf-8-sig"))
    assert report.unmatched == {}
    assert report.violations == {}
    async with get_sessionmaker()() as db:
        gatte = (
            await db.execute(select(Recipe).where(Recipe.slug == "gatte-ki-sabzi"))
        ).scalar_one()
        dhaniya = [ri for ri in gatte.ingredients if ri.display_text == "Dhaniya (optional)"]
        assert dhaniya and dhaniya[0].optional and not dhaniya[0].is_main
        assert [ri.ingredient.slug for ri in gatte.ingredients if ri.is_main] == ["besan"]
        assert gatte.jain_safe
        sabudana = (
            await db.execute(select(Recipe).where(Recipe.slug == "sabudana-khichdi"))
        ).scalar_one()
        assert sabudana.vrat_ok and "peanut" in sabudana.allergens
        assert len(sabudana.steps_hi) == 5


def test_placeholder_images_and_category_aliases() -> None:
    from app.services.importer import _dish_category

    text = (
        "slug,name,dish_category,image_url\n"
        "a,A,dry_sabzi,https://images.example.com/banega/recipes/a/cover.jpg\n"
        "b,B,bread,https://cdn.banega.in/recipes/b.jpg\n"
        "c,C,side,\n"
    )
    rows = {r["slug"]: r for r in recipe_rows_from_csv(text)}
    assert rows["a"]["image_url"] is None
    assert rows["b"]["image_url"] == "https://cdn.banega.in/recipes/b.jpg"
    assert rows["c"]["image_url"] is None
    assert _dish_category("dry_sabzi") == "sabzi"
    assert _dish_category("bread") == "roti_paratha"
    assert _dish_category("Side") == "side"
    assert _dish_category("pickle") == "side"
    assert _dish_category("space food") is None


async def test_retire_same_name_drafts_older_copies() -> None:
    from app.models.enums import RecipeStatus
    from app.services.importer import retire_same_name

    async with get_sessionmaker()() as db:
        await seed_all(db, publish="all")
        await db.commit()
    async with get_sessionmaker()() as db:
        await import_recipes_csv(db, TEMPLATE.read_text(encoding="utf-8-sig"))
    async with get_sessionmaker()() as db:
        keep = [r["slug"] for r in recipe_rows_from_csv(TEMPLATE.read_text(encoding="utf-8-sig"))]
        retired = await retire_same_name(db, keep)
        await db.commit()
    # The template's Moong Dal Khichdi / Gatte / Anda Curry / Macher Jhol / Idli Sambar
    # supersede the demo seed's khichdi / gatte / eggcurry / macher / idli.
    assert {"khichdi", "gatte", "eggcurry", "macher", "idli"} <= set(retired)
    async with get_sessionmaker()() as db:
        old = (await db.execute(select(Recipe).where(Recipe.slug == "khichdi"))).scalar_one()
        assert old.status == RecipeStatus.draft
        rajma = (await db.execute(select(Recipe).where(Recipe.slug == "rajma"))).scalar_one()
        assert rajma.status == RecipeStatus.published
