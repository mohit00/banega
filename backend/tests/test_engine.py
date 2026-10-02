"""Matching engine: parity with the prototype, the FRD-review extensions, scoring, ranking."""

from __future__ import annotations

import itertools
import random
from dataclasses import replace
from datetime import date, timedelta

import pytest

from app.engine import (
    EaterView,
    FitStatus,
    Need,
    NonVegExclusion,
    RecipeView,
    ScoreContext,
    constraint_line,
    fit,
    parse_exclusions,
    parse_needs,
    rank,
    score,
    summarize,
)
from app.models.enums import Diet, Spice
from tests.engine_fixtures import household, proto_summarize, seed_recipes

# Where the derived Jain flag (F-5.2-01a) disagrees with the prototype's hand-set `jain`:
# cheela, lauki and curd rice contain fresh ginger (adrak = root vegetable); paneer butter
# masala as listed has no onion, garlic or root vegetable.
DERIVED_JAIN_DIFFS = {"cheela": "4/5", "lauki": "4/5", "curdrice": "4/5", "pbm": "all"}


def _label(s: object) -> str:
    from app.engine import Summary

    assert isinstance(s, Summary)
    if s.label_key == "all_perfect":
        return "Sabke liye perfect"
    if s.label_key == "all_with_tweaks":
        return f"Sabke liye · {s.label_params['n']} tweak"
    return f"{s.label_params['can']}/{s.label_params['n']} ke liye"


# ---- parity with design/prototype_logic.js ---------------------------------------------


@pytest.mark.parametrize("sr", seed_recipes(jain_from="editorial"), ids=lambda s: s.raw["id"])
def test_prototype_parity_all_22(sr: object) -> None:
    """With the prototype's own Jain flag, badges, labels and per-member statuses match."""
    from tests.engine_fixtures import SeedRecipe

    assert isinstance(sr, SeedRecipe)
    expected = proto_summarize(sr.raw)
    got = summarize(household(), sr.view)
    assert got.badge == expected["badge"]
    assert _label(got) == expected["label"]
    assert (got.can, got.perfect) == (expected["can"], expected["perfect"])
    assert [f.fit.status.value for f in got.fits] == expected["fits"]


def test_seed_has_22_recipes() -> None:
    assert len(seed_recipes()) == 22


@pytest.mark.parametrize("sr", seed_recipes(jain_from="derived"), ids=lambda s: s.raw["id"])
def test_derived_jain_matches_prototype_except_known(sr: object) -> None:
    from tests.engine_fixtures import SeedRecipe

    assert isinstance(sr, SeedRecipe)
    rid = sr.raw["id"]
    got = summarize(household(), sr.view)
    if rid not in DERIVED_JAIN_DIFFS:
        assert _label(got) == proto_summarize(sr.raw)["label"]
        return
    dadi = next(f for f in got.fits if f.name == "Dadi")
    if DERIVED_JAIN_DIFFS[rid] == "4/5":
        assert dadi.fit.status == FitStatus.no
        assert dadi.fit.reason_key == "root_veg"
        assert _label(got) == "4/5 ke liye"
    else:
        assert dadi.fit.status != FitStatus.no
        assert got.can == 5


def _by_id(jain_from: str = "derived") -> dict[str, RecipeView]:
    return {s.raw["id"]: s.view for s in seed_recipes(jain_from=jain_from)}


def test_named_prototype_outcomes() -> None:
    r = _by_id()
    h = household()
    rajma = summarize(h, r["rajma"])
    assert _label(rajma) == "4/5 ke liye"
    assert [f.name for f in rajma.nos] == ["Dadi"]
    assert rajma.nos[0].fit.reason_key == "onion_garlic"
    assert rajma.note_key == "not_for" and rajma.note_params["names"] == ["Dadi"]

    gatte = summarize(h, r["gatte"])
    assert r["gatte"].jain_safe
    dadi = next(f for f in gatte.fits if f.name == "Dadi")
    assert dadi.fit.status == FitStatus.tweak and dadi.fit.reason_key == "less_chilli_katori"
    assert gatte.badge == "tweak" and gatte.label_params == {"n": 3}

    chicken = summarize(h, r["chicken"])
    assert _label(chicken) == "1/5 ke liye"
    assert {f.fit.reason_key for f in chicken.nos} == {"non_veg"}
    assert _label(summarize(h, r["omelette"])) == "2/5 ke liye"
    khichdi = summarize(h, r["khichdi"])
    assert khichdi.note_key == "tweak_for"
    assert khichdi.note_params["name"] == "Wife"
    assert khichdi.note_params["reason_key"] == "add_chilli"


def test_fit_reasons_perfect_and_favourite() -> None:
    r = _by_id()
    mummy = household()[1]
    assert fit(mummy, r["khichdi"]).reason_key == "favourite_cuisine"
    daughter = household()[3]
    assert fit(daughter, r["cheela"]).reason_key == "perfect"


