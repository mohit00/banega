"""CSV import/export for the admin panel, in the same shape as the content/*.seed.json files.

List cells use ``|`` as the separator ("Pyaaz 1|Adrak-lahsun"); ingredient flags are one
column each. Import goes through :mod:`app.services.importer`, so derivation, policy checks
and upserts behave exactly like ``python -m app.cli seed``.
"""

from __future__ import annotations

import csv
import io
from collections.abc import Iterable, Mapping, Sequence
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Ingredient, Recipe
from app.models.catalogue import DEFAULT_INGREDIENT_FLAGS
from app.services.importer import ImportReport, load_ingredients, load_recipes

SEP = "|"
FLAG_COLUMNS = list(DEFAULT_INGREDIENT_FLAGS)

INGREDIENT_COLUMNS = [
    "slug",
    "name_en",
    "name_hi",
    "aliases",
    "category",
    "allergens",
    *FLAG_COLUMNS,
    "scaling_rule",
    "trackable",
    "purchase_unit",
    "pack_size",
    "perishable",
    "is_active",
]

RECIPE_COLUMNS = [
    "slug",
    "name",
    "name_hi",
    "sub",
    "dish_category",
    "cuisine",
    "meal_slots",
    "mins",
    "spice",
    "tags",
    "colour",
    "image_url",
    "video_url",
    "base_servings",
    "vrat_ok",
    "editorial_diet",
    "editorial_jain_safe",
    "status",
    "ingredients_text",
    "steps_en",
    "steps_hi",
]

_TRUE = {"1", "true", "yes", "y", "t"}


def _list(cell: str | None) -> list[str]:
    return [x.strip() for x in (cell or "").split(SEP) if x.strip()]


def _bool(cell: str | None) -> bool:
    return (cell or "").strip().lower() in _TRUE


def _opt(cell: str | None) -> str | None:
    value = (cell or "").strip()
    return value or None


_PLACEHOLDER_HOSTS = ("example.com", "example.org", "example.net")


def _image(cell: str | None) -> str | None:
    """Direct image link, or None for blanks and template placeholders (example.com)."""
    value = _opt(cell)
    if value is None:
        return None
    host = value.split("://", 1)[-1].split("/", 1)[0].lower()
    if any(host == h or host.endswith("." + h) for h in _PLACEHOLDER_HOSTS):
        return None
    return value


def _write(columns: Sequence[str], rows: Iterable[Mapping[str, Any]]) -> str:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=list(columns), lineterminator="\n")
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return buf.getvalue()


def _cell(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, list | tuple):
        return SEP.join(str(v) for v in value)
    return str(value)


def _read(text: str) -> list[dict[str, str]]:
    return list(csv.DictReader(io.StringIO(text.lstrip("﻿"))))


# ---- ingredients ------------------------------------------------------------------------


def ingredient_rows_from_csv(text: str) -> list[dict[str, Any]]:
    rows = []
    for raw in _read(text):
        if not _opt(raw.get("slug")):
            continue
        flags: dict[str, Any] = {k: _bool(raw.get(k)) for k in FLAG_COLUMNS if k != "meat_type"}
        flags["meat_type"] = _opt(raw.get("meat_type")) or "none"
        pack = _opt(raw.get("pack_size"))
        rows.append(
            {
                "slug": raw["slug"].strip(),
                "name_en": (raw.get("name_en") or raw["slug"]).strip(),
                "name_hi": _opt(raw.get("name_hi")),
                "aliases": _list(raw.get("aliases")),
                "category": _opt(raw.get("category")) or "other",
                "allergens": _list(raw.get("allergens")),
                "flags": flags,
                "scaling_rule": _opt(raw.get("scaling_rule")) or "linear",
                "trackable": _bool(raw.get("trackable")),
                "purchase_unit": _opt(raw.get("purchase_unit")),
                "pack_size": float(pack) if pack else None,
                "perishable": _bool(raw.get("perishable")),
                "is_active": raw.get("is_active") is None
                or _opt(raw.get("is_active")) is None
                or _bool(raw.get("is_active")),
            }
        )
    return rows


