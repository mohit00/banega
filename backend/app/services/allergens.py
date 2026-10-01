"""The fixed allergen picklist (F-5.2-03, review H3): every allergen stored on a member,
an ingredient or a recipe is an :class:`~app.models.enums.Allergen` value, so the engine's
"allergen = hard No" rule is an intersection of enum values, never of free text.

Members may add free text in ``allergens_other``: it is shown as a warning, never a No.
"""

from __future__ import annotations

from collections.abc import Iterable

from app.models.enums import Allergen

# Common spellings (English, Hinglish, Hindi transliteration) -> picklist value.
SYNONYMS: dict[str, Allergen] = {
    "peanuts": Allergen.peanut,
    "groundnut": Allergen.peanut,
    "groundnuts": Allergen.peanut,
    "moongphali": Allergen.peanut,
    "mungfali": Allergen.peanut,
    "nuts": Allergen.tree_nut,
    "tree_nuts": Allergen.tree_nut,
    "treenut": Allergen.tree_nut,
    "cashew": Allergen.tree_nut,
    "kaju": Allergen.tree_nut,
    "almond": Allergen.tree_nut,
    "badam": Allergen.tree_nut,
    "walnut": Allergen.tree_nut,
    "akhrot": Allergen.tree_nut,
    "pista": Allergen.tree_nut,
    "pistachio": Allergen.tree_nut,
    "dairy": Allergen.milk,
    "lactose": Allergen.milk,
    "doodh": Allergen.milk,
    "wheat": Allergen.gluten,
    "maida": Allergen.gluten,
    "atta": Allergen.gluten,
    "til": Allergen.sesame,
    "soya": Allergen.soy,
    "soybean": Allergen.soy,
    "eggs": Allergen.egg,
    "anda": Allergen.egg,
    "machli": Allergen.fish,
    "prawn": Allergen.shellfish,
    "prawns": Allergen.shellfish,
    "shrimp": Allergen.shellfish,
    "crab": Allergen.shellfish,
    "jhinga": Allergen.shellfish,
    "sarson": Allergen.mustard,
    "rai": Allergen.mustard,
}
_VALUES = {a.value: a for a in Allergen}


def normalize(value: object) -> Allergen | None:
    """ "Peanut", "tree nut", "Tree-Nuts", "kaju" -> Allergen; unknown -> None."""
    if isinstance(value, Allergen):
        return value
    key = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    if not key:
        return None
    return _VALUES.get(key) or SYNONYMS.get(key) or SYNONYMS.get(key.replace("_", ""))


def split(values: Iterable[object] | None) -> tuple[list[str], list[str]]:
    """(sorted picklist values, unknown texts in input order)."""
    known: set[str] = set()
    unknown: list[str] = []
    for v in values or []:
        a = normalize(v)
        if a is None:
            text = str(v).strip()
            if text and text not in unknown:
                unknown.append(text)
        else:
            known.add(a.value)
    return sorted(known), unknown


def strict(values: Iterable[object] | None) -> list[str]:
    """Normalised picklist values; ValueError naming the unknown ones (import, admin, API)."""
    known, unknown = split(values)
    if unknown:
        allowed = ", ".join(a.value for a in Allergen)
        raise ValueError(f"unknown allergen(s) {', '.join(unknown)}; allowed: {allowed}")
    return known


def engine_set(values: Iterable[object] | None) -> frozenset[str]:
    """What the engine intersects: picklist values only (free text can never exclude)."""
    return frozenset(split(values)[0])
