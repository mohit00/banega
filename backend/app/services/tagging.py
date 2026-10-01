"""Derived recipe flags (F-5.2-01a, F-6-06): computed from ingredients, never hand-set.

Jain policy (F-5.2-01a):
    jain_safe = veg AND no onion/garlic AND no root vegetable
                AND no honey, mushroom or yeast-fermented item.

The editor's claims (``editorial_jain_safe``, ``editorial_diet``) are kept only to check them:
every contradiction becomes an entry in ``policy_violations`` and blocks publishing.
"""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field
from typing import Any

from app.models.catalogue import DEFAULT_INGREDIENT_FLAGS, Ingredient, Recipe
from app.services import allergens as allergen_svc

# Flags that break the Jain policy, in the order used to pick the reason shown to the user.
JAIN_BREAKING_FLAGS: tuple[str, ...] = (
    "onion_garlic",
    "root_veg",
    "honey",
    "mushroom",
    "fermented",
)

# Allergens implied by a flag even when the editor forgot to list them on the ingredient.
_IMPLIED_ALLERGENS: dict[str, str] = {"dairy": "milk", "gluten": "gluten", "egg": "egg"}
_MEAT_ALLERGENS: dict[str, str] = {"fish": "fish", "shellfish": "shellfish"}


@dataclass(frozen=True, slots=True)
class IngredientFacts:
    """What the derivation needs to know about one recipe ingredient."""

    ref: str  # slug (or id) for messages
    name: str
    flags: Mapping[str, Any]
    allergens: frozenset[str] = frozenset()


@dataclass(slots=True)
class DerivedFlags:
    is_veg: bool = True
    has_egg: bool = False
    has_nonveg: bool = False
    meat_types: list[str] = field(default_factory=list)
    jain_safe: bool = True
    no_onion_garlic: bool = True
    has_root_veg: bool = False
    dairy_free: bool = True
    gluten_free: bool = True
    allergens: list[str] = field(default_factory=list)
    # flag -> ingredient refs that set it (onion_garlic, root_veg, honey, ...)
    offenders: dict[str, list[str]] = field(default_factory=dict)
    violations: list[dict[str, Any]] = field(default_factory=list)

    @property
    def jain_reason(self) -> str | None:
        """First Jain-breaking flag present (engine reason key), or None when Jain-safe."""
        if self.has_nonveg:
            return "non_veg"
        if self.has_egg:
            return "has_egg"
        for flag in JAIN_BREAKING_FLAGS:
            if self.offenders.get(flag):
                return flag
        return None


def _flag(flags: Mapping[str, Any], key: str) -> Any:
    return flags.get(key, DEFAULT_INGREDIENT_FLAGS[key])


def derive(
    items: Iterable[IngredientFacts],
    *,
    editorial_jain_safe: bool = False,
    editorial_diet: str | None = None,
    vrat_ok: bool = False,
) -> DerivedFlags:
    items = list(items)
    out = DerivedFlags()
    allergens: set[str] = set()
    meat_types: set[str] = set()

    def offend(flag: str, ref: str) -> None:
        refs = out.offenders.setdefault(flag, [])
        if ref not in refs:
            refs.append(ref)

    for it in items:
        allergens |= allergen_svc.engine_set(it.allergens)
        meat = str(_flag(it.flags, "meat_type") or "none")
        if meat != "none":
            meat_types.add(meat)
            offend("meat", it.ref)
            if meat in _MEAT_ALLERGENS:
                allergens.add(_MEAT_ALLERGENS[meat])
        for key, allergen in _IMPLIED_ALLERGENS.items():
            if _flag(it.flags, key):
                allergens.add(allergen)
                offend(key, it.ref)
        for key in JAIN_BREAKING_FLAGS:
            if _flag(it.flags, key):
                offend(key, it.ref)

    out.meat_types = sorted(meat_types)
    out.has_nonveg = bool(meat_types)
    out.has_egg = bool(out.offenders.get("egg"))
    out.is_veg = not (out.has_nonveg or out.has_egg)
    out.no_onion_garlic = not out.offenders.get("onion_garlic")
    out.has_root_veg = bool(out.offenders.get("root_veg"))
    out.dairy_free = "milk" not in allergens
    out.gluten_free = "gluten" not in allergens
    out.allergens = sorted(allergens)
    out.jain_safe = (
        bool(items)
        and out.is_veg
        and not any(out.offenders.get(flag) for flag in JAIN_BREAKING_FLAGS)
    )
    out.violations = _violations(out, items, editorial_jain_safe, editorial_diet, vrat_ok)
    return out


def _violations(
    d: DerivedFlags,
    items: list[IngredientFacts],
    editorial_jain_safe: bool,
    editorial_diet: str | None,
    vrat_ok: bool,
) -> list[dict[str, Any]]:
    v: list[dict[str, Any]] = []
    if not items:
        v.append({"code": "no_ingredients", "message": "Recipe has no mapped ingredients."})
        return v
    if editorial_jain_safe and not d.jain_safe:
        reason = d.jain_reason or "unknown"
        refs = d.offenders.get(reason if reason not in ("non_veg", "has_egg") else "meat", [])
        if reason == "has_egg":
            refs = d.offenders.get("egg", [])
        v.append(
            {
                "code": "jain_claim_contradicted",
                "reason": reason,
                "ingredients": refs,
                "message": f"Marked Jain-safe but contains {reason}: {', '.join(refs)}.",
            }
        )
    if d.jain_safe and not editorial_jain_safe:
        v.append(
            {
                "code": "jain_unconfirmed",
                "message": "Ingredients are Jain-safe but the recipe is not marked Jain-safe. "
                "Confirm it, or add the missing onion/garlic/root ingredients.",
            }
        )
    derived_diet = "non_veg" if d.has_nonveg else ("egg" if d.has_egg else "veg")
    if editorial_diet and editorial_diet != derived_diet:
        v.append(
            {
                "code": "diet_claim_contradicted",
                "claimed": editorial_diet,
                "derived": derived_diet,
                "message": f"Marked {editorial_diet} but ingredients say {derived_diet}.",
            }
        )
    if vrat_ok and not d.is_veg:
        v.append({"code": "vrat_not_veg", "message": "Marked vrat-ok but is not vegetarian."})
    return v


def facts_for(ingredient: Ingredient) -> IngredientFacts:
    return IngredientFacts(
        ref=ingredient.slug,
        name=ingredient.name_en,
        flags=ingredient.flags or {},
        allergens=frozenset(ingredient.allergens or []),
    )


def apply_derived(recipe: Recipe, ingredients: Iterable[Ingredient] | None = None) -> DerivedFlags:
    """Recompute and store the derived columns on ``recipe``.

    ``ingredients`` defaults to the ingredients of ``recipe.ingredients`` (must be loaded).
    """
    if ingredients is None:
        ingredients = [ri.ingredient for ri in recipe.ingredients]
    d = derive(
        (facts_for(i) for i in ingredients),
        editorial_jain_safe=recipe.editorial_jain_safe,
        editorial_diet=recipe.editorial_diet,
        vrat_ok=recipe.vrat_ok,
    )
    recipe.is_veg = d.is_veg
    recipe.has_egg = d.has_egg
    recipe.has_nonveg = d.has_nonveg
    recipe.meat_types = d.meat_types
    recipe.jain_safe = d.jain_safe
    recipe.no_onion_garlic = d.no_onion_garlic
    recipe.has_root_veg = d.has_root_veg
    recipe.dairy_free = d.dairy_free
    recipe.gluten_free = d.gluten_free
    recipe.allergens = d.allergens
    recipe.policy_violations = d.violations
    return d
