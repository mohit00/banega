"""Editorial workflow: Draft -> Reviewed -> Published, gated by the Jain/diet policy check."""

from __future__ import annotations

import uuid
from collections.abc import Sequence

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.security import utcnow
from app.models import Recipe, RecipeIngredient, RecipeStatus
from app.services.tagging import apply_derived


class PublishError(Exception):
    def __init__(self, slug: str, reason: str) -> None:
        super().__init__(f"{slug}: {reason}")
        self.slug = slug
        self.reason = reason


async def load_recipes(db: AsyncSession, ids: Sequence[uuid.UUID]) -> list[Recipe]:
    stmt = (
        select(Recipe)
        .where(Recipe.id.in_(list(ids)))
        .options(selectinload(Recipe.ingredients).joinedload(RecipeIngredient.ingredient))
        .execution_options(populate_existing=True)
    )
    return list((await db.execute(stmt)).scalars())


async def recompute(db: AsyncSession, recipe_ids: Sequence[uuid.UUID]) -> list[str]:
    """Re-derive flags for the recipes. Published recipes that now violate the policy are
    moved back to Reviewed (taken out of the app); their slugs are returned."""
    pulled: list[str] = []
    for recipe in await load_recipes(db, recipe_ids):
        apply_derived(recipe)
        if recipe.status == RecipeStatus.published and recipe.policy_violations:
            recipe.status = RecipeStatus.reviewed
            pulled.append(recipe.slug)
    await db.flush()
    return pulled


async def recompute_for_ingredient(db: AsyncSession, ingredient_id: uuid.UUID) -> list[str]:
    ids = (
        await db.execute(
            select(RecipeIngredient.recipe_id)
            .where(RecipeIngredient.ingredient_id == ingredient_id)
            .distinct()
        )
    ).scalars()
    return await recompute(db, list(ids))


def mark_reviewed(recipe: Recipe) -> None:
    if recipe.status == RecipeStatus.published:
        raise PublishError(recipe.slug, "already published; unpublish first")
    recipe.status = RecipeStatus.reviewed


def publish(recipe: Recipe) -> None:
    """Reviewed -> Published. Refuses while policy_violations is non-empty."""
    apply_derived(recipe)
    if recipe.policy_violations:
        codes = ", ".join(str(v.get("code")) for v in recipe.policy_violations)
        raise PublishError(recipe.slug, f"policy violations: {codes}")
    if recipe.status != RecipeStatus.reviewed:
        raise PublishError(recipe.slug, "must be Reviewed before publishing")
    recipe.status = RecipeStatus.published
    recipe.published_at = utcnow()
    recipe.version = (recipe.version or 0) + 1


def unpublish(recipe: Recipe) -> None:
    recipe.status = RecipeStatus.draft
