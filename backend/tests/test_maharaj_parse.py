"""Maharaj parse stage: the golden set (>= 95%), language detection and LLM-output
resolution. No network: the LLM parser is exercised with a fake client in test_chat_api."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

import pytest

from app.services.maharaj.parse import LlmParseOut, RuleParser, detect_language, from_llm

GOLDEN = Path(__file__).resolve().parents[2] / "content" / "golden-queries.json"


def _golden() -> dict[str, Any]:
    return json.loads(GOLDEN.read_text(encoding="utf-8"))


def _compare(parser: RuleParser, item: dict[str, Any], slot: str) -> dict[str, Any]:
    p = parser.parse(item["q"], slot)  # type: ignore[arg-type]
    e = item["expect"]
    got: dict[str, Any] = {
        "slot": p.slot if p.explicit_slot else None,
        "tags": sorted(p.tags),
        "max_mins": p.max_mins,
        "cuisines": sorted(p.cuisines),
        "member_focus": p.member_focus,
    }
    exp: dict[str, Any] = {
        "slot": e["slot"],
        "tags": sorted(e["tags"]),
        "max_mins": e["max_mins"],
        "cuisines": sorted(e["cuisines"]),
        "member_focus": e["member_focus"],
    }
    for key in ("ingredients_include", "ingredients_exclude"):
        if key in e:
            got[key], exp[key] = sorted(getattr(p, key)), sorted(e[key])
    for key in ("diet", "spice"):
        if key in e:
            got[key], exp[key] = getattr(p, key), e[key]
    return {k: (got[k], exp[k]) for k in got if got[k] != exp[k]}


def test_golden_set_shape() -> None:
    doc = _golden()
    queries = doc["queries"]
    assert len(queries) >= 60
    langs = Counter(q["lang"] for q in queries)
    assert langs["hi"] >= 20 and langs["en"] >= 15 and langs["hinglish"] >= 40
    texts = {q["q"] for q in queries}
    # Seeded from the prototype's quick asks, welcome chips, ticker asks and follow-ups.
    for seed in (
        "15 min mein kuch",
        "Kuch halka",
        "Baarish special",
        "Daughter ka tiffin",
        "Mehmaan aa rahe hain",
        "High protein",
        "Aaj lunch mein kya?",
        "Dadi ke liye Jain dinner",
        "Paneer wala kuch",
        "Dadi ke liye kya?",
    ):
        assert seed in texts
    assert len(texts) == len(queries), "duplicate queries"


def test_rule_parser_golden_accuracy() -> None:
    doc = _golden()
    parser = RuleParser(doc["household_members"])
    misses = {
        item["q"]: diff
        for item in doc["queries"]
        if (diff := _compare(parser, item, doc["current_slot"]))
    }
    accuracy = 1 - len(misses) / len(doc["queries"])
    assert accuracy >= 0.95, misses


def test_devanagari_queries_detected_as_hindi() -> None:
    for item in _golden()["queries"]:
        if item["lang"] == "hi":
            assert detect_language(item["q"]) == "hi", item["q"]


@pytest.mark.parametrize(
    ("text", "lang"),
    [
        ("Kuch halka", "hinglish"),
        ("15 min mein kuch", "hinglish"),
        ("What should I make for dinner?", "en"),
        ("High protein", None),  # too short to tell: the user's language setting decides
        ("दादी के लिए क्या?", "hi"),
    ],
)
def test_language_detection(text: str, lang: str | None) -> None:
    assert detect_language(text) == lang


def test_prototype_why_fragments() -> None:
    p = RuleParser(["Papa", "Mummy", "Dadi", "Daughter", "Wife"])
    assert p.parse("Daughter ka tiffin").why == ["bachchon ko pasand", "Daughter ke hisaab se"]
    assert p.parse("Baarish special").why == ["mehmaan-worthy", "baarish wala"]
    assert p.parse("15 min mein kuch").why == ["20 min ke andar"]
    assert p.parse("Paneer wala kuch").why == ["paneer wala"]


def test_rule_parser_edge_cases() -> None:
    p = RuleParser(["Dadi", "Daughter"])
    assert p.parse("healthy breakfast").max_mins is None  # "fast" inside "breakfast"
    assert p.parse("rajma for the kidney").tags == []  # "kid" inside "kidney"
    assert p.parse("गुजराती खाना").explicit_slot is False  # "रात" inside "गुजराती"
    assert p.parse("25 min mein lunch").max_mins == 25  # explicit numbers win (F-7-05)
    q = p.parse("paneer nahi, aloo wala")
    assert q.ingredients_exclude == ["paneer"] and q.ingredients_include == ["potato"]
    assert p.parse("bina pyaaz aur lahsun").ingredients_exclude == ["garlic", "onion"]
    assert p.parse("4 mehmaan aur 2 bachche").guests is not None
    assert p.parse("beti ka tiffin").member_focus == "Daughter"


def _llm_out(**kw: Any) -> LlmParseOut:
    base: dict[str, Any] = {
        "slot": None,
        "tags": [],
        "max_mins": None,
        "ingredients_include": [],
        "ingredients_exclude": [],
        "cuisines": [],
        "member_focus": None,
        "guests_adults": None,
        "guests_kids": None,
        "guests_diet": None,
        "diet": None,
        "spice": None,
        "mood": None,
        "language": "hinglish",
        "off_topic": False,
    }
    base.update(kw)
    return LlmParseOut.model_validate(base)


def test_llm_output_is_resolved_against_the_household() -> None:
    rule = RuleParser(["Dadi", "Daughter"])
    q = from_llm(
        _llm_out(
            tags=["kid", "light"],
            member_focus="beti",
            ingredients_include=["Paneer", "unobtainium"],
            ingredients_exclude=["onion"],
            max_mins=900,
        ),
        rule,
        "dinner",
    )
    assert q.source == "llm" and q.slot == "dinner" and not q.explicit_slot
    assert q.tags == ["light", "kid"]  # prototype order
    assert q.member_focus == "Daughter"
    assert q.ingredients_include == ["paneer"] and q.ingredients_exclude == ["onion"]
    assert q.max_mins is None  # out of range: dropped
    assert q.why == ["halka", "bachchon ko pasand", "paneer wala", "bina pyaaz",
                     "Daughter ke hisaab se"]  # fmt: skip
    stranger = from_llm(_llm_out(member_focus="Chachu"), rule, "lunch")
    assert stranger.member_focus is None
