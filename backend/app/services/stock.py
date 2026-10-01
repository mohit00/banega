"""Pantry stock (FRD §5.8 FR-S1..S4 as amended by F-5.8-01/02 and F-5.6-04).

- Tracked items are the global ``Staple`` rows (``Ingredient.trackable``). A household reads
  every staple; a staple with no ``StockItem`` row is ``in``. ``GET /v1/stock`` materialises
  the missing rows so later writes are plain updates.
- Untracked ingredients are never marked missing (F-5.8-01): ``required_items`` shows them
  as ``untracked``.
- A change to ``low`` or ``out`` emits ``stock_low`` to the admin (one event per call).
- Auto-decrement (FR-S4 Should, ``Household.auto_decrement``): on Completed, perishable
  tracked items the dishes used drop ``in -> low`` once (never to ``out``: F-5.8-02 says no
  level changes without a qty calculation or a human tap, and "low" is the prompt).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.errors import AppError, NotFound
from app.models import (
    Household,
    Ingredient,
    Staple,
    StockItem,
    StockLevel,
    Ticket,
)
from app.models.base import utcnow
from app.services import notifications as notify
from app.services.refs import ref, user_names

LEVEL_ORDER: dict[str, int] = {"in": 0, "low": 1, "out": 2}

# Pantry groups the app shows (FR-S1 "grouped by category"), from Ingredient.category.
PANTRY_GROUPS: dict[str, str] = {
    "vegetable": "sabzi",
    "fruit": "sabzi",
    "herb": "sabzi",
    "dairy": "dairy",
    "egg": "dairy",
    "pulse": "dal",
    "grain": "anaaj",
    "spice": "masale",
    "oil_fat": "tel_ghee",
    "nut_seed": "dry_fruits",
}


def pantry_group(category: str) -> str:
    return PANTRY_GROUPS.get(category, "other")


def _not_tracked(ingredient_id: uuid.UUID) -> AppError:
    return AppError(
        "not_tracked",
        "This item is not tracked in the pantry.",
        "Ye saaman stock mein track nahi hota.",
        status_code=422,
        details={"ingredient_id": str(ingredient_id)},
    )


async def staples(db: AsyncSession) -> list[Staple]:
    stmt = (
        select(Staple)
        .join(Ingredient, Ingredient.id == Staple.ingredient_id)
        .where(Ingredient.is_active.is_(True))
        .order_by(Staple.sort_order, Ingredient.name_en)
    )
    return list((await db.execute(stmt)).unique().scalars())


async def staple_ids(db: AsyncSession) -> frozenset[uuid.UUID]:
    rows = await db.execute(select(Staple.ingredient_id))
    return frozenset(rows.scalars())


async def household_rows(db: AsyncSession, household_id: uuid.UUID) -> dict[uuid.UUID, StockItem]:
    rows = await db.execute(select(StockItem).where(StockItem.household_id == household_id))
    return {r.ingredient_id: r for r in rows.scalars()}


# ---- the StockLookup used by menus / tickets (F-5.6-04: read at render time) ---------------


@dataclass(frozen=True, slots=True)
class PantryStock:
    """``status(ingredient_id)`` -> in | low | out | untracked."""

    tracked: frozenset[uuid.UUID]
    levels: Mapping[uuid.UUID, str]

    def status(self, ingredient_id: uuid.UUID) -> str:
        if ingredient_id not in self.tracked:
            return "untracked"
        return self.levels.get(ingredient_id, "in")

    def out_ids(self) -> frozenset[uuid.UUID]:
        return frozenset(i for i, lvl in self.levels.items() if lvl == "out")

    def usable(self, ingredient_id: uuid.UUID) -> bool:
        """In or low stock, or untracked (assumed available, F-5.9-06)."""
        return self.status(ingredient_id) != "out"


async def pantry(db: AsyncSession, household_id: uuid.UUID) -> PantryStock:
    tracked = await staple_ids(db)
    rows = await household_rows(db, household_id)
    return PantryStock(
        tracked=tracked,
        levels={i: str(r.level) for i, r in rows.items() if i in tracked},
    )


# ---- reads -----------------------------------------------------------------------------------


def item_view(
    staple: Staple, row: StockItem | None, names: dict[uuid.UUID, str] | None = None
) -> dict[str, Any]:
    ing = staple.ingredient
    return {
        "ingredient_id": ing.id,
        "name": ing.name_en,
        "name_hi": ing.name_hi,
        "category": pantry_group(str(ing.category)),
        "ingredient_category": str(ing.category),
        "level": str(row.level) if row is not None else "in",
        "qty": float(row.qty) if row is not None and row.qty is not None else None,
        "unit": (row.unit if row is not None else None) or ing.purchase_unit,
        "low_threshold": float(staple.low_threshold) if staple.low_threshold is not None else None,
        "perishable": ing.perishable,
        "updated_at": row.updated_at if row is not None else None,
        "updated_by": ref(row.updated_by, names or {}) if row is not None else None,
    }


async def list_stock(
    db: AsyncSession, household: Household, *, materialise: bool = True
) -> list[dict[str, Any]]:
    """Every tracked staple with its level. First read creates the rows (default ``in``)."""
    items = await staples(db)
    rows = await household_rows(db, household.id)
    if materialise:
        missing = [s for s in items if s.ingredient_id not in rows]
        for s in missing:
            row = StockItem(household_id=household.id, ingredient_id=s.ingredient_id)
            row.level = StockLevel.in_
            db.add(row)
            rows[s.ingredient_id] = row
        if missing:
            await db.flush()
    names = await user_names(db, (r.updated_by for r in rows.values()))
    return [item_view(s, rows.get(s.ingredient_id), names) for s in items]


# ---- writes ----------------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class LevelChange:
    ingredient: Ingredient
    before: str
    after: str


async def _staple(db: AsyncSession, ingredient_id: uuid.UUID) -> Staple:
    staple = (
        await db.execute(select(Staple).where(Staple.ingredient_id == ingredient_id))
    ).scalar_one_or_none()
    if staple is None:
        if await db.get(Ingredient, ingredient_id) is None:
            raise NotFound("ingredient_not_found")
        raise _not_tracked(ingredient_id)
    return staple


async def set_level(
    db: AsyncSession,
    household: Household,
    ingredient_id: uuid.UUID,
    level: StockLevel | str,
    *,
    by: uuid.UUID | None,
    qty: Decimal | float | None = None,
    unit: str | None = None,
    qty_given: bool = False,
    now: datetime | None = None,
) -> tuple[StockItem, LevelChange]:
    """Upsert one level. ``qty_given`` distinguishes "qty omitted" from "qty cleared"."""
    now = now or utcnow()
    staple = await _staple(db, ingredient_id)
    row = (
        await db.execute(
            select(StockItem).where(
                StockItem.household_id == household.id, StockItem.ingredient_id == ingredient_id
            )
        )
    ).scalar_one_or_none()
    before = str(row.level) if row is not None else "in"
    if row is None:
        row = StockItem(household_id=household.id, ingredient_id=ingredient_id)
        db.add(row)
    row.level = StockLevel(str(level))
    if qty_given:
        row.qty = Decimal(str(qty)) if qty is not None else None
    if unit is not None:
        row.unit = unit
    row.updated_by = by
    row.updated_at = now
    await db.flush()
    return row, LevelChange(staple.ingredient, before, str(row.level))


async def notify_low(
    db: AsyncSession,
    household: Household,
    changes: Sequence[LevelChange],
    *,
    actor_user_id: uuid.UUID | None,
    now: datetime | None = None,
) -> None:
    """One ``stock_low`` for every item that just became low or out."""
    worse = [
        c
        for c in changes
        if c.after in ("low", "out") and LEVEL_ORDER[c.after] > LEVEL_ORDER[c.before]
    ]
    if not worse:
        return
    names = ", ".join(c.ingredient.name_en for c in worse)
    levels = ", ".join(sorted({"khatam" if c.after == "out" else "kam" for c in worse}))
    await notify.emit(
        db,
        "stock_low",
        household,
        actor_user_id=actor_user_id,
        params={"item": names, "level": levels},
        now=now,
    )


async def update_levels(
    db: AsyncSession,
    household: Household,
    items: Iterable[Mapping[str, Any]],
    *,
    by: uuid.UUID | None,
    now: datetime | None = None,
    notify_changes: bool = True,
) -> list[LevelChange]:
    now = now or utcnow()
    changes: list[LevelChange] = []
    for it in items:
        _, change = await set_level(
            db,
            household,
            it["ingredient_id"],
            it["level"],
            by=by,
            qty=it.get("qty"),
            unit=it.get("unit"),
            qty_given="qty" in it,
            now=now,
        )
        changes.append(change)
    if notify_changes:
        await notify_low(db, household, changes, actor_user_id=by, now=now)
    return changes


async def stock_item(
    db: AsyncSession, household: Household, ingredient_id: uuid.UUID
) -> dict[str, Any]:
    staple = await _staple(db, ingredient_id)
    row = (
        await db.execute(
            select(StockItem).where(
                StockItem.household_id == household.id, StockItem.ingredient_id == ingredient_id
            )
        )
    ).scalar_one_or_none()
    names = await user_names(db, [row.updated_by if row is not None else None])
    return item_view(staple, row, names)


# ---- auto-decrement on Completed (FR-S4 Should) ---------------------------------------------


async def auto_decrement(
    db: AsyncSession,
    household: Household,
    ticket: Ticket,
    ingredient_ids: Iterable[uuid.UUID],
    *,
    now: datetime | None = None,
) -> list[LevelChange]:
    """Perishable tracked items used by the ticket go in -> low, once per ticket."""
    if not household.auto_decrement:
        return []
    now = now or utcnow()
    ids = list(dict.fromkeys(ingredient_ids))
    if not ids:
        return []
    tracked = await staple_ids(db)
    perishable = set(
        (
            await db.execute(
                select(Ingredient.id).where(Ingredient.id.in_(ids), Ingredient.perishable)
            )
        ).scalars()
    )
    rows = await household_rows(db, household.id)
    changes: list[LevelChange] = []
    for i in ids:
        if i not in tracked or i not in perishable:
            continue
        row = rows.get(i)
        if row is not None and row.level != StockLevel.in_:
            continue
        _, change = await set_level(db, household, i, StockLevel.low, by=None, now=now)
        changes.append(change)
    return changes
