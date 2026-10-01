"""GET /v1/recommendations: Home pick + 8 tiles from the engine only (no LLM).

Cached per household + request hash for 60 s in the KV store (Redis, or in-memory in
tests/dev). The hash includes each eater's ``updated_at`` and the newest recipe publish time,
so profile edits and catalogue publishes invalidate it.
"""

from __future__ import annotations

import hashlib
import json
from datetime import date, datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Query
from sqlalchemy import func, select

from app.api.catalogue import card_out, household_eaters, parse_ids
from app.api.deps import DB, HouseholdCtx
from app.core.kv import get_kv
from app.engine import Ranked, constraint_line, rank
from app.models import MealSlot, Recipe, RecipeStatus
from app.permissions import Action
from app.schemas import (
    ConstraintLineOut,
    ConstraintOut,
    RecommendationsOut,
    RecoTileOut,
)
from app.services import catalogue_cache, learning
from app.services.catalogue import default_slot, eater_view

router = APIRouter(tags=["recommendations"])

CACHE_TTL_SECONDS = 60
GRID_SIZE = 8


def _tile(item: Ranked, recipes: dict[str, Recipe]) -> RecoTileOut:
    return RecoTileOut(
        recipe=card_out(recipes[item.recipe.id], item.summary), score=round(item.score, 2)
    )


@router.get("/recommendations", response_model=RecommendationsOut)
async def recommendations(
    ctx: HouseholdCtx,
    db: DB,
    slot: MealSlot | None = None,
    date_: Annotated[date | None, Query(alias="date")] = None,
    eaters: Annotated[str | None, Query(description="comma-separated member ids")] = None,
    show_health: bool = False,
) -> RecommendationsOut:
    ctx.require(Action.edit_day_menu)
    tz = ZoneInfo(ctx.household.timezone or "Asia/Kolkata")
    now_local = datetime.now(tz)
    slot_key = slot.value if slot else default_slot(now_local, ctx.household.enabled_slots)
    day = date_ or now_local.date()
    members = await household_eaters(db, ctx.household, parse_ids(eaters))

    catalogue_stamp = (
        await db.execute(
            select(func.max(Recipe.updated_at)).where(Recipe.status == RecipeStatus.published)
        )
    ).scalar_one_or_none()
    key_src = json.dumps(
        {
            "slot": slot_key,
            "date": day.isoformat(),
            "eaters": [[str(m.id), m.updated_at.isoformat()] for m in members],
            "catalogue": catalogue_stamp.isoformat() if catalogue_stamp else None,
            "health": show_health,
            # Ratings, served history and stock change the ranking (Phases 6-7).
            "signals": await learning.signal_stamp(db, ctx.household.id),
        },
        sort_keys=True,
    )
    cache_key = f"reco:{ctx.household.id}:{hashlib.sha256(key_src.encode()).hexdigest()[:32]}"
    kv = get_kv()
    hit = await kv.get(cache_key)
    if hit is not None:
        out = RecommendationsOut.model_validate_json(hit)
        out.cached = True
        return out

    snap = await catalogue_cache.published(db)  # in-process, reloaded on change (M4)
    by_id = snap.by_id
    views = [eater_view(m, day=day) for m in members]
    # F-6-05: learning (ratings), repetition (served history) and stock terms.
    ranking = rank(
        snap.views,
        views,
        await learning.score_context(db, ctx.household, day),
        slot_key,
        grid_size=GRID_SIZE,
    )
    items, more = constraint_line(views, show_health=show_health)
    out = RecommendationsOut(
        slot=slot_key,
        date=day,
        eater_ids=[m.id for m in members],
        pick=_tile(ranking.pick, by_id) if ranking.pick else None,
        tiles=[_tile(t, by_id) for t in ranking.tiles],
        constraint_line=ConstraintLineOut(
            items=[ConstraintOut(key=c.key, params=dict(c.params)) for c in items], more=more
        ),
    )
    await kv.set(cache_key, out.model_dump_json(), CACHE_TTL_SECONDS)
    return out