def test_all_perfect_badge() -> None:
    papa = household()[0]
    r = replace(_by_id()["khichdi"], cuisine="Bengali")
    s = summarize([papa], r)
    assert s.badge == "fit" and s.label_key == "all_perfect" and s.note_key == "all_happy"


def test_no_eaters() -> None:
    s = summarize([], _by_id()["poha"])
    assert s.badge == "no" and s.label_key == "no_eaters"


# ---- hard No extensions (F-5.2-01b, F-5.2-03, F-5.2-04, F-5.2-02) -----------------------


def _eater(**kw: object) -> EaterView:
    base = EaterView(id="e", name="E", diet=Diet.non_veg, spice=Spice.medium)
    return replace(base, **kw)  # type: ignore[arg-type]


def _recipe(**kw: object) -> RecipeView:
    base = RecipeView(id="r", name="R", spice=2, tags=frozenset({"lowOil", "lowSugar"}))
    return replace(base, **kw)  # type: ignore[arg-type]


@pytest.mark.parametrize(
    "allergen", ["peanut", "tree_nut", "milk", "gluten", "sesame", "soy", "egg", "fish",
                 "shellfish", "mustard"],
)  # fmt: skip
def test_every_allergen_is_a_hard_no(allergen: str) -> None:
    f = fit(_eater(allergens=frozenset({allergen})), _recipe(allergens=frozenset({allergen})))
    assert f.status == FitStatus.no and f.reason_key == "allergen"
    assert f.reason_params["allergen"] == allergen


def test_allergen_beats_everything() -> None:
    e = _eater(diet=Diet.jain, allergens=frozenset({"peanut"}))
    r = _by_id()["poha"]  # moongphali + pyaaz
    assert fit(e, r).reason_key == "allergen"


def test_seed_allergens_derived() -> None:
    r = _by_id()
    assert "peanut" in r["poha"].allergens
    assert "tree_nut" in r["pbm"].allergens
    assert {"soy", "gluten"} <= r["noodles"].allergens
    assert "fish" in r["macher"].allergens and "mustard" in r["macher"].allergens
    assert "egg" in r["omelette"].allergens and "milk" in r["omelette"].allergens
    assert "sesame" in r["thepla"].allergens


def test_diet_rules() -> None:
    chicken, omelette, macher, rajma = (_by_id()[k] for k in ("chicken", "omelette", "macher",
                                                              "rajma"))  # fmt: skip
    veg, egg = _eater(diet=Diet.veg), _eater(diet=Diet.eggetarian)
    assert fit(veg, omelette).reason_key == "has_egg"
    assert fit(veg, chicken).reason_key == "non_veg"
    assert fit(egg, omelette).status != FitStatus.no
    assert fit(egg, chicken).reason_key == "non_veg"
    nog = _eater(diet=Diet.no_onion_garlic)
    assert fit(nog, rajma).reason_key == "onion_garlic"
    assert fit(nog, _by_id()["paratha"]).status != FitStatus.no  # aloo is fine without Jain
    jain = _eater(diet=Diet.jain)
    assert fit(jain, _by_id()["paratha"]).reason_key == "root_veg"
    assert fit(jain, _by_id()["idli"]).reason_key == "not_jain_safe"  # fermented batter
    assert fit(jain, chicken).reason_key == "non_veg"  # F-6-03 order: meat before Jain
    assert fit(_eater(diet=Diet.pescatarian), macher).status != FitStatus.no


def test_pescatarian() -> None:
    p = _eater(diet=Diet.pescatarian)
    r = _by_id()
    assert fit(p, r["chicken"]).reason_key == "non_veg"
    assert fit(p, r["chicken"]).reason_params["meat"] == "chicken"
    assert fit(p, r["macher"]).status == FitStatus.tweak or fit(p, r["macher"]).status == (
        FitStatus.fit
    )
    assert fit(p, r["omelette"]).status != FitStatus.no
    prawn = _recipe(has_nonveg=True, is_veg=False, meat_types=frozenset({"shellfish"}))
    assert fit(p, prawn).status != FitStatus.no


def test_nonveg_exclusions_beef_pork_halal() -> None:
    beef = _recipe(has_nonveg=True, is_veg=False, meat_types=frozenset({"beef"}))
    pork = _recipe(has_nonveg=True, is_veg=False, meat_types=frozenset({"pork"}))
    chicken = _recipe(has_nonveg=True, is_veg=False, meat_types=frozenset({"chicken"}))
    no_beef = _eater(nonveg_exclusions=parse_exclusions(["No beef"]))
    assert fit(no_beef, beef).reason_key == "beef"
    assert fit(no_beef, pork).status != FitStatus.no
    no_pork = _eater(nonveg_exclusions=frozenset({NonVegExclusion.no_pork}))
    assert fit(no_pork, pork).reason_key == "pork"
    halal = _eater(nonveg_exclusions=parse_exclusions(["halal"]))
    assert fit(halal, pork).reason_key == "not_halal"
    assert fit(halal, chicken).status != FitStatus.no
    assert fit(_eater(), beef).status != FitStatus.no


