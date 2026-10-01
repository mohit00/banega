"""Maharaj retrieve + rank + template writer, over the engine fixtures (no DB).

The oracle for texts is a verbatim port of the prototype's reply() (tests/maharaj_oracle.py).
"""

from __future__ import annotations

from dataclasses import replace

import pytest

from app.engine import EaterView
from app.services.maharaj.parse import RuleParser
from app.services.maharaj.pipeline import DEFAULT_CONFIG
from app.services.maharaj.retrieve import retrieve
from app.services.maharaj.types import ParsedQuery
from app.services.maharaj.write import (
    ReplyFacts,
    TemplateWriter,
    build_facts,
    constraint_line,
    validate,
)
from tests.engine_fixtures import household, seed_recipes
from tests.maharaj_oracle import constraint_line as proto_constraint_line
from tests.maharaj_oracle import proto_recipes, reply

QUICK_ASKS = [
    "15 min mein kuch",
    "Kuch halka",
    "Baarish special",
    "Daughter ka tiffin",
    "Mehmaan aa rahe hain",
    "High protein",
]
SEEDS = seed_recipes()
VIEWS = [s.view for s in SEEDS]
NAMES = {s.view.id: s.raw["name"] for s in SEEDS}
PROTO = proto_recipes({s.view.id: s.view.jain_safe for s in SEEDS})


def _answer(
    text: str, slot: str = "lunch", *, min_results: int = 3, eaters: list[EaterView] | None = None
) -> tuple[list[str], str, ParsedQuery]:
    eaters = eaters or household()
    q = RuleParser([e.name for e in eaters]).parse(text, slot)  # type: ignore[arg-type]
    r = retrieve(VIEWS, eaters, q, min_results=min_results)
    facts = build_facts(
        q=q,
        lang="hinglish",
        slot=r.slot,
        slot_label_hinglish=r.slot.title(),
        n=len(r.items),
        all_ok=r.all_ok,
        exact_count=r.exact_count,
        dropped_groups=r.dropped,
        eaters=eaters,
        recipe_names=[NAMES[x.recipe.id] for x in r.items],
        query_text=text,
    )
    return [x.recipe.id for x in r.items], TemplateWriter().write(facts), q


def test_constraint_line_matches_prototype() -> None:
    assert constraint_line(household(), show_health=True) == proto_constraint_line(True)
    assert constraint_line(household(), show_health=True) == (
        "Dhyaan rakha: Papa (low sugar) · Dadi (Jain) · Daughter (kam mirch)"
    )
    # F-5.3-05: health needs are hidden by default (in-app too).
    assert constraint_line(household()) == proto_constraint_line()
    assert "low sugar" not in constraint_line(household())


@pytest.mark.parametrize("ask", QUICK_ASKS)
def test_quick_asks_equal_prototype_reply(ask: str) -> None:
    """Prototype semantics (relax only when nothing matches) give identical texts, cards
    and chips for the six quick asks."""
    oracle = reply(ask, "lunch", PROTO)
    ids, text, q = _answer(ask, min_results=1)
    assert text == oracle["text"]
    assert ids == oracle["recipes"]
    assert DEFAULT_CONFIG["follow_ups"][q.slot] == oracle["chips"]


def test_quick_asks_with_default_relaxation() -> None:
    """With MAHARAJ_MIN_RESULTS=3 only "Baarish special" (one exact match) changes: the exact
    match stays first and the reply names the relaxed filters (F-5.4-04)."""
    for ask in QUICK_ASKS:
        oracle = reply(ask, "lunch", PROTO)
        ids, text, _ = _answer(ask)
        if ask == "Baarish special":
            assert ids[0] == "kadhi" and len(ids) == 4
            assert text.endswith(
                "\n1 bilkul match; baaki kareeb wale (mehmaan-worthy, baarish wala chhod ke)."
            )
        else:
            assert (ids, text) == (oracle["recipes"], oracle["text"])


def test_relaxation_order_cuisine_tags_then_time() -> None:
    eaters = household()
    q = ParsedQuery(
        slot="nashta",
        explicit_slot=True,
        tags=["protein"],
        cuisines=["Bengali"],
        max_mins=10,
    )
    r = retrieve(VIEWS, eaters, q, min_results=3)
    assert r.exact_count == 0
    assert r.dropped[:2] == ["cuisine", "tags"]
    assert all("nashta" in x.recipe.meal_slots for x in r.items)
    # Explicit slot is hard: never relaxed.
    q2 = q.model_copy(update={"cuisines": [], "tags": [], "max_mins": 25})
    r2 = retrieve(VIEWS, eaters, q2, min_results=50)
    assert r2.dropped == ["max_mins"]
    assert all("nashta" in x.recipe.meal_slots for x in r2.items)


def test_no_match_text_and_dropped_line() -> None:
    ids, text, _ = _answer("bengali nashta", "lunch")
    assert ids
    assert text.startswith(
        "Is combo mein exact match nahi mila. Nashta ke liye ye sabse kareeb hain:"
    )
    assert text.endswith("\nChhoda: Bengali.")


