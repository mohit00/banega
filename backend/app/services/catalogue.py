"""Glue between the ORM and the pure engine: views, scaling (F-5.5-05) and slot defaults."""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import date, datetime, time
from decimal import ROUND_HALF_UP, Decimal

from app.engine import EaterView, RecipeView, parse_exclusions, parse_needs
from app.models import Member, Recipe, ScalingRule
from app.services import allergens as allergen_svc

# Above this multiple of base servings the app says "Do batch mein banayein" (F-5.5-05).
BATCH_THRESHOLD = 3.0
# Sublinear: x0.75 of the increase per doubling -> 2x servings = 1.5x qty.
SUBLINEAR_PER_DOUBLING = 1.5


def recipe_view(recipe: Recipe) -> RecipeView:
    """Engine view of a recipe. ``recipe.ingredients`` must be loaded."""
    main: set[str] = set()
    other: set[str] = set()
    tracked: set[str] = set()
    for ri in recipe.ingredients:
        refs = {str(ri.ingredient_id)}
        if ri.ingredient is not None:
            refs.add(ri.ingredient.slug)
            if ri.ingredient.trackable:
                tracked |= refs
        (main if ri.is_main else other).update(refs)
    return RecipeView(
        id=str(recipe.id),
        name=recipe.name,
        cuisine=recipe.cuisine,
        mins=recipe.mins,
        spice=recipe.spice,
        tags=frozenset(recipe.tags or []),
        dish_category=str(recipe.dish_category),
        meal_slots=frozenset(recipe.meal_slots or []),
        is_veg=recipe.is_veg,
        has_egg=recipe.has_egg,
        has_nonveg=recipe.has_nonveg,
        meat_types=frozenset(recipe.meat_types or []),
        jain_safe=recipe.jain_safe,
        has_onion_garlic=not recipe.no_onion_garlic,
        has_root_veg=recipe.has_root_veg,
        dairy_free=recipe.dairy_free,
        allergens=allergen_svc.engine_set(recipe.allergens),
        vrat_ok=recipe.vrat_ok,
        main_ingredients=frozenset(main),
        other_ingredients=frozenset(other - main),
        tracked_ingredients=frozenset(tracked),
    )


def eater_view(
    member: Member, *, day: date | None = None, vrat_today: bool | None = None
) -> EaterView:
    """Engine view of a member. ``day`` (household-local) turns on the vrat rule when its
    weekday is one of ``member.vrat_days``; ``vrat_today`` overrides."""
    needs = parse_needs(member.needs or [])
    if vrat_today is None:
        vrat_today = day is not None and day.weekday() in set(member.vrat_days or [])
    return EaterView(
        id=str(member.id),
        name=member.name,
        diet=member.diet,
        nonveg_exclusions=parse_exclusions(member.nonveg_exclusions or []),
        no_dairy=member.no_dairy,
        spice=member.spice,
        needs=needs,
        # Picklist values only: allergens_other is a warning, never a hard No.
        allergens=allergen_svc.engine_set(member.allergens),
        dislikes=frozenset(member.dislikes or []),
        is_kid=member.is_kid,
        vrat_today=vrat_today,
        cuisines=frozenset(member.cuisines or []),
        show_on_home=bool(member.show_on_home),
    )


# ---- scaling ----------------------------------------------------------------------------


@dataclass(frozen=True, slots=True)
class ScaleResult:
    factor: float
    batch_suggested: bool


def scale_factor(servings: int, base_servings: int) -> ScaleResult:
    factor = servings / max(1, base_servings)
    return ScaleResult(factor=factor, batch_suggested=factor > BATCH_THRESHOLD)


def rule_multiplier(rule: ScalingRule, factor: float) -> float:
    if rule == ScalingRule.fixed or factor <= 0:
        return 1.0
    if rule == ScalingRule.sublinear:
        return float(SUBLINEAR_PER_DOUBLING ** math.log2(factor))
    return factor


_STEP_BY_UNIT: dict[str, Decimal] = {
    "g": Decimal("5"),
    "ml": Decimal("5"),
    "kg": Decimal("0.05"),
    "l": Decimal("0.05"),
    "cup": Decimal("0.25"),
    "tsp": Decimal("0.25"),
    "tbsp": Decimal("0.25"),
    "pc": Decimal("0.5"),
    "gaddi": Decimal("0.5"),
}


def scale_qty(
    qty: Decimal | None, unit: str | None, rule: ScalingRule, factor: float
) -> Decimal | None:
    """Scaled quantity rounded to a kitchen-friendly step for the unit."""
    if qty is None:
        return None
    raw = Decimal(str(float(qty) * rule_multiplier(rule, factor)))
    step = _STEP_BY_UNIT.get((unit or "").lower(), Decimal("0.01"))
    rounded = (raw / step).quantize(Decimal("1"), rounding=ROUND_HALF_UP) * step
    if rounded <= 0:
        rounded = step
    if rounded == rounded.to_integral():
        return rounded.quantize(Decimal("1"))
    return rounded.normalize()


# ---- slots ------------------------------------------------------------------------------


def default_slot(now_local: datetime, enabled: list[str] | None = None) -> str:
    """F-5.3-01 defaults by household-local time. After midnight it is still Dinner."""
    t = now_local.time()
    if time(4, 0) <= t < time(11, 0):
        return "nashta"
    if time(11, 0) <= t < time(16, 0):
        return "lunch"
    shaam_on = enabled is not None and "shaam" in enabled
    if shaam_on and time(16, 0) <= t < time(18, 30):
        return "shaam"
    return "dinner"


def diet_mark(recipe: Recipe) -> str:
    """The tile's diet mark: veg | egg | non_veg."""
    if recipe.has_nonveg:
        return "non_veg"
    if recipe.has_egg:
        return "egg"
    return "veg"
