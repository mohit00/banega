"""Read-only catalogue endpoints: recipes (with per-eater fits), ingredients, staples, config.

Recipes are global, but every recipe response is computed for the caller's household
(its active members, or ``?eaters=`` ids from that household).
"""

from __future__ import annotations

import base64
import uuid
from collections.abc import Sequence
from typing import Annotated, Any

from fastapi import APIRouter, Query
from sqlalchemy import String, and_, cast, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import DB, Auth, HouseholdCtx
from app.core.errors import AppError, NotFound
from app.core.security import utcnow
from app.engine import EaterView, Summary, summarize
from app.models import (
    AppConfig,
    Household,
    Ingredient,
    Member,
    Recipe,
    RecipeIngredient,
    RecipeStatus,
    Staple,
)
from app.schemas import (
    FitOut,
    IngredientOut,
    ItemsOut,
    Page,
    RecipeCardOut,
    RecipeDetailOut,
    RecipeFlagsOut,
    ScaledIngredientOut,
    StapleOut,
    SummaryOut,
)
from app.services.catalogue import (
    diet_mark,
    eater_view,
    recipe_view,
    scale_factor,
    scale_qty,
)
from app.services.menus import local_today

router = APIRouter(tags=["catalogue"])

MAX_SERVINGS = 60


# ---- helpers shared with recommendations -----------------------------------------------


def parse_ids(raw: str | None) -> list[uuid.UUID] | None:
    if not raw:
        return None
    try:
        return [uuid.UUID(x.strip()) for x in raw.split(",") if x.strip()]
    except ValueError as exc:
        raise AppError("invalid_eaters", "Invalid eater ids.", "Eater ids galat hain.") from exc


async def household_eaters(
    db: AsyncSession, household: Household, ids: Sequence[uuid.UUID] | None
) -> list[Member]:
    """Active members of the household, optionally narrowed to ``ids`` (404 on foreign ids)."""
    stmt = select(Member).where(Member.household_id == household.id, Member.archived_at.is_(None))
    members = list((await db.execute(stmt.order_by(Member.created_at, Member.id))).scalars())
    if ids is None:
        return members
    by_id = {m.id: m for m in members}
    missing = [i for i in ids if i not in by_id]
    if missing:
        raise NotFound()
    return [by_id[i] for i in dict.fromkeys(ids)]


def flags_out(r: Recipe) -> RecipeFlagsOut:
    return RecipeFlagsOut(
        is_veg=r.is_veg,
        has_egg=r.has_egg,
        has_nonveg=r.has_nonveg,
        jain_safe=r.jain_safe,
        no_onion_garlic=r.no_onion_garlic,
        dairy_free=r.dairy_free,
        gluten_free=r.gluten_free,
        allergens=list(r.allergens or []),
    )


def summary_out(s: Summary) -> SummaryOut:
    return SummaryOut(
        badge=s.badge,
        label_key=s.label_key,
        label_params=dict(s.label_params),
        note_key=s.note_key,
        note_params=dict(s.note_params),
        can=s.can,
        perfect=s.perfect,
        n=s.n,
    )


def card_out(r: Recipe, summary: Summary | None = None) -> RecipeCardOut:
    return RecipeCardOut(
        id=r.id,
        slug=r.slug,
        name=r.name,
        name_hi=r.name_hi,
        sub=r.sub,
        cuisine=r.cuisine,
        dish_category=str(r.dish_category),
        meal_slots=list(r.meal_slots or []),
        mins=r.mins,
        spice=r.spice,
        tags=list(r.tags or []),
        colour=r.colour,
        image_url=r.image_url,
        mark=diet_mark(r),
        flags=flags_out(r),
        summary=summary_out(summary) if summary is not None else None,
    )


def published_recipes() -> Any:
    return (
        select(Recipe)
        .where(Recipe.status == RecipeStatus.published)
        .options(selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient))
    )


def _encode_cursor(r: Recipe) -> str:
    return base64.urlsafe_b64encode(f"{r.name}|{r.id}".encode()).decode()


def _decode_cursor(cursor: str) -> tuple[str, uuid.UUID]:
    try:
        name, rid = base64.urlsafe_b64decode(cursor.encode()).decode().rsplit("|", 1)
        return name, uuid.UUID(rid)
    except (ValueError, UnicodeDecodeError) as exc:
        raise AppError("invalid_cursor", "Invalid cursor.", "Cursor galat hai.") from exc


# ---- recipes ----------------------------------------------------------------------------


