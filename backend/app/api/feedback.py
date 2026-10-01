"""Ratings summary and the weekly insights (contract Phase 7)."""

from __future__ import annotations

import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Query

from app.api.deps import DB, HouseholdCtx
from app.core.errors import Forbidden
from app.schemas_pantry import RatingSummaryOut, WeeklyInsightsOut
from app.services import insights as insights_svc
from app.services import ratings as rating_svc

router = APIRouter(tags=["ratings"])


@router.get("/ratings/summary", response_model=list[RatingSummaryOut])
async def ratings_summary(
    ctx: HouseholdCtx, db: DB, recipe_id: uuid.UUID | None = None
) -> list[RatingSummaryOut]:
    """Per recipe: average and count; ``members`` lists only the ratings the caller may see
    by name (a hired cook gets the aggregate unless ``show_names_to_cook``)."""
    rows = await rating_svc.summary(db, ctx.household, ctx.actor, recipe_id=recipe_id)
    return [RatingSummaryOut.model_validate(r) for r in rows]


@router.get("/insights/weekly", response_model=WeeklyInsightsOut)
async def weekly_insights(
    ctx: HouseholdCtx,
    db: DB,
    end: Annotated[date | None, Query(description="last day of the 7-day window")] = None,
) -> WeeklyInsightsOut:
    if not (ctx.actor.is_admin or ctx.actor.is_member):
        raise Forbidden()
    return WeeklyInsightsOut.model_validate(await insights_svc.weekly(db, ctx.household, end=end))