def test_allergic_member_never_gets_allergen_card() -> None:
    """Poha has moongphali (peanut). With Daughter allergic to peanut it is never shown:
    not as an exact match, not among relaxed closest options, not in the no-match list."""
    poha = next(v for v in VIEWS if v.id == "poha")
    assert "peanut" in poha.allergens
    eaters = [
        replace(e, allergens=frozenset({"peanut"})) if e.name == "Daughter" else e
        for e in household()
    ]
    for text, slot in [
        ("Kuch halka nashta", "nashta"),
        ("maharashtrian nashta", "nashta"),  # poha is the only Maharashtrian dish
        ("bengali protein nashta 5 min", "nashta"),  # nothing matches: closest options
        ("15 min mein kuch", "lunch"),
    ]:
        for min_results in (1, 3, 10):
            ids, _, _ = _answer(text, slot, min_results=min_results, eaters=eaters)
            assert "poha" not in ids, (text, min_results)
            assert ids, text


def test_member_focus_never_gets_a_no() -> None:
    eaters = household()
    dadi = next(e for e in eaters if e.name == "Dadi")
    for min_results in (1, 4, 10):
        ids, _, q = _answer("Dadi ke liye kuch bengali", "dinner", min_results=min_results)
        assert q.member_focus == "Dadi"
        views = {v.id: v for v in VIEWS}
        for rid in ids:
            v = views[rid]
            assert v.jain_safe and not v.has_nonveg and not v.has_egg, rid
    assert dadi.name == "Dadi"


def test_exclusions_are_hard() -> None:
    ids, _, q = _answer("paneer nahi, kuch dinner", "lunch", min_results=10)
    assert q.ingredients_exclude == ["paneer"]
    assert not {"pbm", "palak", "cheela"} & set(ids)


def test_off_topic_and_languages() -> None:
    f = ReplyFacts(
        lang="en",
        slot="lunch",
        slot_label="lunch",
        n=2,
        all_ok=1,
        exact_count=2,
        no_match=False,
        why=["light"],
        dropped=[],
        constraint_line="Kept in mind: Dadi (Jain)",
        recipe_names=["Dal Tadka & Jeera Rice", "Moong Dal Khichdi"],
    )
    w = TemplateWriter()
    assert w.write(f) == (
        "2 options for lunch — light.\nThe whole family can eat 1 of them. "
        "Kept in mind: Dadi (Jain)."
    )
    hi = replace(f, lang="hi", slot_label="लंच", why=["हल्का"], constraint_line="ध्यान रखा: दादी (जैन)")
    assert w.write(hi) == "लंच के लिए 2 विकल्प — हल्का।\n1 में पूरा परिवार खा सकता है। ध्यान रखा: दादी (जैन)।"
    assert w.write(replace(f, off_topic=True)) == "I can only help with food and cooking."


def test_llm_output_validation() -> None:
    f = ReplyFacts(
        lang="hinglish",
        slot="lunch",
        slot_label="Lunch",
        n=2,
        all_ok=1,
        exact_count=2,
        no_match=False,
        why=["20 min ke andar"],
        dropped=[],
        constraint_line="",
        recipe_names=["Curd Rice", "Vegetable Upma"],
    )
    catalogue = ["Curd Rice", "Vegetable Upma", "Chicken Curry"]
    ok = (
        "Curd Rice aur Vegetable Upma 20 min mein ban jaayenge. "
        "1 mein poora parivaar kha sakta hai."
    )
    assert validate(ok, f, catalogue) == ok
    assert validate("Chicken Curry try karo, sabko pasand aayega.", f, catalogue) is None
    assert validate("Curd Rice diabetes ke liye best hai.", f, catalogue) is None
    assert validate("3 mein poora parivaar kha sakta hai.", f, catalogue) is None
    assert validate("Ek. Do. Teen. Char.", f, catalogue) is None
    assert validate("**Curd Rice** banao.", f, catalogue) is None
    # Fabricated dishes (not in the catalogue at all) are rejected too (review primary #5).
    assert validate("Aaj Rajma Chawal banao, Curd Rice bhi.", f, catalogue) is None
    assert validate("Curd Rice ke saath Paneer Tikka lo.", f, catalogue) is None
    # Sentence-initial capitals, the meal and words the user typed are fine.
    assert validate("Lunch ke liye Curd Rice. Aaj halka rakho.", f, catalogue) is not None
    typed = replace(f, query_text="Dadi ke liye kuch halka")
    assert validate("Dadi ke liye Curd Rice sahi hai.", typed, catalogue) is not None


def test_model_kwargs_per_model() -> None:
    from app.services.maharaj.llm import model_kwargs

    assert model_kwargs("claude-sonnet-5", temperature=0.0) == {
        "thinking": {"type": "disabled"},
        "output_config": {"effort": "low"},
    }
    assert model_kwargs("claude-opus-5-5", temperature=0.3) == {"output_config": {"effort": "low"}}
    assert model_kwargs("claude-haiku-4-5", temperature=0.3) == {"extra_body": {"temperature": 0.3}}