@router.get("/recipes", response_model=Page[RecipeCardOut])
async def list_recipes(
    ctx: HouseholdCtx,
    db: DB,
    slot: str | None = None,
    q: Annotated[str | None, Query(max_length=80)] = None,
    eaters: Annotated[str | None, Query(description="comma-separated member ids")] = None,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> Page[RecipeCardOut]:
    """Published recipes (A-Z), each with the household badge for the eaters."""
    stmt = published_recipes()
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(
            or_(Recipe.name.ilike(like), Recipe.sub.ilike(like), Recipe.cuisine.ilike(like))
        )
    if cursor:
        name, rid = _decode_cursor(cursor)
        stmt = stmt.where(or_(Recipe.name > name, and_(Recipe.name == name, Recipe.id > rid)))
    # The slot filter runs in Python: meal_slots is JSON and the catalogue is small.
    rows = list((await db.execute(stmt.order_by(Recipe.name, Recipe.id))).scalars())
    if slot:
        rows = [r for r in rows if slot in (r.meal_slots or [])]
    page, more = rows[:limit], len(rows) > limit
    today = local_today(ctx.household, utcnow())
    members = await household_eaters(db, ctx.household, parse_ids(eaters))
    views = [eater_view(m, day=today) for m in members]
    items = [card_out(r, summarize(views, recipe_view(r))) for r in page]
    return Page[RecipeCardOut](
        items=items, next_cursor=_encode_cursor(page[-1]) if more and page else None
    )


@router.get("/recipes/{recipe_id}", response_model=RecipeDetailOut)
async def get_recipe(
    recipe_id: uuid.UUID,
    ctx: HouseholdCtx,
    db: DB,
    servings: Annotated[int | None, Query(ge=1, le=MAX_SERVINGS)] = None,
    eaters: Annotated[str | None, Query(description="comma-separated member ids")] = None,
) -> RecipeDetailOut:
    recipe = (
        await db.execute(published_recipes().where(Recipe.id == recipe_id))
    ).scalar_one_or_none()
    if recipe is None:
        raise NotFound()
    members = await household_eaters(db, ctx.household, parse_ids(eaters))
    wanted = servings or ctx.household.default_servings or recipe.base_servings
    return recipe_detail(recipe, members, wanted)


def recipe_detail(recipe: Recipe, members: Sequence[Member], wanted: int) -> RecipeDetailOut:
    """Recipe detail scaled to ``wanted`` servings, with fits for ``members``.
    Also serves cook mode (``/tickets/{id}/recipes/{recipe_id}``)."""
    views: list[EaterView] = [eater_view(m) for m in members]
    summary = summarize(views, recipe_view(recipe))
    scale = scale_factor(wanted, recipe.base_servings)
    ingredients = [
        ScaledIngredientOut(
            ingredient_id=ri.ingredient_id,
            slug=ri.ingredient.slug,
            name_en=ri.ingredient.name_en,
            name_hi=ri.ingredient.name_hi,
            display_text=ri.display_text,
            qty=ri.qty,
            unit=ri.unit,
            scaled_qty=None
            if scale.batch_suggested
            else scale_qty(ri.qty, ri.unit, ri.ingredient.scaling_rule, scale.factor),
            scaling_rule=ri.ingredient.scaling_rule,
            is_main=ri.is_main,
            optional=ri.optional,
            trackable=ri.ingredient.trackable,
            sort_order=ri.sort_order,
            allergens=list(ri.ingredient.allergens or []),
        )
        for ri in recipe.ingredients
    ]
    card = card_out(recipe, summary)
    return RecipeDetailOut(
        **card.model_dump(),
        video_url=recipe.video_url,
        base_servings=recipe.base_servings,
        servings=wanted,
        scale_factor=round(scale.factor, 3),
        batch_suggested=scale.batch_suggested,
        steps_en=list(recipe.steps_en or []),
        steps_hi=list(recipe.steps_hi or []),
        vrat_ok=recipe.vrat_ok,
        ingredients=ingredients,
        fits=[
            FitOut(
                eater_id=f.eater_id,
                name=f.name,
                status=f.fit.status.value,
                reason_key=f.fit.reason_key,
                reason_params=dict(f.fit.reason_params),
            )
            for f in summary.fits
        ],
        allergy_notice=any(m.allergens for m in members),
    )


# ---- ingredients, staples, config ------------------------------------------------------


@router.get("/ingredients", response_model=Page[IngredientOut])
async def list_ingredients(
    auth: Auth,
    db: DB,
    q: Annotated[str | None, Query(max_length=80)] = None,
    cursor: str | None = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> Page[IngredientOut]:
    """Active ingredients A-Z; ``q`` matches English/Hindi names, slug and aliases."""
    stmt = select(Ingredient).where(Ingredient.is_active)
    if q:
        like = f"%{q.strip().lower()}%"
        stmt = stmt.where(
            or_(
                Ingredient.name_en.ilike(like),
                Ingredient.name_hi.ilike(like),
                Ingredient.slug.ilike(like),
                cast(Ingredient.aliases, String).ilike(like),
            )
        )
    if cursor:
        name, iid = _decode_cursor(cursor)
        stmt = stmt.where(
            or_(Ingredient.name_en > name, and_(Ingredient.name_en == name, Ingredient.id > iid))
        )
    rows = list(
        (
            await db.execute(stmt.order_by(Ingredient.name_en, Ingredient.id).limit(limit + 1))
        ).scalars()
    )
    next_cursor = None
    if len(rows) > limit:
        last = rows[limit - 1]
        next_cursor = base64.urlsafe_b64encode(f"{last.name_en}|{last.id}".encode()).decode()
    return Page[IngredientOut](
        items=[IngredientOut.model_validate(i) for i in rows[:limit]], next_cursor=next_cursor
    )


@router.get("/staples", response_model=ItemsOut[StapleOut])
async def list_staples(auth: Auth, db: DB) -> ItemsOut[StapleOut]:
    rows = (await db.execute(select(Staple).order_by(Staple.sort_order))).unique().scalars()
    return ItemsOut[StapleOut](items=[StapleOut.model_validate(s) for s in rows])


@router.get("/config", response_model=dict[str, Any])
async def get_config(auth: Auth, db: DB) -> dict[str, Any]:
    """Admin-editable app config: quick_asks, follow_ups, ticker_asks, cuisines, needs, ..."""
    rows = (await db.execute(select(AppConfig).order_by(AppConfig.key))).scalars()
    return {row.key: row.value for row in rows}
