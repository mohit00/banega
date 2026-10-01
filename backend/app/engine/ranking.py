"""score(), rank() and constraint_line(): one scoring formula (F-6-05), variety (F-5.3-02)
and header constraints (F-5.3-03)."""

from __future__ import annotations

from collections import Counter
from collections.abc import Sequence

from app.engine.rules import summarize
from app.engine.types import (
    Constraint,
    EaterView,
    FitStatus,
    Need,
    Ranked,
    Ranking,
    RecipeView,
    ScoreContext,
    Summary,
    Weights,
)
from app.models.enums import Diet, Spice

DEFAULT_WEIGHTS = Weights()

# Need -> recipe tag that satisfies it (need_bonus in F-6-05).
_NEED_TAGS: dict[Need, str] = {
    Need.low_sugar: "lowSugar",
    Need.low_oil: "lowOil",
    Need.high_protein: "protein",
    Need.kid_friendly: "kid",
}


def score(
    summary: Summary,
    recipe: RecipeView,
    ctx: ScoreContext | None = None,
    weights: Weights = DEFAULT_WEIGHTS,
    eaters: Sequence[EaterView] = (),
) -> float:
    """F-6-05. ``eaters`` (same order as ``summary.fits``) enables the need bonus."""
    ctx = ctx or ScoreContext()
    w = weights
    total = 0.0
    needs_by_id = {e.id: e.needs for e in eaters}
    cuisines_by_id = {e.id: e.cuisines for e in eaters}
    for ef in summary.fits:
        status = ef.fit.status
        if status == FitStatus.no:
            continue
        total += w.can
        if status == FitStatus.fit:
            total += w.perfect
        if ef.fit.reason_key == "favourite_cuisine" or (
            recipe.cuisine is not None and recipe.cuisine in cuisines_by_id.get(ef.eater_id, ())
        ):
            total += w.favourite_cuisine
        needs = needs_by_id.get(ef.eater_id, frozenset())
        total += w.need_bonus * sum(1 for n in needs if _NEED_TAGS.get(n, "\0") in recipe.tags)
        avg = ctx.ratings.get((ef.eater_id, recipe.id))
        if avg is not None:
            if avg >= w.liked_min:
                total += w.liked_bonus
            elif avg <= w.disliked_max:
                total -= w.disliked_penalty
    if summary.can < summary.n:
        total -= w.any_no_penalty
    if ctx.today is not None:
        served = ctx.last_served.get(recipe.id)
        if served is not None and 0 <= (ctx.today - served).days < w.repeat_window_days:
            total -= w.repeat_penalty
    if ctx.out_of_stock is not None and recipe.tracked_ingredients:
        out = len(recipe.tracked_ingredients & ctx.out_of_stock)
        total += -w.stock_out_penalty * out if out else w.stock_all_in_bonus
    return total


def rank(
    recipes: Sequence[RecipeView],
    eaters: Sequence[EaterView],
    ctx: ScoreContext | None = None,
    slot: str | None = None,
    *,
    weights: Weights = DEFAULT_WEIGHTS,
    grid_size: int = 8,
    max_per_category: int = 2,
) -> Ranking:
    """Pick + grid for a slot. Deterministic: ties break on minutes, then recipe id.

    Variety (F-5.3-02): the grid excludes the pick and holds at most ``max_per_category``
    recipes per dish_category. If the catalogue for the slot is too small to fill the grid
    under that rule, the remaining places are filled in rank order.
    """
    pool = [r for r in recipes if slot is None or slot in r.meal_slots]
    ranked = [
        Ranked(r, s, score(s, r, ctx, weights, eaters))
        for r in pool
        for s in (summarize(eaters, r),)
    ]
    ranked.sort(key=lambda x: (-x.score, x.recipe.mins, x.recipe.id))
    if not ranked:
        return Ranking(pick=None, tiles=())
    pick, rest = ranked[0], ranked[1:]
    tiles: list[Ranked] = []
    per_cat: Counter[str] = Counter()
    for item in rest:
        if len(tiles) >= grid_size:
            break
        if per_cat[item.recipe.dish_category] < max_per_category:
            tiles.append(item)
            per_cat[item.recipe.dish_category] += 1
    if len(tiles) < grid_size:
        chosen = {t.recipe.id for t in tiles}
        tiles += [x for x in rest if x.recipe.id not in chosen][: grid_size - len(tiles)]
        tiles.sort(key=lambda x: (-x.score, x.recipe.mins, x.recipe.id))
    return Ranking(pick=pick, tiles=tuple(tiles))


# F-5.3-03 priority: allergy > Jain/no-onion-garlic > veg/egg > vrat today > health needs.
def constraint_line(
    eaters: Sequence[EaterView], *, max_items: int = 3, show_health: bool = False
) -> tuple[list[Constraint], int]:
    """Header constraints (keys only) and the "+N more" count.

    Veg / eggetarian only count when someone at the table eats egg or meat (otherwise they
    are not a constraint). Health needs are hidden (F-5.3-05) except for members with
    ``show_on_home`` (or everyone with ``show_health``); the prototype's "kam mirch" for kids
    is shown with them as a spice constraint.
    """
    items: list[Constraint] = []
    for e in eaters:
        for allergen in sorted(e.allergens):
            items.append(Constraint("allergy", {"name": e.name, "allergen": allergen}))
    for e in eaters:
        if e.diet == Diet.jain:
            items.append(Constraint("jain", {"name": e.name}))
        elif e.diet == Diet.no_onion_garlic:
            items.append(Constraint("no_onion_garlic", {"name": e.name}))
    mixed = any(e.diet in (Diet.non_veg, Diet.pescatarian, Diet.eggetarian) for e in eaters)
    if mixed:
        veg = [e.name for e in eaters if e.diet == Diet.veg]
        if veg:
            items.append(Constraint("veg", {"names": veg}))
        if any(e.diet in (Diet.non_veg, Diet.pescatarian) for e in eaters):
            egg = [e.name for e in eaters if e.diet == Diet.eggetarian]
            if egg:
                items.append(Constraint("eggetarian", {"names": egg}))
    for e in eaters:
        if e.vrat_today:
            items.append(Constraint("vrat", {"name": e.name}))
    for e in eaters:
        if e.spice == Spice.kam and (e.is_kid or Need.kid_friendly in e.needs):
            items.append(Constraint("kam_mirch", {"name": e.name}))
    for e in eaters:
        if show_health or e.show_on_home:
            for need in sorted(e.needs):
                if need != Need.kid_friendly:
                    items.append(Constraint(need.value, {"name": e.name}))
    return items[:max_items], max(0, len(items) - max_items)