async def export_ingredients_csv(db: AsyncSession) -> str:
    rows = (await db.execute(select(Ingredient).order_by(Ingredient.slug))).scalars()
    out = []
    for i in rows:
        flags = {**DEFAULT_INGREDIENT_FLAGS, **(i.flags or {})}
        out.append(
            {
                "slug": i.slug,
                "name_en": i.name_en,
                "name_hi": _cell(i.name_hi),
                "aliases": _cell(i.aliases),
                "category": str(i.category),
                "allergens": _cell(i.allergens),
                **{k: _cell(flags[k]) for k in FLAG_COLUMNS},
                "scaling_rule": str(i.scaling_rule),
                "trackable": _cell(i.trackable),
                "purchase_unit": _cell(i.purchase_unit),
                "pack_size": _cell(i.pack_size),
                "perishable": _cell(i.perishable),
                "is_active": _cell(i.is_active),
            }
        )
    return _write(INGREDIENT_COLUMNS, out)


async def import_ingredients_csv(db: AsyncSession, text: str) -> ImportReport:
    report = await load_ingredients(db, ingredient_rows_from_csv(text))
    await db.commit()
    return report


# ---- recipes ----------------------------------------------------------------------------


def recipe_rows_from_csv(text: str) -> list[dict[str, Any]]:
    rows = []
    for raw in _read(text):
        if not _opt(raw.get("slug")):
            continue
        rows.append(
            {
                "slug": raw["slug"].strip(),
                "name": (raw.get("name") or raw["slug"]).strip(),
                "name_hi": _opt(raw.get("name_hi")),
                "sub": _opt(raw.get("sub")),
                "dish_category": _opt(raw.get("dish_category")) or "other",
                "cuisine": _opt(raw.get("cuisine")),
                "meal_slots": _list(raw.get("meal_slots")),
                "mins": int(_opt(raw.get("mins")) or 30),
                "spice": int(_opt(raw.get("spice")) or 2),
                "tags": _list(raw.get("tags")),
                "colour": _opt(raw.get("colour")),
                "image_url": _image(raw.get("image_url")),
                "video_url": _opt(raw.get("video_url")),
                "base_servings": int(_opt(raw.get("base_servings")) or 4),
                "vrat_ok": _bool(raw.get("vrat_ok")),
                "editorial_diet": _opt(raw.get("editorial_diet")),
                "editorial_jain_safe": _bool(raw.get("editorial_jain_safe")),
                "status": _opt(raw.get("status")) or "draft",
                "ingredients_text": _list(raw.get("ingredients_text")),
                "steps_en": _list(raw.get("steps_en")),
                "steps_hi": _list(raw.get("steps_hi")),
            }
        )
    return rows


async def export_recipes_csv(db: AsyncSession) -> str:
    rows = (await db.execute(select(Recipe).order_by(Recipe.slug))).scalars()
    out = []
    for r in rows:
        lines = list(
            dict.fromkeys(ri.display_text or ri.ingredient.name_en for ri in r.ingredients)
        )
        out.append(
            {
                "slug": r.slug,
                "name": r.name,
                "name_hi": _cell(r.name_hi),
                "sub": _cell(r.sub),
                "dish_category": str(r.dish_category),
                "cuisine": _cell(r.cuisine),
                "meal_slots": _cell(r.meal_slots),
                "mins": r.mins,
                "spice": r.spice,
                "tags": _cell(r.tags),
                "colour": _cell(r.colour),
                "image_url": _cell(r.image_url),
                "video_url": _cell(r.video_url),
                "base_servings": r.base_servings,
                "vrat_ok": _cell(r.vrat_ok),
                "editorial_diet": _cell(r.editorial_diet),
                "editorial_jain_safe": _cell(r.editorial_jain_safe),
                "status": str(r.status),
                "ingredients_text": _cell(lines),
                "steps_en": _cell(r.steps_en),
                "steps_hi": _cell(r.steps_hi),
            }
        )
    return _write(RECIPE_COLUMNS, out)


async def import_recipes_csv(db: AsyncSession, text: str) -> ImportReport:
    """Upsert recipes. A row asking for ``published`` with violations lands as ``reviewed``."""
    report = await load_recipes(db, recipe_rows_from_csv(text), publish="none")
    await db.commit()
    return report
