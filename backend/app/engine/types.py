"""Engine inputs and outputs. Plain frozen dataclasses: no ORM, no I/O."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass, field
from datetime import date
from enum import StrEnum
from typing import Any, Literal

from app.models.enums import Diet, Spice


def cuisine_key(value: str) -> str:
    """ "North Indian", "north_indian" and "north-indian" compare equal."""
    return "_".join(value.strip().lower().replace("-", " ").replace("_", " ").split())


def likes_cuisine(cuisine: str | None, liked: Iterable[str]) -> bool:
    """True when ``cuisine`` (the recipe's) is among a member's favourites, in any spelling."""
    if cuisine is None:
        return False
    key = cuisine_key(cuisine)
    return any(cuisine_key(c) == key for c in liked)


class FitStatus(StrEnum):
    fit = "fit"
    tweak = "tweak"
    no = "no"


class Need(StrEnum):
    low_oil = "low_oil"
    low_sugar = "low_sugar"
    high_protein = "high_protein"
    no_maida = "no_maida"
    kid_friendly = "kid_friendly"


# Member.needs is stored as the chip label ("Low sugar") or the key ("low_sugar").
_NEED_ALIASES: dict[str, Need] = {
    "low oil": Need.low_oil,
    "low sugar": Need.low_sugar,
    "high protein": Need.high_protein,
    "protein": Need.high_protein,
    "no maida": Need.no_maida,
    "kid-friendly": Need.kid_friendly,
    "kid friendly": Need.kid_friendly,
}


def parse_needs(values: Iterable[str]) -> frozenset[Need]:
    out: set[Need] = set()
    for raw in values:
        key = raw.strip().lower()
        if key in _NEED_ALIASES:
            out.add(_NEED_ALIASES[key])
        else:
            try:
                out.add(Need(key.replace(" ", "_").replace("-", "_")))
            except ValueError:
                continue  # unknown needs are ignored (FR-M4 list may grow before the engine)
    return frozenset(out)


class NonVegExclusion(StrEnum):
    no_beef = "no_beef"
    no_pork = "no_pork"
    halal_only = "halal_only"


_EXCLUSION_ALIASES: dict[str, NonVegExclusion] = {
    "beef": NonVegExclusion.no_beef,
    "no beef": NonVegExclusion.no_beef,
    "no_beef": NonVegExclusion.no_beef,
    "pork": NonVegExclusion.no_pork,
    "no pork": NonVegExclusion.no_pork,
    "no_pork": NonVegExclusion.no_pork,
    "halal": NonVegExclusion.halal_only,
    "halal only": NonVegExclusion.halal_only,
    "halal_only": NonVegExclusion.halal_only,
}


def parse_exclusions(values: Iterable[str]) -> frozenset[NonVegExclusion]:
    return frozenset(
        _EXCLUSION_ALIASES[v.strip().lower()]
        for v in values
        if v.strip().lower() in _EXCLUSION_ALIASES
    )


# Fish-type meat_types a pescatarian eats.
SEAFOOD_TYPES: frozenset[str] = frozenset({"fish", "shellfish"})


@dataclass(frozen=True, slots=True)
class RecipeView:
    """Everything the engine reads about a recipe. Ingredient refs may be ids or slugs."""

    id: str
    name: str = ""
    cuisine: str | None = None
    mins: int = 30
    spice: int = 2
    tags: frozenset[str] = frozenset()
    dish_category: str = "other"
    meal_slots: frozenset[str] = frozenset()
    # derived diet flags (app.services.tagging)
    is_veg: bool = True
    has_egg: bool = False
    has_nonveg: bool = False
    meat_types: frozenset[str] = frozenset()
    jain_safe: bool = True
    has_onion_garlic: bool = False
    has_root_veg: bool = False
    dairy_free: bool = True
    allergens: frozenset[str] = frozenset()
    vrat_ok: bool = False
    # ingredient refs (ids and/or slugs)
    main_ingredients: frozenset[str] = frozenset()
    other_ingredients: frozenset[str] = frozenset()
    tracked_ingredients: frozenset[str] = frozenset()


@dataclass(frozen=True, slots=True)
class EaterView:
    id: str
    name: str = ""
    diet: Diet = Diet.veg
    nonveg_exclusions: frozenset[NonVegExclusion] = frozenset()
    no_dairy: bool = False
    spice: Spice = Spice.medium
    needs: frozenset[Need] = frozenset()
    allergens: frozenset[str] = frozenset()
    # ingredient refs (ids and/or slugs)
    dislikes: frozenset[str] = frozenset()
    is_kid: bool = False
    vrat_today: bool = False
    cuisines: frozenset[str] = frozenset()
    # The member chose to show her health needs in the constraint line (F-5.3-05).
    show_on_home: bool = False


@dataclass(frozen=True, slots=True)
class Fit:
    status: FitStatus
    reason_key: str
    reason_params: Mapping[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class EaterFit:
    eater_id: str
    name: str
    fit: Fit


Badge = Literal["fit", "tweak", "no"]


@dataclass(frozen=True, slots=True)
class Summary:
    n: int
    can: int
    perfect: int
    like: int
    fits: tuple[EaterFit, ...]
    badge: Badge
    label_key: str
    label_params: Mapping[str, Any]
    note_key: str
    note_params: Mapping[str, Any]

    @property
    def tweaks(self) -> tuple[EaterFit, ...]:
        return tuple(f for f in self.fits if f.fit.status == FitStatus.tweak)

    @property
    def nos(self) -> tuple[EaterFit, ...]:
        return tuple(f for f in self.fits if f.fit.status == FitStatus.no)


@dataclass(frozen=True, slots=True)
class ScoreContext:
    """Per-request signals. Everything defaults to "no signal" (0)."""

    today: date | None = None
    # (eater_id, recipe_id) -> average rating 1..5 in the learning window (F-6-05).
    ratings: Mapping[tuple[str, str], float] = field(default_factory=dict)
    # recipe_id -> last date it was served to this household.
    last_served: Mapping[str, date] = field(default_factory=dict)
    # Stock: None = unknown (no penalty or bonus); else the tracked ingredient refs that are Out.
    out_of_stock: frozenset[str] | None = None


@dataclass(frozen=True, slots=True)
class Weights:
    """F-6-05: Score(r) = Σ_eaters [10·can + 3·fit + 2·fav + 2·need_bonus + L]
    - 15·anyNo - Rep + Stock."""

    can: float = 10.0
    perfect: float = 3.0
    favourite_cuisine: float = 2.0
    need_bonus: float = 2.0
    any_no_penalty: float = 15.0
    liked_bonus: float = 4.0  # eater's avg rating >= liked_min
    liked_min: float = 4.0
    disliked_penalty: float = 8.0  # eater's avg rating <= disliked_max
    disliked_max: float = 2.0
    repeat_penalty: float = 25.0
    repeat_window_days: int = 3
    stock_all_in_bonus: float = 3.0
    stock_out_penalty: float = 5.0  # per tracked ingredient that is Out


@dataclass(frozen=True, slots=True)
class Ranked:
    recipe: RecipeView
    summary: Summary
    score: float


@dataclass(frozen=True, slots=True)
class Ranking:
    pick: Ranked | None
    tiles: tuple[Ranked, ...]


@dataclass(frozen=True, slots=True)
class Constraint:
    key: str
    params: Mapping[str, Any]
