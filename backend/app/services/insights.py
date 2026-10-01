"""Weekly summary (FR-F4, contract Phase 7 Should): ``GET /v1/insights/weekly``.

- Top dishes: recipes served in the window, by average rating then times served.
- Coverage: completed meals where every eater had at least one dish that was not a "no"
  (read from the dish summaries snapshotted on the ticket).
- On-time: completed tickets with ``completed_at <= due_at + 15 min``.
"""

from __future__ import annotations

import uuid
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Household, Rating, Recipe, Ticket, TicketStatus, TicketStockIssue
from app.models.base import utcnow
from app.services import menus as menu_svc

ON_TIME_GRACE = timedelta(minutes=15)
TOP_N = 5


def uncovered_eaters(dishes: list[dict[str, Any]], eater_ids: set[str]) -> set[str]:
    """Eaters for whom every dish of the meal is a "no" (from the snapshot summaries)."""
    if not dishes:
        return set(eater_ids)
    out = set(eater_ids)
    for d in dishes:
        s = d.get("summary") or {}
        nos = set()
        if s.get("note_key") == "not_for":
            nos = {str(x) for x in (s.get("note_params") or {}).get("eater_ids") or []}
        out &= nos
    return out


async def weekly(
    db: AsyncSession,
    household: Household,
    *,
    end: date | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    now = now or utcnow()
    to_date = end or menu_svc.local_today(household, now)
    from_date = to_date - timedelta(days=6)
    tickets = list(
        (
            await db.execute(
                select(Ticket).where(
                    Ticket.household_id == household.id,
                    Ticket.date >= from_date,
                    Ticket.date <= to_date,
                )
            )
        ).scalars()
    )
    completed = [t for t in tickets if t.status == TicketStatus.completed]
    served: Counter[uuid.UUID] = Counter()
    for t in completed:
        for d in t.dishes or []:
            served[uuid.UUID(str(d["recipe_id"]))] += 1
    ratings = (
        list(
            (
                await db.execute(
                    select(Rating).where(Rating.ticket_id.in_([t.id for t in completed]))
                )
            ).scalars()
        )
        if completed
        else []
    )
    scores: dict[uuid.UUID, list[int]] = defaultdict(list)
    for r in ratings:
        scores[r.recipe_id].append(r.score)
    names = (
        {
            r.id: r.name
            for r in (await db.execute(select(Recipe).where(Recipe.id.in_(list(served))))).scalars()
        }
        if served
        else {}
    )
    top: list[dict[str, Any]] = []
    for rid, n in served.items():
        s = scores.get(rid, [])
        top.append(
            {
                "recipe_id": rid,
                "name": names.get(rid, ""),
                "count": n,
                "avg": round(sum(s) / len(s), 2) if s else None,
                "ratings": len(s),
                "served": n,
            }
        )
    top.sort(key=lambda x: (-(x["avg"] or 0), -x["served"], x["name"]))
    covered = sum(
        1
        for t in completed
        if not uncovered_eaters(
            list(t.dishes or []), {str(e.get("member_id")) for e in t.eaters or []}
        )
    )
    on_time = sum(
        1
        for t in completed
        if t.completed_at is not None and t.completed_at <= t.due_at + ON_TIME_GRACE
    )
    issues = (
        len(
            list(
                (
                    await db.execute(
                        select(TicketStockIssue.id).where(
                            TicketStockIssue.ticket_id.in_([t.id for t in tickets])
                        )
                    )
                ).scalars()
            )
        )
        if tickets
        else 0
    )

    def pct(a: int, b: int) -> float | None:
        return round(100.0 * a / b, 1) if b else None

    return {
        "meals_cooked": len(completed),
        "on_time_pct": pct(on_time, len(completed)) or 0.0,
        "coverage_pct": pct(covered, len(completed)) or 0.0,
        "from_date": from_date,
        "to_date": to_date,
        "tickets": len(tickets),
        "completed": len(completed),
        "cancelled": sum(1 for t in tickets if t.status == TicketStatus.cancelled),
        "top_dishes": top[:TOP_N],
        "coverage": {
            "meals": len(completed),
            "fully_covered": covered,
            "pct": pct(covered, len(completed)),
        },
        "on_time": {
            "completed": len(completed),
            "on_time": on_time,
            "pct": pct(on_time, len(completed)),
        },
        "stock_issues": issues,
    }


def summary_line(data: dict[str, Any]) -> str:
    top = ", ".join(str(d["name"]) for d in data["top_dishes"][:3]) or "-"
    ot = data["on_time"]["pct"]
    return (
        f"{data['completed']} khaane bane. Top: {top}. Samay par: {ot if ot is not None else '-'}%."
    )


WEEKLY_AT = (0, 10)  # Monday, 10:00 household-local


async def send_weekly(db: AsyncSession, now: datetime) -> list[uuid.UUID]:
    """``weekly_summary`` (Should) to the admin, Monday 10:00 local, once per household
    (``notification_marks``), one transaction per household."""
    from datetime import time
    from zoneinfo import ZoneInfo

    from app.services import marks
    from app.services import notifications as notify
    from app.services.sweeps import each

    sent: list[uuid.UUID] = []
    failed: dict[str, int] = {}
    # Monday somewhere on Earth (UTC-12 .. UTC+14)? Otherwise there is nothing to do.
    if not any((now + timedelta(hours=h)).weekday() == WEEKLY_AT[0] for h in range(-12, 15)):
        return sent

    def ids(seen: set[uuid.UUID]) -> Any:
        q = select(Household.id).where(Household.deleted_at.is_(None))
        return (q.where(Household.id.not_in(seen)) if seen else q).order_by(Household.id)

    async def handle(hid: uuid.UUID) -> None:
        h = await db.get(Household, hid)
        if h is None or h.deleted_at is not None:
            return
        tz = ZoneInfo(h.timezone or "Asia/Kolkata")
        local = now.astimezone(tz)
        at = datetime.combine(local.date(), time(WEEKLY_AT[1], 0), tzinfo=tz)
        if local.weekday() != WEEKLY_AT[0] or local < at:
            return
        if await marks.is_marked(db, h.id, "weekly_summary", local.date()):
            return
        data = await weekly(db, h, end=local.date() - timedelta(days=1), now=now)
        if not data["tickets"] or not await marks.claim(db, h.id, "weekly_summary", local.date()):
            return
        await notify.emit(db, "weekly_summary", h, params={"summary": summary_line(data)}, now=now)
        sent.append(h.id)

    # Cheap outside Monday 10:00-24:00 in any timezone: nothing is emitted, marks skip repeats.
    await each(db, "weekly_summary", ids, handle, failed)
    return sent