def test_no_dairy_and_maida() -> None:
    r = _by_id()
    assert fit(_eater(no_dairy=True), r["pbm"]).reason_key == "dairy"
    assert fit(_eater(no_dairy=True), r["daltadka"]).status != FitStatus.no
    no_maida = _eater(needs=parse_needs(["No maida"]))
    assert fit(no_maida, r["noodles"]).reason_key == "maida"


def test_dislikes_main_is_no_minor_is_tweak() -> None:
    r = _by_id()["bhindi"]  # main: okra; others: onion, amchur, ...
    assert fit(_eater(dislikes=frozenset({"okra"})), r).reason_key == "dislike_main"
    minor = fit(_eater(dislikes=frozenset({"amchur"})), r)
    assert minor.status == FitStatus.tweak and minor.reason_key == "dislike_skip"
    assert minor.reason_params == {"ingredient": "amchur"}


def test_vrat_day() -> None:
    e = _eater(diet=Diet.veg, vrat_today=True)
    assert fit(e, _by_id()["khichdi"]).reason_key == "vrat"
    assert fit(e, replace(_by_id()["khichdi"], vrat_ok=True)).status != FitStatus.no
    assert fit(replace(e, vrat_today=False), _by_id()["khichdi"]).status != FitStatus.no


def test_tweak_order_matches_prototype() -> None:
    e = _eater(spice=Spice.kam, needs=frozenset(Need))
    r = _recipe(spice=3, tags=frozenset())
    assert fit(e, r).reason_key == "less_chilli_katori"
    assert fit(replace(e, spice=Spice.medium), r).reason_key == "small_portion_salad"
    e2 = replace(e, spice=Spice.medium, needs=frozenset({Need.kid_friendly}))
    assert fit(e2, r).reason_key == "kid_separate_mild"
    assert fit(e2, replace(r, spice=1)).status == FitStatus.fit
    assert fit(_eater(spice=Spice.teekha), replace(r, spice=1)).reason_key == "add_chilli"


def test_parse_needs_accepts_labels_and_keys() -> None:
    assert parse_needs(["Low sugar", "high_protein", "Kid-friendly", "??"]) == {
        Need.low_sugar,
        Need.high_protein,
        Need.kid_friendly,
    }


# ---- property-style checks ---------------------------------------------------------------


def test_fit_is_total_and_consistent_over_random_eaters() -> None:
    rnd = random.Random(7)
    recipes = [s.view for s in seed_recipes()]
    allergens = ["peanut", "milk", "gluten", "egg", "fish", "mustard"]
    for _ in range(400):
        e = EaterView(
            id="x",
            diet=rnd.choice(list(Diet)),
            spice=rnd.choice(list(Spice)),
            needs=frozenset(rnd.sample(list(Need), rnd.randint(0, 3))),
            allergens=frozenset(rnd.sample(allergens, rnd.randint(0, 2))),
            no_dairy=rnd.random() < 0.2,
            vrat_today=rnd.random() < 0.1,
        )
        for r in recipes:
            f = fit(e, r)
            if e.allergens & r.allergens:
                assert f.status == FitStatus.no
            if e.diet in (Diet.veg, Diet.jain, Diet.no_onion_garlic) and not r.is_veg:
                assert f.status == FitStatus.no
            if e.diet == Diet.jain and not r.jain_safe:
                assert f.status == FitStatus.no
            if e.vrat_today and not r.vrat_ok:
                assert f.status == FitStatus.no


# ---- score and rank ------------------------------------------------------------------------


def test_score_formula_terms() -> None:
    papa = household()[0]  # veg, low sugar + low oil, North Indian
    r = _by_id()["khichdi"]  # lowSugar + lowOil, Gujarati
    s = summarize([papa], r)
    # can 10 + perfect 3 + need bonus 2x2
    assert score(s, r, eaters=[papa]) == 17
    fav = replace(r, cuisine="North Indian")
    assert score(summarize([papa], fav), fav, eaters=[papa]) == 19
    today = date(2026, 10, 5)
    ctx = ScoreContext(today=today, last_served={r.id: today - timedelta(days=2)})
    assert score(s, r, ctx, eaters=[papa]) == 17 - 25
    old = ScoreContext(today=today, last_served={r.id: today - timedelta(days=3)})
    assert score(s, r, old, eaters=[papa]) == 17
    liked = ScoreContext(ratings={(papa.id, r.id): 4.5})
    assert score(s, r, liked, eaters=[papa]) == 21
    hated = ScoreContext(ratings={(papa.id, r.id): 1.5})
    assert score(s, r, hated, eaters=[papa]) == 9
    tracked = replace(r, tracked_ingredients=frozenset({"rice", "moong-dal"}))
    s2 = summarize([papa], tracked)
    assert score(s2, tracked, ScoreContext(out_of_stock=frozenset()), eaters=[papa]) == 20
    assert score(s2, tracked, ScoreContext(out_of_stock=frozenset({"rice"})), eaters=[papa]) == 12
    assert score(s2, tracked, ScoreContext(), eaters=[papa]) == 17  # stock unknown


