"""In-process snapshot of the published catalogue (review M4).

Recommendations and Maharaj used to load every published recipe (+ ingredients) and build
engine views on every request. The snapshot keeps the loaded recipes and their
:class:`~app.engine.RecipeView` per process and reloads only when the catalogue changed:
the stamp is (max recipe updated_at, published count, max ingredient updated_at). The stamp
itself is re-read at most every CATALOGUE_CACHE_SECONDS (60 s; 0 = on every call), so an
admin edit shows up within a minute.

The cached ORM objects are detached, fully loaded and read-only by convention: callers read
attributes, never modify or ``db.add`` them.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass, field
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.engine import RecipeView
from app.models import Ingredient, Recipe, RecipeIngredient, RecipeStatus
from app.services.catalogue import recipe_view

Stamp = tuple[datetime | None, int, datetime | None]


@dataclass(frozen=True)
class Snapshot:
    stamp: Stamp
    recipes: list[Recipe]
    views: list[RecipeView]
    by_id: dict[str, Recipe] = field(default_factory=dict)
    loaded_at: float = 0.0


_snapshot: Snapshot | None = None
_checked_at: float = 0.0
_lock: asyncio.Lock | None = None


async def _stamp(db: AsyncSession) -> Stamp:
    row = (
        await db.execute(
            select(func.max(Recipe.updated_at), func.count(Recipe.id)).where(
                Recipe.status == RecipeStatus.published
            )
        )
    ).one()
    ing = (await db.execute(select(func.max(Ingredient.updated_at)))).scalar_one_or_none()
    return (row[0], int(row[1] or 0), ing)


async def published(db: AsyncSession) -> Snapshot:
    """The current snapshot (reloaded when the stamp changed)."""
    global _snapshot, _checked_at, _lock
    ttl = get_settings().CATALOGUE_CACHE_SECONDS
    now = time.monotonic()
    if _snapshot is not None and ttl > 0 and now - _checked_at < ttl:
        return _snapshot
    if _lock is None:
        _lock = asyncio.Lock()
    async with _lock:
        stamp = await _stamp(db)
        if _snapshot is not None and _snapshot.stamp == stamp:
            _checked_at = time.monotonic()
            return _snapshot
        # Loaded in a session of its own: the objects come out detached and fully loaded,
        # and the caller's session / identity map is untouched.
        async with get_sessionmaker()() as own:
            recipes = list(
                (
                    await own.execute(
                        select(Recipe)
                        .where(Recipe.status == RecipeStatus.published)
                        .options(
                            selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient)
                        )
                    )
                ).scalars()
            )
            own.expunge_all()
        _snapshot = Snapshot(
            stamp=stamp,
            recipes=recipes,
            views=[recipe_view(r) for r in recipes],
            by_id={str(r.id): r for r in recipes},
            loaded_at=time.monotonic(),
        )
        _checked_at = time.monotonic()
        return _snapshot


def reset() -> None:
    """Tests (a fresh database per test) and admin tooling."""
    global _snapshot, _checked_at, _lock
    _snapshot = None
    _checked_at = 0.0
    _lock = None
