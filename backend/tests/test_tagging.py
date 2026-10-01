"""Derived recipe flags and the Jain policy check (F-5.2-01a, F-6-06)."""

from __future__ import annotations

from typing import Any

from app.services.tagging import IngredientFacts, derive


def _i(ref: str, allergens: tuple[str, ...] = (), **flags: Any) -> IngredientFacts:
    return IngredientFacts(ref=ref, name=ref, flags=flags, allergens=frozenset(allergens))


def test_plain_veg_is_jain_safe() -> None:
    d = derive([_i("besan"), _i("curd", dairy=True), _i("hing", ("gluten",))])
    assert d.is_veg and d.jain_safe and d.no_onion_garlic and not d.has_root_veg
    assert not d.dairy_free and not d.gluten_free
    assert d.allergens == ["gluten", "milk"]
    assert d.jain_reason is None


def test_onion_garlic_breaks_jain_and_nog() -> None:
    d = derive([_i("dal"), _i("onion", onion_garlic=True, root_veg=True)])
    assert not d.jain_safe and not d.no_onion_garlic
    assert d.jain_reason == "onion_garlic"


def test_root_veg_only() -> None:
    d = derive([_i("potato", root_veg=True)])
    assert not d.jain_safe and d.no_onion_garlic and d.has_root_veg
    assert d.jain_reason == "root_veg"


def test_honey_mushroom_fermented_break_jain() -> None:
    for flag in ("honey", "mushroom", "fermented"):
        d = derive([_i("x", **{flag: True})])
        assert not d.jain_safe, flag
        assert d.jain_reason == flag
        assert d.is_veg and d.no_onion_garlic


def test_egg_and_meat() -> None:
    egg = derive([_i("egg", egg=True)])
    assert egg.has_egg and not egg.is_veg and not egg.has_nonveg and not egg.jain_safe
    assert "egg" in egg.allergens
    fish = derive([_i("rohu", meat_type="fish")])
    assert fish.has_nonveg and fish.meat_types == ["fish"] and "fish" in fish.allergens
    prawn = derive([_i("prawn", meat_type="shellfish")])
    assert "shellfish" in prawn.allergens
    mixed = derive([_i("chicken", meat_type="chicken"), _i("egg", egg=True)])
    assert mixed.jain_reason == "non_veg"


def test_empty_recipe_is_not_jain_safe() -> None:
    d = derive([], editorial_jain_safe=True)
    assert not d.jain_safe
    assert [v["code"] for v in d.violations] == ["no_ingredients"]


def test_violation_when_editor_claims_jain_but_root_veg() -> None:
    d = derive([_i("dal"), _i("ginger", root_veg=True)], editorial_jain_safe=True)
    assert [v["code"] for v in d.violations] == ["jain_claim_contradicted"]
    assert d.violations[0]["reason"] == "root_veg"
    assert d.violations[0]["ingredients"] == ["ginger"]


def test_violation_when_egg_claimed_jain() -> None:
    d = derive([_i("egg", egg=True)], editorial_jain_safe=True, editorial_diet="egg")
    v = {x["code"]: x for x in d.violations}
    assert set(v) == {"jain_claim_contradicted"}
    assert v["jain_claim_contradicted"]["reason"] == "has_egg"
    assert v["jain_claim_contradicted"]["ingredients"] == ["egg"]


def test_unconfirmed_jain_is_flagged() -> None:
    d = derive([_i("paneer", dairy=True)], editorial_jain_safe=False)
    assert [v["code"] for v in d.violations] == ["jain_unconfirmed"]


def test_diet_claim_checked() -> None:
    d = derive(
        [_i("chicken", meat_type="chicken")],
        editorial_diet="veg",
        vrat_ok=True,
    )
    codes = {v["code"] for v in d.violations}
    assert codes == {"diet_claim_contradicted", "vrat_not_veg"}
    ok = derive([_i("chicken", meat_type="chicken")], editorial_diet="non_veg")
    assert ok.violations == []


def test_consistent_recipe_has_no_violations() -> None:
    d = derive([_i("besan")], editorial_jain_safe=True, editorial_diet="veg")
    assert d.violations == []
