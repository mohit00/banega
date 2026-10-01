"""Retrieve + rank: ParsedQuery -> up to 4 ranked recipes, with soft-filter relaxation.

Hard filters (never dropped, F-7-01 / F-5.4-04):
- a recipe that is No for any eater because of an allergen,
- a recipe that is No for the ``member_focus`` member,
- explicit exclusions ("paneer nahi", "bina pyaaz"), a stated diet (Jain, veg ...),
- an explicitly named slot.

Soft filters, dropped in this order while fewer than ``min_results`` recipes match:
ingredients asked for -> cuisine -> tags (incl. spice) -> max_mins (+15 min, then removed).
Exact matches always stay first; relaxed extras ("closest options") follow them.

Slot, as in the prototype's reply(): an implicit slot (the screen's current slot) narrows the
exact matches only when at least two of them are in that slot; relaxed extras always come
from the slot.

Retrieval is keyword + filter based. ``embed()`` is the hook for pgvector similarity
(Recipe.embedding exists since migration 0002); it is a no-op until an embedding provider is
configured, and ranking never depends on it.
"""

from __future__ import annotations

import time
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field

from app.core.config import get_settings
from app.engine import EaterView, FitStatus, Ranked, RecipeView, ScoreContext, rank, summarize
from app.services.maharaj.parse import INGREDIENT_BY_KEY
from app.services.maharaj.types import ParsedQuery

SOFT_STEPS: tuple[str, ...] = ("ingredients", "cuisine", "tags", "max_mins+15", "max_mins")


@dataclass(slots=True)
class Retrieval:
    items: list[Ranked]
    slot: str
    exact_count: int
    dropped: list[str] = field(default_factory=list)  # fragment groups relaxed
    n_eaters: int = 0
    retrieve_ms: float = 0.0
    rank_ms: float = 0.0

    @property
    def all_ok(self) -> int:
        """How many shown recipes the whole family can eat (the prototype's allOk)."""
        return sum(1 for r in self.items if r.summary.can == r.summary.n and r.summary.n > 0)

    @property
    def no_match(self) -> bool:
        return self.exact_count == 0


def embed(text: str) -> list[float] | None:
    """Query embedding for pgvector retrieval. No-op (None) unless VOYAGE_API_KEY and
    EMBEDDING_MODEL are set; wiring the provider is a TODO for when the catalogue outgrows
    keyword retrieval (FR-C2)."""
    s = get_settings()
    if not (s.VOYAGE_API_KEY and s.EMBEDDING_MODEL):
        return None
    return None  # TODO(phase-4b): call the embedding provider and order by cosine distance.


def _refs(r: RecipeView) -> frozenset[str]:
    return r.main_ingredients | r.other_ingredients


def _has_group(r: RecipeView, key: str) -> bool:
    group = INGREDIENT_BY_KEY.get(key)
    if group is None:
        return False
    if key == "maida" and "maida" in r.tags:
        return True
    return bool(_refs(r) & group.slugs)


def _diet_ok(r: RecipeView, diet: str | None) -> bool:
    if diet in ("veg", "jain", "no_onion_garlic") and (r.has_nonveg or r.has_egg):
        return False
    if diet == "eggetarian" and r.has_nonveg:
        return False
    if diet == "jain" and not r.jain_safe:
        return False
    return not (diet == "no_onion_garlic" and r.has_onion_garlic)


def _spice_ok(r: RecipeView, spice: str | None) -> bool:
    if spice == "teekha":
        return r.spice >= 3
    if spice == "kam":
        return r.spice <= 1
    return True


def _soft_ok(r: RecipeView, q: ParsedQuery, active: set[str], max_mins: int | None) -> bool:
    if "ingredients" in active and not all(_has_group(r, k) for k in q.ingredients_include):
        return False
    if "cuisine" in active and q.cuisines and r.cuisine not in q.cuisines:
        return False
    if "tags" in active and (not all(t in r.tags for t in q.tags) or not _spice_ok(r, q.spice)):
        return False
    return not (max_mins is not None and r.mins > max_mins)


