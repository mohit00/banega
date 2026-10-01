"""Global recipe catalogue (Phase 2): ingredients, staples, recipes, substitutions, app config.

Catalogue rows are not household-scoped: every household reads the same published recipes.
Diet and allergen flags on a recipe are **derived** from its ingredients on save
(:mod:`app.services.tagging`, F-5.2-01a / F-6-06) and are never hand-set.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    false,
    true,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, JSONType, Timestamped, UTCDateTime, UUIDPk, str_enum
from app.models.enums import (
    DishCategory,
    IngredientCategory,
    RecipeStatus,
    ScalingRule,
)

EMBEDDING_DIM = 1024

# pgvector on Postgres; a JSON list on SQLite (tests) so the schema stays comparable.
EmbeddingType = JSON().with_variant(Vector(EMBEDDING_DIM), "postgresql")

DEFAULT_INGREDIENT_FLAGS: dict[str, Any] = {
    "root_veg": False,
    "onion_garlic": False,
    "meat_type": "none",
    "egg": False,
    "dairy": False,
    "gluten": False,
    "honey": False,
    "mushroom": False,
    "fermented": False,
}


def default_flags() -> dict[str, Any]:
    return dict(DEFAULT_INGREDIENT_FLAGS)


class Ingredient(UUIDPk, Timestamped, Base):
    """Global ingredient (~600-800 at launch, F-5.8-01). Staples are the trackable subset."""

    __tablename__ = "ingredients"

    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    name_en: Mapped[str] = mapped_column(String(120), nullable=False)
    name_hi: Mapped[str | None] = mapped_column(String(120))
    # Hinglish / regional spellings used by the importer and search ("pyaz", "kanda").
    aliases: Mapped[list[str]] = mapped_column(JSONType, default=list)
    category: Mapped[IngredientCategory] = mapped_column(
        str_enum(IngredientCategory, "ingredient_category"),
        default=IngredientCategory.other,
        nullable=False,
    )
    allergens: Mapped[list[str]] = mapped_column(JSONType, default=list)
    # {root_veg, onion_garlic, meat_type, egg, dairy, gluten, honey, mushroom, fermented}
    flags: Mapped[dict[str, Any]] = mapped_column(JSONType, default=default_flags)
    scaling_rule: Mapped[ScalingRule] = mapped_column(
        str_enum(ScalingRule, "scaling_rule"), default=ScalingRule.linear, nullable=False
    )
    trackable: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    purchase_unit: Mapped[str | None] = mapped_column(String(16))
    pack_size: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    perishable: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())

    def __str__(self) -> str:
        return self.name_en


class Staple(UUIDPk, Timestamped, Base):
    """Pantry-tracked ingredient (FR-S3): shows In / Low / Out in stock."""

    __tablename__ = "staples"

    ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ingredients.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    low_threshold: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    default_pack_qty: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    ingredient: Mapped[Ingredient] = relationship(lazy="joined")

    def __str__(self) -> str:
        return f"Staple: {self.ingredient.name_en}" if self.ingredient else "Staple"


class Recipe(UUIDPk, Timestamped, Base):
    __tablename__ = "recipes"
    __table_args__ = (
        CheckConstraint("spice BETWEEN 1 AND 3", name="spice_range"),
        CheckConstraint("base_servings >= 1", name="base_servings_positive"),
    )

    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    name_hi: Mapped[str | None] = mapped_column(String(120))
    sub: Mapped[str | None] = mapped_column(String(200))
    dish_category: Mapped[DishCategory] = mapped_column(
        str_enum(DishCategory, "dish_category"), default=DishCategory.other, nullable=False
    )
    # Variants of one dish (e.g. Jain / regular) share a group id.
    dish_group_id: Mapped[uuid.UUID | None] = mapped_column(index=True)
    cuisine: Mapped[str | None] = mapped_column(String(40))
    meal_slots: Mapped[list[str]] = mapped_column(JSONType, default=list)
    mins: Mapped[int] = mapped_column(Integer, default=30, server_default="30")
    spice: Mapped[int] = mapped_column(Integer, default=2, server_default="2")
    tags: Mapped[list[str]] = mapped_column(JSONType, default=list)
    colour: Mapped[str | None] = mapped_column(String(16))
    image_url: Mapped[str | None] = mapped_column(String(512))
    video_url: Mapped[str | None] = mapped_column(String(512))
    base_servings: Mapped[int] = mapped_column(Integer, default=4, server_default="4")
    steps_en: Mapped[list[str]] = mapped_column(JSONType, default=list)
    steps_hi: Mapped[list[str]] = mapped_column(JSONType, default=list)
    vrat_ok: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    status: Mapped[RecipeStatus] = mapped_column(
        str_enum(RecipeStatus, "recipe_status"),
        default=RecipeStatus.draft,
        nullable=False,
        index=True,
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    published_at: Mapped[datetime | None] = mapped_column(UTCDateTime())

    # ---- editorial claims (checked against the derived flags) ----
    editorial_jain_safe: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default=false()
    )
    # veg | egg | non_veg as the editor entered it (prototype `diet`), or null.
    editorial_diet: Mapped[str | None] = mapped_column(String(16))

    # ---- derived on save from RecipeIngredient + Ingredient.flags (never hand-set) ----
    is_veg: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    has_egg: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    has_nonveg: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    # Meat types present (chicken, mutton, fish, ...): pescatarian / beef / pork rules.
    meat_types: Mapped[list[str]] = mapped_column(JSONType, default=list)
    jain_safe: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    no_onion_garlic: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    has_root_veg: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    dairy_free: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    gluten_free: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    allergens: Mapped[list[str]] = mapped_column(JSONType, default=list)
    policy_violations: Mapped[list[dict[str, Any]]] = mapped_column(JSONType, default=list)

    embedding: Mapped[list[float] | None] = mapped_column(EmbeddingType, nullable=True)

    ingredients: Mapped[list[RecipeIngredient]] = relationship(
        back_populates="recipe",
        cascade="all, delete-orphan",
        order_by="RecipeIngredient.sort_order",
        lazy="selectin",
    )

    def __str__(self) -> str:
        return self.name


class RecipeIngredient(UUIDPk, Base):
    __tablename__ = "recipe_ingredients"

    recipe_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("recipes.id", ondelete="CASCADE"), index=True, nullable=False
    )
    ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ingredients.id", ondelete="RESTRICT"), index=True, nullable=False
    )
    qty: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(16))
    # The editor's free text, e.g. "Mota poha 2 cup". Rows parsed from one text line share
    # the same sort_order and display_text ("Adrak-lahsun" -> ginger + garlic).
    display_text: Mapped[str | None] = mapped_column(String(200))
    is_main: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    optional: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    recipe: Mapped[Recipe] = relationship(back_populates="ingredients")
    ingredient: Mapped[Ingredient] = relationship(lazy="joined")

    def __str__(self) -> str:
        return self.display_text or (self.ingredient.name_en if self.ingredient else "?")


class SubstitutionRule(UUIDPk, Timestamped, Base):
    __tablename__ = "substitution_rules"
    __table_args__ = (UniqueConstraint("from_ingredient_id", "to_ingredient_id", "cuisine_scope"),)

    from_ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ingredients.id", ondelete="CASCADE"), index=True, nullable=False
    )
    to_ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ingredients.id", ondelete="CASCADE"), index=True, nullable=False
    )
    ratio: Mapped[Decimal] = mapped_column(Numeric(6, 3), default=Decimal("1"))
    note_en: Mapped[str | None] = mapped_column(Text)
    note_hi: Mapped[str | None] = mapped_column(Text)
    cuisine_scope: Mapped[str | None] = mapped_column(String(40))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())

    from_ingredient: Mapped[Ingredient] = relationship(foreign_keys=[from_ingredient_id])
    to_ingredient: Mapped[Ingredient] = relationship(foreign_keys=[to_ingredient_id])


class AppConfig(Timestamped, Base):
    """Editable app config: quick_asks, follow_ups, ticker_asks, cuisines, needs, slots, ..."""

    __tablename__ = "app_config"

    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[Any] = mapped_column(JSONType, nullable=False)

    def __str__(self) -> str:
        return self.key
