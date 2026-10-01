"""A verbatim Python port of design/prototype_logic.js reply() (and summarize / ranked /
constraintLine), used as the oracle for the Maharaj template texts."""

from __future__ import annotations

import re
from typing import Any

from tests.engine_fixtures import PROTOTYPE_MEMBERS, RECIPES_JSON, proto_fit_for

_SLOT_KEY = {"nashta": "b", "lunch": "l", "dinner": "d"}
SLOTS = {"b": "Nashta", "l": "Lunch", "d": "Dinner"}


def proto_recipes(jain: dict[str, bool] | None = None) -> list[dict[str, Any]]:
    """RECIPES in the prototype's shape; ``jain`` overrides the per-recipe Jain flag (the
    backend derives it from ingredients)."""
    out = []
    for r in RECIPES_JSON:
        out.append(
            {
                "id": r["id"],
                "name": r["name"],
                "mins": r["mins"],
                "meals": "".join(_SLOT_KEY[s] for s in r["meal_slots"]),
                "diet": r["diet"],
                "jain": (jain or {}).get(r["id"], r["jain_safe_editorial"]),
                "spice": r["spice"],
                "tags": r["tags"],
                "cuisine": r["cuisine"],
                "raw": r,
            }
        )
    return out


def _fit(m: dict[str, Any], r: dict[str, Any]) -> str:
    return proto_fit_for(m, r["raw"], r["jain"])


def _summarize(r: dict[str, Any]) -> dict[str, Any]:
    can = perfect = like = 0
    nos = []
    for m in PROTOTYPE_MEMBERS:
        f = _fit(m, r)
        if f != "no":
            can += 1
        else:
            nos.append(m["name"])
        if f == "fit":
            perfect += 1
        if r["cuisine"] in m["cuisines"]:
            like += 1
    return {"can": can, "score": can * 10 + perfect * 3 + like * 2 - (15 if nos else 0)}


def _ranked(lst: list[dict[str, Any]]) -> list[tuple[dict[str, Any], dict[str, Any]]]:
    pairs = [(r, _summarize(r)) for r in lst]
    # JS sort is stable: b.score - a.score || a.mins - b.mins
    return sorted(pairs, key=lambda p: (-p[1]["score"], p[0]["mins"]))


def constraint_line(show_health: bool = False) -> str:
    """The prototype's constraintLine(). One deliberate deviation: health needs ("low
    sugar") only with ``show_health`` (F-5.3-05, as in engine.ranking and Maharaj)."""
    bits = []
    for m in PROTOTYPE_MEMBERS:
        if m["diet"] == "Jain":
            bits.append(m["name"] + " (Jain)")
        if show_health and "Low sugar" in m["needs"]:
            bits.append(m["name"] + " (low sugar)")
        if m["spice"] == "Kam" and "Kid-friendly" in m["needs"]:
            bits.append(m["name"] + " (kam mirch)")
    return "Dhyaan rakha: " + " · ".join(bits[:3]) if bits else "Sabki pasand dhyaan mein hai"


def reply(q: str, state_slot: str, recipes: list[dict[str, Any]]) -> dict[str, Any]:
    s = q.lower()
    slot = _SLOT_KEY[state_slot]
    explicit = False
    fs: list[Any] = []
    why: list[str] = []
    if re.search(r"nashta|breakfast|subah", s):
        slot, explicit = "b", True
    elif re.search(r"lunch|dopahar", s):
        slot, explicit = "l", True
    elif re.search(r"dinner|raat", s):
        slot, explicit = "d", True

    def tag(t: str, w: str) -> None:
        fs.append(lambda r: t in r["tags"])
        why.append(w)

    if re.search(r"halka|light|bimaar|simple|hal?ka", s):
        tag("light", "halka")
    if re.search(r"protein|gym", s):
        tag("protein", "high protein")
    if re.search(r"guest|mehmaan|mehman|party|special", s):
        tag("special", "mehmaan-worthy")
    if re.search(r"baarish|barish|rain", s):
        tag("rainy", "baarish wala")
    if re.search(r"tiffin|bachch|kid|beti|daughter", s):
        tag("kid", "bachchon ko pasand")
    if re.search(r"jaldi|quick|fast|15|10 min|20 min", s):
        fs.append(lambda r: r["mins"] <= 20)
        why.append("20 min ke andar")
    if re.search(r"paneer", s):
        fs.append(lambda r: "Paneer" in r["name"] or r["id"] == "cheela")
        why.append("paneer wala")
    cmap = {
        "south": "South Indian",
        "gujarat": "Gujarati",
        "punjab": "North Indian",
        "rajasthan": "Rajasthani",
        "bengal": "Bengali",
        "chinese": "Indo-Chinese",
        "maharash": "Maharashtrian",
    }
    for k, c in cmap.items():
        if k in s:
            fs.append(lambda r, c=c: r["cuisine"] == c)
            why.append(c)
    who = None
    for m in PROTOTYPE_MEMBERS:
        if m["name"].lower() in s:
            who = m
    if who is not None:
        w = who
        fs.append(lambda r: _fit(w, r) != "no")
        why.append(who["name"] + " ke hisaab se")
    lst = [r for r in recipes if all(f(r) for f in fs)]
    in_slot = [r for r in lst if slot in r["meals"]]
    if explicit or len(in_slot) >= 2:
        lst = in_slot
    top = _ranked(lst)[:4]
    if not top:
        top = _ranked([r for r in recipes if slot in r["meals"]])[:4]
        text = f"Is combo mein exact match nahi mila. {SLOTS[slot]} ke liye ye sabse kareeb hain:"
    else:
        all_ok = sum(1 for _, sm in top if sm["can"] == len(PROTOTYPE_MEMBERS))
        text = (
            f"{SLOTS[slot]} ke liye {len(top)} options"
            + (" — " + ", ".join(why) if why else "")
            + f".\n{all_ok} mein poora parivaar kha sakta hai. {constraint_line()}."
        )
    follow = (
        ["Protein wala nashta", "Daughter ka tiffin", "Kuch South Indian"]
        if slot == "b"
        else ["Kuch halka", "Baarish special", "Paneer wala kuch", "Dadi ke liye kya?"]
    )
    return {"text": text, "recipes": [r["id"] for r, _ in top], "chips": follow, "slot": slot}
