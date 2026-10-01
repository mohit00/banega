"""Ticket and duty timers (contract §Worker timers; review H1, M10, primary #4). Each sweep
takes ``now`` so tests drive them with a fake clock; the ARQ cron in ``app.workers.worker``
calls :func:`run_all`.

- ``due_at + 3 h`` and still accepted/cooking/ready -> not_confirmed + "Khaana bana?" to admin.
- not_confirmed for 24 h -> cancelled (no learning, no stock effects).
- new / unassigned and nobody picked it up 24 h after due -> cancelled (``not_picked_up_24h``).
- still new ``no_show_minutes`` (default 90) before due -> one no_show alert to the admin and
  the backup cook (F-5.7-12).
- accepted but not cooking ``at_risk_minutes`` (default 45) before due -> one at_risk alert to
  the admin and the assignee.
- Per-slot thresholds: ``Household.slot_defaults[slot].no_show_minutes`` / ``.at_risk_minutes``.
- Alerts only look TICKET_ALERT_LOOKBACK_HOURS back: after an outage the worker does not
  alert on history.
- 20:00 household-local -> tomorrow's tickets to each assignee, once per household per local
  day (``notification_marks``).
- off_duty_until passed -> cook back on duty; tickets do not move back (F-5.7-06 rule 3).

Every ticket / household / cook is handled in its own transaction, re-selected with
``FOR UPDATE SKIP LOCKED`` (a second worker skips it), in LIMIT batches. A failure is logged,
counted in ``SweepReport.failed`` and does not stop the others.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, time, timedelta
from typing import Any
from zoneinfo import ZoneInfo

import structlog
from sqlalchemy import Select, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import Cook, Household, Ticket, TicketStatus
from app.services import cooks as cook_svc
from app.services import marks, push_outbox
from app.services import notifications as notify
from app.services import tickets as ticket_svc
from app.services.labels import slot_label, time_label
from app.services.sweeps import each

S = TicketStatus
log = structlog.get_logger(__name__)

# Per-slot thresholds are clamped to this window (it also bounds the candidate query).
MAX_ALERT_MINUTES = 360


@dataclass
class SweepReport:
    not_confirmed: list[uuid.UUID] = field(default_factory=list)
    auto_cancelled: list[uuid.UUID] = field(default_factory=list)
    stuck_cancelled: list[uuid.UUID] = field(default_factory=list)
    no_show: list[uuid.UUID] = field(default_factory=list)
    at_risk: list[uuid.UUID] = field(default_factory=list)
    tomorrow_notified: list[uuid.UUID] = field(default_factory=list)  # household ids
    back_on_duty: list[uuid.UUID] = field(default_factory=list)
    failed: dict[str, int] = field(default_factory=lambda: defaultdict(int))

    def counts(self) -> dict[str, int]:
        out = {k: len(v) for k, v in self.__dict__.items() if isinstance(v, list)}
        out["failed"] = sum(self.failed.values())
        return out


def slot_minutes(household: Household, slot: str, key: str, default: int) -> int:
    """Household setting ``slot_defaults[slot][key]`` (minutes before due), else default."""
    raw: Any = ((household.slot_defaults or {}).get(slot) or {}).get(key)
    try:
        value = int(raw) if raw is not None else default
    except (TypeError, ValueError):
        value = default
    return max(5, min(MAX_ALERT_MINUTES, value))


def _locked(stmt: Select[tuple[Ticket]]) -> Select[tuple[Ticket]]:
    return stmt.with_for_update(skip_locked=True)


async def _live_household(db: AsyncSession, household_id: uuid.UUID) -> Household | None:
    h = await db.get(Household, household_id)
    return h if h is not None and h.deleted_at is None else None


async def sweep_not_confirmed(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    cutoff = now - timedelta(minutes=get_settings().TICKET_NOT_CONFIRMED_AFTER_MINUTES)
    active = [S.accepted, S.cooking, S.ready]

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = select(Ticket.id).where(Ticket.status.in_(active), Ticket.due_at <= cutoff)
        return (q.where(Ticket.id.not_in(seen)) if seen else q).order_by(Ticket.due_at)

    async def handle(tid: uuid.UUID) -> None:
        t = (
            await db.execute(
                _locked(
                    select(Ticket).where(
                        Ticket.id == tid, Ticket.status.in_(active), Ticket.due_at <= cutoff
                    )
                )
            )
        ).scalar_one_or_none()
        if t is None or (household := await _live_household(db, t.household_id)) is None:
            return
        await ticket_svc.system_transition(db, household, t, S.not_confirmed, now=now)
        await notify.emit(
            db,
            "not_confirmed_prompt",
            household,
            ticket=t,
            params=ticket_svc.ticket_params(household, t),
            now=now,
        )
        report.not_confirmed.append(t.id)

    await each(db, "not_confirmed", ids, handle, report.failed)


async def sweep_not_confirmed_close(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    cutoff = now - timedelta(hours=get_settings().TICKET_NOT_CONFIRMED_CLOSE_HOURS)

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = select(Ticket.id).where(
            Ticket.status == S.not_confirmed, Ticket.status_changed_at <= cutoff
        )
        return (q.where(Ticket.id.not_in(seen)) if seen else q).order_by(Ticket.due_at)

    async def handle(tid: uuid.UUID) -> None:
        t = (
            await db.execute(
                _locked(
                    select(Ticket).where(
                        Ticket.id == tid,
                        Ticket.status == S.not_confirmed,
                        Ticket.status_changed_at <= cutoff,
                    )
                )
            )
        ).scalar_one_or_none()
        if t is None or (household := await _live_household(db, t.household_id)) is None:
            return
        await ticket_svc.system_transition(
            db, household, t, S.cancelled, action="auto_closed", reason="not_confirmed_24h", now=now
        )
        report.auto_cancelled.append(t.id)

    await each(db, "not_confirmed_close", ids, handle, report.failed)


async def sweep_stuck(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    """new / unassigned nobody picked up: cancelled TICKET_STUCK_CANCEL_HOURS after due."""
    cutoff = now - timedelta(hours=get_settings().TICKET_STUCK_CANCEL_HOURS)
    stuck = [S.new, S.unassigned]

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = select(Ticket.id).where(Ticket.status.in_(stuck), Ticket.due_at <= cutoff)
        return (q.where(Ticket.id.not_in(seen)) if seen else q).order_by(Ticket.due_at)

    async def handle(tid: uuid.UUID) -> None:
        t = (
            await db.execute(
                _locked(
                    select(Ticket).where(
                        Ticket.id == tid, Ticket.status.in_(stuck), Ticket.due_at <= cutoff
                    )
                )
            )
        ).scalar_one_or_none()
        if t is None or (household := await _live_household(db, t.household_id)) is None:
            return
        await ticket_svc.system_transition(
            db, household, t, S.cancelled, action="auto_closed", reason="not_picked_up_24h", now=now
        )
        report.stuck_cancelled.append(t.id)

    await each(db, "stuck", ids, handle, report.failed)


async def sweep_no_show(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    s = get_settings()
    horizon = now + timedelta(minutes=MAX_ALERT_MINUTES)
    floor = now - timedelta(hours=s.TICKET_ALERT_LOOKBACK_HOURS)

    def where() -> list[Any]:
        return [
            Ticket.status == S.new,
            Ticket.no_show_alerted_at.is_(None),
            Ticket.due_at <= horizon,
            Ticket.due_at >= floor,
        ]

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = select(Ticket.id).where(*where())
        return (q.where(Ticket.id.not_in(seen)) if seen else q).order_by(Ticket.due_at)

    async def handle(tid: uuid.UUID) -> None:
        t = (
            await db.execute(_locked(select(Ticket).where(Ticket.id == tid, *where())))
        ).scalar_one_or_none()
        if t is None or (household := await _live_household(db, t.household_id)) is None:
            return
        minutes = slot_minutes(
            household, t.slot, "no_show_minutes", s.TICKET_NO_SHOW_BEFORE_MINUTES
        )
        if t.due_at > now + timedelta(minutes=minutes):
            return
        cook = await ticket_svc.ticket_cook(db, t)
        t.no_show_alerted_at = now
        ticket_svc.log_event(db, t, "no_show_alert", None, {"due_at": t.due_at.isoformat()}, now)
        await notify.emit(
            db,
            "no_show",
            household,
            ticket=t,
            assignee=cook,
            params=ticket_svc.ticket_params(household, t, cook),
            now=now,
        )
        report.no_show.append(t.id)

    await each(db, "no_show", ids, handle, report.failed)


async def sweep_at_risk(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    """Accepted but not Cooking shortly before due (F-5.7-12 second branch)."""
    s = get_settings()
    horizon = now + timedelta(minutes=MAX_ALERT_MINUTES)
    floor = now - timedelta(hours=s.TICKET_ALERT_LOOKBACK_HOURS)

    def where() -> list[Any]:
        return [
            Ticket.status == S.accepted,
            Ticket.at_risk_alerted_at.is_(None),
            Ticket.due_at <= horizon,
            Ticket.due_at >= floor,
        ]

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = select(Ticket.id).where(*where())
        return (q.where(Ticket.id.not_in(seen)) if seen else q).order_by(Ticket.due_at)

    async def handle(tid: uuid.UUID) -> None:
        t = (
            await db.execute(_locked(select(Ticket).where(Ticket.id == tid, *where())))
        ).scalar_one_or_none()
        if t is None or (household := await _live_household(db, t.household_id)) is None:
            return
        minutes = slot_minutes(
            household, t.slot, "at_risk_minutes", s.TICKET_AT_RISK_BEFORE_MINUTES
        )
        if t.due_at > now + timedelta(minutes=minutes):
            return
        cook = await ticket_svc.ticket_cook(db, t)
        t.at_risk_alerted_at = now
        ticket_svc.log_event(db, t, "at_risk_alert", None, {"due_at": t.due_at.isoformat()}, now)
        await notify.emit(
            db,
            "at_risk",
            household,
            ticket=t,
            assignee=cook,
            params=ticket_svc.ticket_params(household, t, cook),
            now=now,
        )
        report.at_risk.append(t.id)

    await each(db, "at_risk", ids, handle, report.failed)


def _notify_time() -> time:
    try:
        return time.fromisoformat(get_settings().TOMORROW_NOTIFY_LOCAL_TIME)
    except ValueError:
        return time(20, 0)


async def send_tomorrow_tickets(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    """Once per household per local day, from 20:00 local until midnight. Only households
    with an assigned ticket in the next days are looked at (no scan of every household)."""
    at = _notify_time()
    first = (now - timedelta(days=1)).date()
    last = (now + timedelta(days=2)).date()

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = (
            select(Ticket.household_id)
            .where(
                Ticket.date >= first,
                Ticket.date <= last,
                Ticket.status.in_([S.new, S.accepted]),
                Ticket.assignee_cook_id.is_not(None),
            )
            .distinct()
        )
        return (q.where(Ticket.household_id.not_in(seen)) if seen else q).order_by(
            Ticket.household_id
        )

    async def handle(hid: uuid.UUID) -> None:
        h = (
            await db.execute(
                select(Household)
                .where(Household.id == hid, Household.deleted_at.is_(None))
                .with_for_update(skip_locked=True)
            )
        ).scalar_one_or_none()
        if h is None:
            return
        tz = ZoneInfo(h.timezone or "Asia/Kolkata")
        local = now.astimezone(tz)
        if local.time() < at or await marks.is_marked(db, h.id, "tomorrow_tickets", local.date()):
            return
        tomorrow = local.date() + timedelta(days=1)
        tickets = list(
            (
                await db.execute(
                    select(Ticket)
                    .where(
                        Ticket.household_id == h.id,
                        Ticket.date == tomorrow,
                        Ticket.status.in_([S.new, S.accepted]),
                        Ticket.assignee_cook_id.is_not(None),
                    )
                    .order_by(Ticket.due_at)
                )
            ).scalars()
        )
        if not tickets or not await marks.claim(db, h.id, "tomorrow_tickets", local.date()):
            return
        by_cook: dict[uuid.UUID, list[Ticket]] = defaultdict(list)
        for t in tickets:
            assert t.assignee_cook_id is not None
            by_cook[t.assignee_cook_id].append(t)
        sent = False
        for cook_id, items in by_cook.items():
            cook = await db.get(Cook, cook_id)
            if cook is None:
                continue
            summary = "; ".join(
                f"{slot_label(t.slot)} {time_label(t.due_at, h.timezone)}: "
                + ", ".join(str(d.get("name", "")) for d in t.dishes or [])
                for t in items
            )
            audience = await notify.build_audience(db, h, assignee=cook)
            out = await notify.emit(
                db,
                "tomorrow_tickets",
                h,
                audience=audience,
                params={"count": len(items), "summary": summary},
                now=now,
            )
            sent = sent or bool(out)
        if sent:
            report.tomorrow_notified.append(h.id)

    await each(db, "tomorrow_tickets", ids, handle, report.failed)


async def sweep_duty_returns(db: AsyncSession, now: datetime, report: SweepReport) -> None:
    def where() -> list[Any]:
        return [
            Cook.on_duty.is_(False),
            Cook.off_duty_until.is_not(None),
            Cook.off_duty_until <= now,
            Cook.removed_at.is_(None),
        ]

    def ids(seen: set[uuid.UUID]) -> Select[Any]:
        q = select(Cook.id).where(*where())
        return (q.where(Cook.id.not_in(seen)) if seen else q).order_by(Cook.off_duty_until)

    async def handle(cid: uuid.UUID) -> None:
        c = (
            await db.execute(
                select(Cook).where(Cook.id == cid, *where()).with_for_update(skip_locked=True)
            )
        ).scalar_one_or_none()
        if c is None or (household := await _live_household(db, c.household_id)) is None:
            return
        await cook_svc.return_from_off_duty(db, household, c, now)
        report.back_on_duty.append(c.id)

    await each(db, "duty_returns", ids, handle, report.failed)


async def run_all(db: AsyncSession, now: datetime) -> SweepReport:
    report = SweepReport()
    await sweep_duty_returns(db, now, report)
    await sweep_not_confirmed_close(db, now, report)
    await sweep_stuck(db, now, report)
    await sweep_not_confirmed(db, now, report)
    await sweep_no_show(db, now, report)
    await sweep_at_risk(db, now, report)
    await send_tomorrow_tickets(db, now, report)
    if report.failed:
        log.error("ticket_timers_failures", **dict(report.failed))
    if push_outbox.take_pending(db):
        await push_outbox.kick()
    return report
