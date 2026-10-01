"""Allergen picklist (F-5.2-03, review H3 / primary #7-#8): validated, normalised, an enum
intersection in the engine; free text ("other") is a warning and never excludes a dish."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import create_engine, text

from app.engine import FitStatus, RecipeView, fit
from app.models import Diet, Member, Recipe, Spice
from app.services import allergens as allergen_svc
from app.services.catalogue import eater_view, recipe_view
from tests.test_migrations import _run_upgrade


def test_normalise_synonyms_and_case() -> None:
    assert allergen_svc.strict(["Peanuts", "tree nut", "Tree-Nuts", "kaju", "DAIRY"]) == [
        "milk",
        "peanut",
        "tree_nut",
    ]
    assert allergen_svc.split(["peanut", "kiwi", "Kiwi "]) == (["peanut"], ["kiwi", "Kiwi"])
    with pytest.raises(ValueError, match="kiwi"):
        allergen_svc.strict(["kiwi"])


def _recipe(allergens: list[str]) -> Recipe:
    return Recipe(
        name="Test",
        slug="test",
        allergens=allergens,
        tags=[],
        meal_slots=["lunch"],
        meat_types=[],
        mins=20,
        spice=2,
        dish_category="sabzi",
        is_veg=True,
        has_egg=False,
        has_nonveg=False,
        jain_safe=True,
        no_onion_garlic=True,
        has_root_veg=False,
        dairy_free=True,
        vrat_ok=False,
        ingredients=[],
    )


def _member(allergens: list[str], other: str | None = None) -> Member:
    return Member(
        name="Papa",
        diet=Diet.veg,
        spice=Spice.medium,
        allergens=allergens,
        allergens_other=other,
        needs=[],
        cuisines=[],
        dislikes=[],
        nonveg_exclusions=[],
        no_dairy=False,
        is_kid=False,
    )


def test_engine_intersects_picklist_values() -> None:
    # Legacy spellings on either side still meet on the enum value.
    f = fit(eater_view(_member(["Peanuts"])), recipe_view(_recipe(["peanut"])))
    assert f.status == FitStatus.no and f.reason_key == "allergen"
    f = fit(eater_view(_member(["peanut"])), recipe_view(_recipe(["Peanut"])))
    assert f.status == FitStatus.no


def test_other_never_excludes() -> None:
    """allergens_other is free text: even "peanut" typed there is a warning, not a No."""
    for other in ("peanut", "kiwi", "sab kuch"):
        f = fit(eater_view(_member([], other)), recipe_view(_recipe(["peanut"])))
        assert f.status != FitStatus.no, other
    # Free text that slipped into the list itself cannot exclude either.
    f = fit(eater_view(_member(["kiwi"])), RecipeView(id="r", allergens=frozenset({"kiwi"})))
    assert f.status != FitStatus.no


async def test_member_api_validates_and_normalises(
    client: AsyncClient, make_household: Any
) -> None:
    h = await make_household()
    r = await client.post(
        "/v1/members",
        json={"name": "Chhotu", "allergens": ["Peanuts", "kaju"], "allergens_other": "kiwi"},
        headers=h,
    )
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["allergens"] == ["peanut", "tree_nut"] and body["allergens_other"] == "kiwi"
    bad = await client.post("/v1/members", json={"name": "X", "allergens": ["kiwi"]}, headers=h)
    assert bad.status_code == 422 and bad.json()["code"] == "validation_error"
    r = await client.patch(f"/v1/members/{body['id']}", json={"allergens_other": None}, headers=h)
    assert r.status_code == 200 and r.json()["allergens_other"] is None


async def test_ingredient_import_rejects_unknown_allergen() -> None:
    from app.core.db import get_sessionmaker
    from app.services.importer import load_ingredients

    rows = [{"slug": "kiwi-fruit", "name_en": "Kiwi", "allergens": ["kiwi"]}]
    async with get_sessionmaker()() as db:
        with pytest.raises(ValueError, match="kiwi-fruit"):
            await load_ingredients(db, rows)
        await db.rollback()
    rows = [{"slug": "til-seeds", "name_en": "Til", "allergens": ["Sesame", "til"]}]
    async with get_sessionmaker()() as db:
        await load_ingredients(db, rows)
        await db.commit()
        from sqlalchemy import select

        from app.models import Ingredient

        ing = (
            await db.execute(select(Ingredient).where(Ingredient.slug == "til-seeds"))
        ).scalar_one()
        assert ing.allergens == ["sesame"]


@pytest.mark.filterwarnings("ignore")
def test_migration_normalises_existing_allergens(tmp_path: Path) -> None:
    db = tmp_path / "allergens.db"
    url = f"sqlite+aiosqlite:///{db.as_posix()}"
    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("upgrade", "0009_constraints"),)))
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.begin() as conn:
        conn.execute(
            text(
                "INSERT INTO households (id, name, timezone, default_servings, enabled_slots, "
                "slot_defaults, cook_can_approve_swaps, members_can_send_to_cook, "
                "show_names_to_cook, eater_defaults, auto_decrement, ratings_enabled, "
                "created_at, updated_at) VALUES ('00000000000000000000000000000009', 'Old', "
                "'Asia/Kolkata', 4, '[]', '{}', 1, 1, 0, '{}', 0, 1, CURRENT_TIMESTAMP, "
                "CURRENT_TIMESTAMP)"
            )
        )
        conn.execute(
            text(
                "INSERT INTO members (id, household_id, name, is_kid, diet, nonveg_exclusions, "
                "no_dairy, spice, needs, cuisines, allergens, dislikes, created_at, updated_at) "
                "VALUES ('0000000000000000000000000000000a', '00000000000000000000000000000009', "
                "'Papa', 0, 'veg', '[]', 0, 'medium', '[]', '[]', '[\"Peanuts\", \"kiwi\"]', "
                "'[]', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
            )
        )
    engine.dispose()
    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("upgrade", "head"),)))
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        row = conn.execute(text("SELECT allergens, allergens_other FROM members")).one()
    engine.dispose()
    assert row[0] == '["peanut"]' and row[1] == "kiwi"