def _order(
    pool: Sequence[RecipeView],
    eaters: Sequence[EaterView],
    ctx: ScoreContext,
    tiebreak: Mapping[str, str] | None = None,
) -> list[Ranked]:
    """Engine ranking (F-6-05 score; ties: minutes, then ``tiebreak[id]`` - the slug, so the
    order does not depend on random UUIDs - then id) without the grid's variety rule."""
    if not pool:
        return []
    ranking = rank(pool, eaters, ctx, None, grid_size=len(pool), max_per_category=len(pool))
    assert ranking.pick is not None
    items = [ranking.pick, *ranking.tiles]
    tb = tiebreak or {}
    items.sort(key=lambda x: (-x.score, x.recipe.mins, tb.get(x.recipe.id, x.recipe.id)))
    return items


def retrieve(
    recipes: Sequence[RecipeView],
    eaters: Sequence[EaterView],
    q: ParsedQuery,
    *,
    ctx: ScoreContext | None = None,
    min_results: int = 3,
    limit: int = 4,
    tiebreak: Mapping[str, str] | None = None,
) -> Retrieval:
    t0 = time.perf_counter()
    ctx = ctx or ScoreContext()
    slot = q.slot
    focus = next((e for e in eaters if e.name == q.member_focus), None) if q.member_focus else None
    guest_diet = q.guests.diet if q.guests and q.guests.diet != "non_veg" else None

    hard: list[RecipeView] = []
    for r in recipes:
        if q.explicit_slot and slot not in r.meal_slots:
            continue
        if any(_has_group(r, k) for k in q.ingredients_exclude):
            continue
        if not _diet_ok(r, q.diet) or not _diet_ok(r, guest_diet):
            continue
        s = summarize(eaters, r)
        if any(f.fit.status == FitStatus.no and f.fit.reason_key == "allergen" for f in s.fits):
            continue  # F-5.4-04: never shown, not even as a "closest option"
        if focus is not None and any(
            f.eater_id == focus.id and f.fit.status == FitStatus.no for f in s.fits
        ):
            continue
        hard.append(r)

    active = {"ingredients", "cuisine", "tags"}
    max_mins = q.max_mins
    exact = [r for r in hard if _soft_ok(r, q, active, max_mins)]
    if not q.explicit_slot:
        in_slot = [r for r in exact if slot in r.meal_slots]
        if len(in_slot) >= 2:
            exact = in_slot
    t1 = time.perf_counter()
    items = _order(exact, eaters, ctx, tiebreak)
    exact_count = len(items)

    present = {
        "ingredients": bool(q.ingredients_include),
        "cuisine": bool(q.cuisines),
        "tags": bool(q.tags or q.spice),
        "max_mins+15": q.max_mins is not None,
        "max_mins": q.max_mins is not None,
    }
    dropped: list[str] = []
    for step in SOFT_STEPS:
        if len(items) >= min_results:
            break
        if not present[step]:
            continue
        if step == "max_mins+15":
            assert q.max_mins is not None
            max_mins = q.max_mins + 15
        elif step == "max_mins":
            max_mins = None
        else:
            active.discard(step)
        group = "max_mins" if step.startswith("max_mins") else step
        if group not in dropped:
            dropped.append(group)
        seen = {x.recipe.id for x in items}
        extra = [
            r
            for r in hard
            if r.id not in seen and slot in r.meal_slots and _soft_ok(r, q, active, max_mins)
        ]
        items += _order(extra, eaters, ctx, tiebreak)
    if not items:
        # Nothing at all even with every soft filter gone: the slot's best (still safe).
        items = _order([r for r in hard if slot in r.meal_slots], eaters, ctx, tiebreak)
    t3 = time.perf_counter()
    return Retrieval(
        items=items[:limit],
        slot=slot,
        exact_count=min(exact_count, limit),
        dropped=dropped,
        n_eaters=len(eaters),
        retrieve_ms=(t1 - t0) * 1000,
        rank_ms=(t3 - t1) * 1000,
    )
