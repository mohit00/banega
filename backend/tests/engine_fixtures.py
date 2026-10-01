"""Shared engine fixtures: the prototype household, the 22 seed recipes as RecipeViews, and a
line-by-line Python port of design/prototype_logic.js fitFor / summarize (the oracle)."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from app.engine import EaterView, RecipeView, parse_needs
from app.models.enums import Diet, Spice
from app.services.importer import AliasMatcher, load_json
from app.services.tagging import IngredientFacts, derive

RECIPES_JSON: list[dict[str, Any]] = load_json("recipes.seed.json")
INGREDIENTS_JSON: list[dict[str, Any]] = load_json("ingredients.seed.json")
_ING = {i["slug"]: i for i in INGREDIENTS_JSON}
MATCHER = AliasMatcher((i["slug"], i["name_en"], i["aliases"]) for i in INGREDIENTS_JSON)

# design/prototype_logic.js state.members
PROTOTYPE_MEMBERS: list[dict[str, Any]] = [
    {"id": "m1", "name": "Papa", "diet": "Veg", "spice": "Medium",
     "needs": ["Low sugar", "Low oil"], "cuisines": ["North Indian", "Rajasthani"]},
    {"id": "m2", "name": "Mummy", "diet": "Veg", "spice": "Medium",
     "needs": ["High protein"], "cuisines": ["Gujarati", "North Indian"]},
    {"id": "m3", "name": "Dadi", "diet": "Jain", "spice": "Kam",
     "needs": ["Low oil"], "cuisines": ["Rajasthani", "Gujarati"]},
    {"id": "m4", "name": "Daughter", "diet": "Egg", "spice": "Kam",
     "needs": ["Kid-friendly"], "cuisines": ["Indo-Chinese", "South Indian"]},
    {"id": "m5", "name": "Wife", "diet": "Non-veg", "spice": "Teekha",
     "needs": ["High protein"], "cuisines": ["Bengali", "South Indian"]},
]  # fmt: skip

_DIET = {"Veg": Diet.veg, "Jain": Diet.jain, "Egg": Diet.eggetarian, "Non-veg": Diet.non_veg}
_SPICE = {"Kam": Spice.kam, "Medium": Spice.medium, "Teekha": Spice.teekha}


def household() -> list[EaterView]:
    return [
        EaterView(
            id=m["id"],
            name=m["name"],
            diet=_DIET[m["diet"]],
            spice=_SPICE[m["spice"]],
            needs=parse_needs(m["needs"]),
            cuisines=frozenset(m["cuisines"]),
            is_kid=m["name"] == "Daughter",
        )
        for m in PROTOTYPE_MEMBERS
    ]


@dataclass(frozen=True)
class SeedRecipe:
    raw: dict[str, Any]
    view: RecipeView


def seed_recipes(*, jain_from: str = "derived") -> list[SeedRecipe]:
    """RecipeViews for the 22 seed recipes. ``jain_from``: "derived" or "editorial"."""
    out = []
    for r in RECIPES_JSON:
        main: set[str] = set()
        other: set[str] = set()
        facts: list[IngredientFacts] = []
        for i, line in enumerate(r["ingredients_text"]):
            for slug in MATCHER.match(line):
                ing = _ING[slug]
                facts.append(
                    IngredientFacts(slug, ing["name_en"], ing["flags"], frozenset(ing["allergens"]))
                )
                (main if i == 0 else other).add(slug)
        d = derive(facts, editorial_jain_safe=r["jain_safe_editorial"])
        jain_safe = d.jain_safe if jain_from == "derived" else r["jain_safe_editorial"]
        out.append(
            SeedRecipe(
                raw=r,
                view=RecipeView(
                    id=r["id"],
                    name=r["name"],
                    cuisine=r["cuisine"],
                    mins=r["mins"],
                    spice=r["spice"],
                    tags=frozenset(r["tags"]),
                    dish_category=r["dish_category"],
                    meal_slots=frozenset(r["meal_slots"]),
                    is_veg=d.is_veg,
                    has_egg=d.has_egg,
                    has_nonveg=d.has_nonveg,
                    meat_types=frozenset(d.meat_types),
                    jain_safe=jain_safe,
                    has_onion_garlic=not d.no_onion_garlic,
                    has_root_veg=d.has_root_veg,
                    dairy_free=d.dairy_free,
                    allergens=frozenset(d.allergens),
                    vrat_ok=r.get("vrat_ok", False),
                    main_ingredients=frozenset(main),
                    other_ingredients=frozenset(other - main),
                ),
            )
        )
    return out


# ---- the oracle: design/prototype_logic.js, ported literally ---------------------------

_PROTO_DIET = {"veg": "veg", "egg": "egg", "non_veg": "nonveg"}


def proto_fit_for(m: dict[str, Any], r: dict[str, Any], jain: bool) -> str:
    diet = _PROTO_DIET[r["diet"]]
    if m["diet"] == "Jain" and not jain:
        return "no"
    if m["diet"] == "Veg" and diet != "veg":
        return "no"
    if m["diet"] == "Egg" and diet == "nonveg":
        return "no"
    if "No maida" in m["needs"] and "maida" in r["tags"]:
        return "no"
    tw = []
    if m["spice"] == "Kam" and r["spice"] == 3:
        tw.append(1)
    if m["spice"] == "Teekha" and r["spice"] == 1:
        tw.append(1)
    if "Low sugar" in m["needs"] and "lowSugar" not in r["tags"]:
        tw.append(1)
    if "Low oil" in m["needs"] and "lowOil" not in r["tags"]:
        tw.append(1)
    if "High protein" in m["needs"] and "protein" not in r["tags"]:
        tw.append(1)
    if "Kid-friendly" in m["needs"] and "kid" not in r["tags"] and r["spice"] > 1:
        tw.append(1)
    return "tweak" if tw else "fit"


def proto_summarize(r: dict[str, Any], jain: bool | None = None) -> dict[str, Any]:
    jain = r["jain_safe_editorial"] if jain is None else jain
    fits = [proto_fit_for(m, r, jain) for m in PROTOTYPE_MEMBERS]
    n = len(fits)
    can = sum(1 for f in fits if f != "no")
    perfect = sum(1 for f in fits if f == "fit")
    tweaks = sum(1 for f in fits if f == "tweak")
    if can == n and perfect == n:
        badge, label = "fit", "Sabke liye perfect"
    elif can == n:
        badge, label = "tweak", f"Sabke liye · {tweaks} tweak"
    else:
        badge, label = "no", f"{can}/{n} ke liye"
    return {"badge": badge, "label": label, "can": can, "perfect": perfect, "fits": fits}