def test_no_eater_penalty() -> None:
    h = household()
    rajma = _by_id()["rajma"]
    # Papa tweak 10+fav 2 | Mummy fit 10+3+fav 2+protein 2 | Dadi no | Daughter 10+3+kid 2 |
    # Wife 10+3+protein 2  = 59, minus 15 because Dadi can't eat it.
    assert score(summarize(h, rajma), rajma, eaters=h) == 44
    without_dadi = h[:2] + h[3:]
    assert score(summarize(without_dadi, rajma), rajma, eaters=without_dadi) == 59


def test_rank_variety_and_pick_excluded() -> None:
    views = [s.view for s in seed_recipes()]
    ranking = rank(views, household(), ScoreContext(), "lunch")
    assert ranking.pick is not None
    ids = [t.recipe.id for t in ranking.tiles]
    assert ranking.pick.recipe.id not in ids
    assert len(ids) == 8
    for _, group in itertools.groupby(sorted(t.recipe.dish_category for t in ranking.tiles)):
        assert len(list(group)) <= 2
    assert all("lunch" in t.recipe.meal_slots for t in ranking.tiles)


def test_rank_is_deterministic() -> None:
    views = [s.view for s in seed_recipes()]
    h = household()
    first = rank(views, h, ScoreContext(), "dinner")
    for seed in range(20):
        shuffled = views[:]
        random.Random(seed).shuffle(shuffled)
        again = rank(shuffled, h, ScoreContext(), "dinner")
        assert again.pick is not None and first.pick is not None
        assert again.pick.recipe.id == first.pick.recipe.id
        assert [t.recipe.id for t in again.tiles] == [t.recipe.id for t in first.tiles]


def test_rank_fills_grid_when_catalogue_lacks_variety() -> None:
    views = [_recipe(id=f"c{i}", dish_category="curry", meal_slots=frozenset({"lunch"}))
             for i in range(6)]  # fmt: skip
    ranking = rank(views, [_eater()], ScoreContext(), "lunch")
    assert len(ranking.tiles) == 5


def test_rank_empty_slot() -> None:
    assert rank([], household(), None, "lunch").pick is None


def test_repetition_pushes_recipe_down() -> None:
    views = [s.view for s in seed_recipes()]
    h = household()
    base = rank(views, h, ScoreContext(today=date(2026, 10, 5)), "lunch")
    assert base.pick is not None
    top = base.pick.recipe.id
    ctx = ScoreContext(today=date(2026, 10, 5), last_served={top: date(2026, 10, 4)})
    again = rank(views, h, ctx, "lunch")
    assert again.pick is not None and again.pick.recipe.id != top


# ---- constraint line (F-5.3-03) ------------------------------------------------------------


def test_constraint_line_priority() -> None:
    items, more = constraint_line(household())
    keys = [c.key for c in items]
    assert keys[0] == "jain" and items[0].params == {"name": "Dadi"}
    assert keys == ["jain", "veg", "eggetarian"]
    assert more == 1  # Daughter (kam mirch)
    h = household()
    h[3] = replace(h[3], allergens=frozenset({"peanut"}))
    items, _ = constraint_line(h)
    assert items[0].key == "allergy" and items[0].params["allergen"] == "peanut"


def test_constraint_line_health_hidden_by_default() -> None:
    papa = household()[0]
    items, _ = constraint_line([papa])
    assert items == []
    items, _ = constraint_line([papa], show_health=True)
    assert {c.key for c in items} == {"low_oil", "low_sugar"}


def test_favourite_cuisine_matches_any_spelling() -> None:
    """The app saves cuisine keys ("north_indian"); recipes carry labels ("North Indian")."""
    from app.engine.types import likes_cuisine

    assert likes_cuisine("North Indian", ["north_indian"])
    assert likes_cuisine("North Indian", ["North Indian"])
    assert likes_cuisine("Indo-Chinese", ["indo_chinese"])
    assert not likes_cuisine("Gujarati", ["north_indian"])
    assert not likes_cuisine(None, ["north_indian"])
