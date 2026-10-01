"""Reply fragments in Hinglish (default), English and Hindi (Devanagari).

The Hinglish strings are the prototype's (design/prototype_logic.js reply()):
"halka", "high protein", "mehmaan-worthy", "baarish wala", "bachchon ko pasand",
"20 min ke andar", "paneer wala", the cuisine name, "{name} ke hisaab se".
"""

from __future__ import annotations

from app.services.maharaj.types import Lang, ParsedQuery

TAG_TEXT: dict[str, dict[str, str]] = {
    "light": {"hinglish": "halka", "en": "light", "hi": "हल्का"},
    "protein": {"hinglish": "high protein", "en": "high protein", "hi": "हाई प्रोटीन"},
    "special": {"hinglish": "mehmaan-worthy", "en": "guest-worthy", "hi": "मेहमानों के लायक"},
    "rainy": {"hinglish": "baarish wala", "en": "rainy-day", "hi": "बारिश वाला"},
    "kid": {"hinglish": "bachchon ko pasand", "en": "kid-friendly", "hi": "बच्चों को पसंद"},
    "lowOil": {"hinglish": "kam tel", "en": "low oil", "hi": "कम तेल"},
    "lowSugar": {"hinglish": "kam meetha", "en": "low sugar", "hi": "कम मीठा"},
}
SPICE_TEXT: dict[str, dict[str, str]] = {
    "teekha": {"hinglish": "teekha", "en": "spicy", "hi": "तीखा"},
    "kam": {"hinglish": "kam mirch", "en": "mild", "hi": "कम मिर्च"},
}
DIET_TEXT: dict[str, dict[str, str]] = {
    "veg": {"hinglish": "veg", "en": "veg", "hi": "शाकाहारी"},
    "jain": {"hinglish": "Jain", "en": "Jain", "hi": "जैन"},
    "eggetarian": {"hinglish": "bina non-veg", "en": "no meat", "hi": "बिना नॉन-वेज"},
    "no_onion_garlic": {
        "hinglish": "bina pyaaz-lahsun",
        "en": "no onion-garlic",
        "hi": "बिना प्याज़-लहसुन",
    },
}
CUISINE_HI: dict[str, str] = {
    "South Indian": "साउथ इंडियन",
    "Gujarati": "गुजराती",
    "North Indian": "नॉर्थ इंडियन",
    "Rajasthani": "राजस्थानी",
    "Bengali": "बंगाली",
    "Indo-Chinese": "इंडो-चाइनीज़",
    "Maharashtrian": "महाराष्ट्रीयन",
}
# Ingredient-group display names: (hinglish, en, hi).
INGREDIENT_TEXT: dict[str, tuple[str, str, str]] = {
    "paneer": ("paneer", "paneer", "पनीर"),
    "potato": ("aloo", "potato", "आलू"),
    "okra": ("bhindi", "okra", "भिंडी"),
    "spinach": ("palak", "spinach", "पालक"),
    "egg": ("anda", "egg", "अंडा"),
    "chicken": ("chicken", "chicken", "चिकन"),
    "mutton": ("mutton", "mutton", "मटन"),
    "fish": ("machli", "fish", "मछली"),
    "prawns": ("jhinga", "prawns", "झींगा"),
    "rajma": ("rajma", "rajma", "राजमा"),
    "chana": ("chana", "chickpeas", "चना"),
    "dal": ("dal", "dal", "दाल"),
    "cauliflower": ("gobhi", "cauliflower", "गोभी"),
    "bottle-gourd": ("lauki", "bottle gourd", "लौकी"),
    "mushroom": ("mushroom", "mushroom", "मशरूम"),
    "besan": ("besan", "gram flour", "बेसन"),
    "poha": ("poha", "poha", "पोहा"),
    "rice": ("chawal", "rice", "चावल"),
    "onion": ("pyaaz", "onion", "प्याज़"),
    "garlic": ("lahsun", "garlic", "लहसुन"),
    "tomato": ("tamatar", "tomato", "टमाटर"),
    "curd": ("dahi", "curd", "दही"),
    "maida": ("maida", "maida", "मैदा"),
    "peanut": ("moongphali", "peanut", "मूंगफली"),
}
_LANG_IDX = {"hinglish": 0, "en": 1, "hi": 2}

SLOT_LABELS: dict[str, dict[str, str]] = {
    "nashta": {"hinglish": "Nashta", "en": "breakfast", "hi": "नाश्ते"},
    "lunch": {"hinglish": "Lunch", "en": "lunch", "hi": "लंच"},
    "dinner": {"hinglish": "Dinner", "en": "dinner", "hi": "डिनर"},
}

# Filter groups in the order their fragments appear (the prototype's why-order).
GROUP_ORDER: tuple[str, ...] = (
    "tags",
    "max_mins",
    "ingredients",
    "exclude",
    "diet",
    "cuisine",
    "member",
)


def ingredient_name(key: str, lang: Lang) -> str:
    names = INGREDIENT_TEXT.get(key)
    return names[_LANG_IDX[lang]] if names else key.replace("-", " ")


def fragments(q: ParsedQuery, lang: Lang) -> list[tuple[str, str]]:
    """(group, text) pairs in the prototype's order."""
    out: list[tuple[str, str]] = []
    for t in q.tags:
        if t in TAG_TEXT:
            out.append(("tags", TAG_TEXT[t][lang]))
    if q.spice:
        out.append(("tags", SPICE_TEXT[q.spice][lang]))
    if q.max_mins is not None:
        out.append(
            (
                "max_mins",
                {
                    "hinglish": f"{q.max_mins} min ke andar",
                    "en": f"under {q.max_mins} min",
                    "hi": f"{q.max_mins} मिनट के अंदर",
                }[lang],
            )
        )
    for key in q.ingredients_include:
        name = ingredient_name(key, lang)
        out.append(
            (
                "ingredients",
                {"hinglish": f"{name} wala", "en": f"with {name}", "hi": f"{name} वाला"}[lang],
            )
        )
    for key in q.ingredients_exclude:
        name = ingredient_name(key, lang)
        out.append(
            (
                "exclude",
                {"hinglish": f"bina {name}", "en": f"no {name}", "hi": f"बिना {name}"}[lang],
            )
        )
    diet = q.diet or (q.guests.diet if q.guests and q.guests.diet != "non_veg" else None)
    if diet:
        out.append(("diet", DIET_TEXT[diet][lang]))
    for c in q.cuisines:
        out.append(("cuisine", CUISINE_HI.get(c, c) if lang == "hi" else c))
    if q.member_focus:
        name = q.member_focus
        out.append(
            (
                "member",
                {
                    "hinglish": f"{name} ke hisaab se",
                    "en": f"for {name}",
                    "hi": f"{name} के हिसाब से",
                }[lang],
            )
        )
    return out


def why(q: ParsedQuery, lang: Lang = "hinglish") -> list[str]:
    return [text for _, text in fragments(q, lang)]


def dropped_text(q: ParsedQuery, dropped: list[str], lang: Lang) -> list[str]:
    return [text for group, text in fragments(q, lang) if group in dropped]
