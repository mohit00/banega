"""ParsedQuery: the structured intent every parser returns (also the LLM output schema)."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Slot = Literal["nashta", "lunch", "dinner"]
Lang = Literal["en", "hi", "hinglish"]
DietFilter = Literal["veg", "jain", "eggetarian", "no_onion_garlic"]
GuestDiet = Literal["veg", "jain", "eggetarian", "non_veg"]
SpiceWish = Literal["kam", "teekha"]

# Recipe tags the chat can filter on, in the prototype's why-order.
TAG_ORDER: tuple[str, ...] = ("light", "protein", "special", "rainy", "kid", "lowOil", "lowSugar")
# The prototype's cuisine map order (south, gujarat, punjab, rajasthan, bengal, chinese,
# maharash).
CUISINE_ORDER: tuple[str, ...] = (
    "South Indian",
    "Gujarati",
    "North Indian",
    "Rajasthani",
    "Bengali",
    "Indo-Chinese",
    "Maharashtrian",
)


class Guests(BaseModel):
    adults: int | None = None
    kids: int | None = None
    diet: GuestDiet | None = None


class ParsedQuery(BaseModel):
    """Filters for one chat message. ``slot`` is always resolved; ``explicit_slot`` says
    whether the user named it (explicit slots are hard filters)."""

    slot: Slot = "lunch"
    explicit_slot: bool = False
    tags: list[str] = Field(default_factory=list)
    max_mins: int | None = None
    # Canonical ingredient-group keys (see parse.INGREDIENT_GROUPS), e.g. "paneer", "fish".
    ingredients_include: list[str] = Field(default_factory=list)
    ingredients_exclude: list[str] = Field(default_factory=list)
    cuisines: list[str] = Field(default_factory=list)
    # A household member's name exactly as stored (resolved locally, never guessed).
    member_focus: str | None = None
    guests: Guests | None = None
    diet: DietFilter | None = None
    spice: SpiceWish | None = None
    mood: str | None = None
    # None = not detected with confidence: the reply uses the user's language (F-7-07).
    language: Lang | None = None
    off_topic: bool = False
    # Hinglish fragments for the reply's first line ("halka", "20 min ke andar", ...).
    why: list[str] = Field(default_factory=list)
    source: Literal["rule", "llm"] = "rule"

    def canonical(self) -> ParsedQuery:
        """Dedupe and sort lists into the prototype order (stable texts, cache keys)."""
        tags = [t for t in TAG_ORDER if t in set(self.tags)]
        cuisines = [c for c in CUISINE_ORDER if c in set(self.cuisines)]
        return self.model_copy(
            update={
                "tags": tags,
                "cuisines": cuisines,
                "ingredients_include": sorted(set(self.ingredients_include)),
                "ingredients_exclude": sorted(set(self.ingredients_exclude)),
            }
        )
