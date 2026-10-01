"""Learning signals for the engine (F-6-05, F-5.10-02, FR-F5/F6): the ``ScoreContext`` that
``/recommendations``, Maharaj chat and the out-of-stock ladder rank with.

- ``ratings``: per (member, recipe) average. Scores are 1..3 (bura | theek | bahut accha);
  the engine thresholds are on a 1..5 scale, so 1 -> 1, 2 -> 3, 3 -> 5. A dislike (<= 2 on
  the 1..5 scale) counts from the last 30 days, a like (>= 4) from the last 90 days.
- ``last_served``: the latest household-local date each recipe was served (``ServedHistory``)
  -> the 3-day repetition penalty.
- ``out_of_stock``: ids of tracked ingredients that are Out. ``None`` while the
  household has never recorded a level (no StockItem rows): stock unknown, no bonus/penalty.

Only tickets that reached ``completed`` count: ratings need a completed ticket and served
history is written on completion (never for ``not_confirmed`` or ``cancelled``).
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.engine import ScoreContext
from app.models import (
    Household,
    Ingredient,
    Rating,
    ServedHistory,
    StockItem,
    StockLevel,
    Ticket,
    TicketStatus,
)
from app.models.base import utcnow

LIKE_WINDOW_DAYS = 90
DISLIKE_WINDOW_DAYS = 30
HISTORY_DAYS = 14


def to_five(score: float) -> float:
    """1..3 -> 1..5 (1 -> 1, 2 -> 3, 3 -> 5)."""
    return 2.0 * score - 1.0


async def rating_averages(
    db: AsyncSession, household_id: uuid.UUID, now: datetime
) -> dict[tuple[str, str], float]:
    since = now - timedelta(days=LIKE_WINDOW_DAYS)
    rows = (
        await db.execute(
            select(Rating.member_id, Rating.recipe_id, Rating.score, Rating.updated_at)
            .join(Ticket, Ticket.id == Rating.ticket_id)
            .where(
                Rating.household_id == household_id,
                Ticket.status == TicketStatus.completed,
                Rating.updated_at >= since,
            )
        )
    ).all()
    likes: dict[tuple[str, str], list[int]] = defaultdict(list)
    recent: dict[tuple[str, str], list[int]] = defaultdict(list)
    dislike_since = now - timedelta(days=DISLIKE_WINDOW_DAYS)
    for member_id, recipe_id, score, at in rows:
        key = (str(member_id), str(recipe_id))
        likes[key].append(score)
        if at >= dislike_since:
            recent[key].append(score)
    out: dict[tuple[str, str], float] = {}
    for key, scores in likes.items():
        near = recent.get(key)
        if near and to_five(sum(near) / len(near)) <= 2.0:
            out[key] = to_five(sum(near) / len(near))
        else:
            avg = to_five(sum(scores) / len(scores))
            if avg > 2.0:  # an old dislike (> 30 days) no longer pushes a recipe down
                out[key] = avg
    return out


async def last_served(db: AsyncSession, household: Household, now: datetime) -> dict[str, date]:
    tz = ZoneInfo(household.timezone or "Asia/Kolkata")
    rows = (
        await db.execute(
            select(ServedHistory.recipe_id, func.max(ServedHistory.served_at))
            .where(
                ServedHistory.household_id == household.id,
                ServedHistory.served_at >= now - timedelta(days=HISTORY_DAYS),
            )
            .group_by(ServedHistory.recipe_id)
        )
    ).all()
    out: dict[str, date] = {}
    for recipe_id, at in rows:
        if at is None:
            continue
        if at.tzinfo is None:  # SQLite aggregate returns a naive value
            from datetime import UTC

            at = at.replace(tzinfo=UTC)
        out[str(recipe_id)] = at.astimezone(tz).date()
    return out


async def out_of_stock(db: AsyncSession, household_id: uuid.UUID) -> frozenset[str] | None:
    rows = (
        await db.execute(
            select(StockItem.level, Ingredient.id, Ingredient.slug)
            .join(Ingredient, Ingredient.id == StockItem.ingredient_id)
            .where(StockItem.household_id == household_id)
        )
    ).all()
    if not rows:
        return None
    # Ids only: RecipeView.tracked_ingredients holds both the id and the slug of each item, so
    # matching on one ref counts every Out ingredient once (-5 each, F-6-05).
    return frozenset(str(iid) for level, iid, _slug in rows if level == StockLevel.out)


async def score_context(
    db: AsyncSession,
    household: Household,
    today: date,
    *,
    now: datetime | None = None,
) -> ScoreContext:
    now = now or utcnow()
    return ScoreContext(
        today=today,
        ratings=await rating_averages(db, household.id, now),
        last_served=await last_served(db, household, now),
        out_of_stock=await out_of_stock(db, household.id),
    )


async def signal_stamp(db: AsyncSession, household_id: uuid.UUID) -> str:
    """Changes whenever a learning signal changes (recommendation cache key)."""
    parts = []
    for col, where in (
        (func.max(Rating.updated_at), Rating.household_id == household_id),
        (func.max(ServedHistory.served_at), ServedHistory.household_id == household_id),
        (func.max(StockItem.updated_at), StockItem.household_id == household_id),
    ):
        value = (await db.execute(select(col).where(where))).scalar_one_or_none()
        parts.append(str(value) if value is not None else "-")
    return "|".join(parts)
