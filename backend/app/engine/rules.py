"""fit() and summarize(): the prototype's fitFor / summarize, extended per the FRD review.

Rule order (first match wins). The hard No's follow F-6-03 so that the reason names the real
problem (chicken curry says "non_veg" to a Jain member, not "onion_garlic"); the status is
the same in any order. The Tweak order is the prototype's.

No:    allergen → non_veg (meat/fish for veg-type diets, meat for pescatarian) → has_egg →
       beef / pork / not_halal → Jain (onion_garlic | root_veg | not_jain_safe) or
       no-onion-garlic diet (onion_garlic) → dairy → maida → dislike_main → vrat
Tweak: less_chilli_katori → add_chilli → small_portion_salad → less_oil → add_dahi_paneer →
       kid_separate_mild → dislike_skip
Fit:   favourite_cuisine | perfect
"""

from __future__ import annotations

from collections.abc import Sequence

from app.engine.types import (
    SEAFOOD_TYPES,
    Badge,
    EaterFit,
    EaterView,
    Fit,
    FitStatus,
    Need,
    NonVegExclusion,
    RecipeView,
    Summary,
    likes_cuisine,
)
from app.models.enums import Diet, Spice

# Diets that exclude meat and fish; the first three also exclude egg.
_NO_MEAT_DIETS = frozenset({Diet.veg, Diet.jain, Diet.no_onion_garlic, Diet.eggetarian})
_NO_EGG_DIETS = frozenset({Diet.veg, Diet.jain, Diet.no_onion_garlic})


def _no(key: str, **params: object) -> Fit:
    return Fit(FitStatus.no, key, params)


def _hard_no(e: EaterView, r: RecipeView) -> Fit | None:
    hit = sorted(e.allergens & r.allergens)
    if hit:
        return _no("allergen", allergen=hit[0], allergens=hit)

    if r.has_nonveg:
        if e.diet in _NO_MEAT_DIETS:
            return _no("non_veg")
        if e.diet == Diet.pescatarian and (r.meat_types - SEAFOOD_TYPES):
            return _no("non_veg", meat=sorted(r.meat_types - SEAFOOD_TYPES)[0])
    if r.has_egg and e.diet in _NO_EGG_DIETS:
        return _no("has_egg")

    if "beef" in r.meat_types and NonVegExclusion.no_beef in e.nonveg_exclusions:
        return _no("beef")
    if "pork" in r.meat_types and NonVegExclusion.no_pork in e.nonveg_exclusions:
        return _no("pork")
    if NonVegExclusion.halal_only in e.nonveg_exclusions and r.meat_types & {"pork", "other"}:
        return _no("not_halal")

    if e.diet == Diet.jain and not r.jain_safe:
        if r.has_onion_garlic:
            return _no("onion_garlic")
        if r.has_root_veg:
            return _no("root_veg")
        return _no("not_jain_safe")
    if e.diet == Diet.no_onion_garlic and r.has_onion_garlic:
        return _no("onion_garlic")

    if e.no_dairy and not r.dairy_free:
        return _no("dairy")
    if Need.no_maida in e.needs and "maida" in r.tags:
        return _no("maida")

    disliked_main = sorted(e.dislikes & r.main_ingredients)
    if disliked_main:
        return _no("dislike_main", ingredient=disliked_main[0])
    if e.vrat_today and not r.vrat_ok:
        return _no("vrat")
    return None


def _first_tweak(e: EaterView, r: RecipeView) -> Fit | None:
    if e.spice == Spice.kam and r.spice == 3:
        return Fit(FitStatus.tweak, "less_chilli_katori")
    if e.spice == Spice.teekha and r.spice == 1:
        return Fit(FitStatus.tweak, "add_chilli")
    if Need.low_sugar in e.needs and "lowSugar" not in r.tags:
        return Fit(FitStatus.tweak, "small_portion_salad")
    if Need.low_oil in e.needs and "lowOil" not in r.tags:
        return Fit(FitStatus.tweak, "less_oil")
    if Need.high_protein in e.needs and "protein" not in r.tags:
        return Fit(FitStatus.tweak, "add_dahi_paneer")
    if Need.kid_friendly in e.needs and "kid" not in r.tags and r.spice > 1:
        return Fit(FitStatus.tweak, "kid_separate_mild")
    disliked_minor = sorted(e.dislikes & r.other_ingredients)
    if disliked_minor:
        return Fit(FitStatus.tweak, "dislike_skip", {"ingredient": disliked_minor[0]})
    return None


def fit(eater: EaterView, recipe: RecipeView) -> Fit:
    """One eater's verdict for one recipe."""
    return (
        _hard_no(eater, recipe)
        or _first_tweak(eater, recipe)
        or Fit(
            FitStatus.fit,
            "favourite_cuisine" if likes_cuisine(recipe.cuisine, eater.cuisines) else "perfect",
        )
    )


def summarize(eaters: Sequence[EaterView], recipe: RecipeView) -> Summary:
    """Household verdict for one recipe over today's eaters (prototype `summarize`)."""
    fits = tuple(EaterFit(e.id, e.name, fit(e, recipe)) for e in eaters)
    n = len(fits)
    can = sum(1 for f in fits if f.fit.status != FitStatus.no)
    perfect = sum(1 for f in fits if f.fit.status == FitStatus.fit)
    like = sum(
        1
        for e, f in zip(eaters, fits, strict=True)
        if likes_cuisine(recipe.cuisine, e.cuisines) and f.fit.status != FitStatus.no
    )
    tweaks = [f for f in fits if f.fit.status == FitStatus.tweak]
    nos = [f for f in fits if f.fit.status == FitStatus.no]

    badge: Badge
    label_params: dict[str, object]
    if n == 0:
        badge, label_key, label_params = "no", "no_eaters", {}
    elif can == n and perfect == n:
        badge, label_key, label_params = "fit", "all_perfect", {}
    elif can == n:
        badge, label_key, label_params = "tweak", "all_with_tweaks", {"n": len(tweaks)}
    else:
        badge, label_key, label_params = "no", "some", {"can": can, "n": n}

    if nos:
        note_key = "not_for"
        note_params: dict[str, object] = {
            "names": [f.name for f in nos],
            "eater_ids": [f.eater_id for f in nos],
        }
    elif tweaks:
        first = tweaks[0]
        note_key = "tweak_for"
        note_params = {
            "name": first.name,
            "eater_id": first.eater_id,
            "reason_key": first.fit.reason_key,
            "reason_params": dict(first.fit.reason_params),
        }
    else:
        note_key, note_params = "all_happy", {}

    return Summary(
        n=n,
        can=can,
        perfect=perfect,
        like=like,
        fits=fits,
        badge=badge,
        label_key=label_key,
        label_params=label_params,
        note_key=note_key,
        note_params=note_params,
    )
