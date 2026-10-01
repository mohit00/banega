"""ARQ worker: ``arq app.workers.worker.WorkerSettings``.

Jobs: purge after the 7-day undo window (Phase 1, extended in Phase 7 to every household
table and export file), idle chat purge and the Maharaj writer (Phase 4), the Phase 5
ticket/duty timers (``ticket_timers`` every 5 minutes: due_at + 3 h not_confirmed, 24 h
auto-close, no-show alert, 20:00 household-local "kal ke tickets", off-duty auto-return), and
the Phase 6-7 sweeps (``kitchen_sweeps`` every 5 minutes: 30-minute approval expiry ->
``stock_issue_timeout``, subscription transitions + the day-5 / day-7 10:00 trial reminders,
Monday 10:00 weekly summary) and ``run_export``. The logic lives in the services and takes
``now`` so it is unit-tested with a fake clock.

Hardening (review H1, M6, M7, M9): every sweep handles one ticket / household per
transaction (``FOR UPDATE SKIP LOCKED``, LIMIT batches), counts and logs failures instead of
aborting; every job has an explicit timeout; ``flush_push_outbox`` delivers queued pushes
after commit (kicked by the API, plus a 1-minute cron); ``purge_housekeeping`` (daily) drops
old OTP requests, expired sessions, 90-day inbox, delivered pushes, old marks and expired
data exports. Still to come: FCM delivery itself, TTS pre-render.
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any, ClassVar

import structlog
from arq import cron
from arq.connections import RedisSettings
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.core.logging_setup import configure_logging
from app.core.security import utcnow
from app.models import (
    Approval,
    AuthSession,
    ChatMessage,
    ChatSession,
    Consent,
    Device,
    ExportJob,
    Household,
    HouseholdMembership,
    InboxItem,
    MembershipStatus,
    NotificationMark,
    OtpRequest,
    PushOutbox,
    Rating,
    RationItem,
    RationRequest,
    ServedHistory,
    StockItem,
    Ticket,
    TicketStockIssue,
    User,
)
from app.services import export as export_svc
from app.services import insights, ladder, push_outbox, subscription, ticket_timers
from app.services.maharaj import pipeline as maharaj_pipeline

log = structlog.get_logger(__name__)


async def purge_household_data(db: AsyncSession, household_id: uuid.UUID) -> None:
    """Every household-scoped Phase 4-7 row, explicitly (FR-A8; does not rely on the database
    enforcing ON DELETE CASCADE), then the export files. The household row itself (and the
    Phase 1-5 tables that cascade from it) is deleted by the caller."""
    sessions = select(ChatSession.id).where(ChatSession.household_id == household_id)
    tickets = select(Ticket.id).where(Ticket.household_id == household_id)
    requests = select(RationRequest.id).where(RationRequest.household_id == household_id)
    await db.execute(delete(ChatMessage).where(ChatMessage.session_id.in_(sessions)))
    await db.execute(delete(ChatSession).where(ChatSession.household_id == household_id))
    await db.execute(delete(Rating).where(Rating.household_id == household_id))
    await db.execute(delete(ServedHistory).where(ServedHistory.household_id == household_id))
    await db.execute(delete(TicketStockIssue).where(TicketStockIssue.ticket_id.in_(tickets)))
    await db.execute(delete(Approval).where(Approval.household_id == household_id))
    await db.execute(delete(RationItem).where(RationItem.request_id.in_(requests)))
    await db.execute(delete(RationRequest).where(RationRequest.household_id == household_id))
    await db.execute(delete(StockItem).where(StockItem.household_id == household_id))
    await db.execute(delete(InboxItem).where(InboxItem.household_id == household_id))
    await db.execute(delete(Consent).where(Consent.household_id == household_id))
    await db.execute(delete(ExportJob).where(ExportJob.household_id == household_id))
    export_svc.remove_files(household_id)


async def purge_deleted(ctx: dict[str, Any]) -> dict[str, int]:
    """Hard-delete households and anonymise users whose undo window has closed (FR-A8)."""
    cutoff = utcnow() - timedelta(days=get_settings().UNDO_WINDOW_DAYS)
    async with get_sessionmaker()() as db:
        doomed = list(
            (
                await db.execute(
                    select(Household.id).where(
                        Household.deleted_at.is_not(None), Household.deleted_at <= cutoff
                    )
                )
            ).scalars()
        )
        for hid in doomed:
            await purge_household_data(db, hid)
        households = (
            await db.execute(
                delete(Household)
                .where(Household.deleted_at.is_not(None), Household.deleted_at <= cutoff)
                .returning(Household.id)
            )
        ).all()
        user_ids = list(
            (
                await db.execute(
                    select(User.id).where(
                        User.deleted_at.is_not(None),
                        User.deleted_at <= cutoff,
                        User.phone_deleted_at.is_(None),
                    )
                )
            ).scalars()
        )
        for uid in user_ids:
            await db.execute(delete(Device).where(Device.user_id == uid))
            await db.execute(delete(AuthSession).where(AuthSession.user_id == uid))
            # The user's own private data: chats, consent records, inbox.
            own_sessions = select(ChatSession.id).where(ChatSession.user_id == uid)
            await db.execute(delete(ChatMessage).where(ChatMessage.session_id.in_(own_sessions)))
            await db.execute(delete(ChatSession).where(ChatSession.user_id == uid))
            await db.execute(delete(Consent).where(Consent.user_id == uid))
            await db.execute(delete(InboxItem).where(InboxItem.user_id == uid))
            await db.execute(
                update(HouseholdMembership)
                .where(HouseholdMembership.user_id == uid)
                .values(status=MembershipStatus.removed)
            )
            # Erase the number (frees it for a new sign-up; fits users.phone on Postgres).
            await db.execute(
                update(User)
                .where(User.id == uid)
                .values(phone=None, phone_deleted_at=utcnow(), name=None)
            )
        await db.commit()
    result = {"households": len(households), "users": len(user_ids)}
    log.info("purge_deleted", **result)
    return result


async def purge_chat_sessions(ctx: dict[str, Any]) -> dict[str, int]:
    """F-5.4-01: hard-delete chat sessions (and messages) idle for CHAT_RETENTION_DAYS."""
    async with get_sessionmaker()() as db:
        n = await maharaj_pipeline.purge_idle_sessions(db)
        await db.commit()
    log.info("purge_chat_sessions", sessions=n)
    return {"sessions": n}


async def maharaj_write(ctx: dict[str, Any], message_id: str) -> str | None:
    """Fill a pending Maharaj reply (LLM writer, template fallback)."""
    try:
        return await maharaj_pipeline.complete_write(message_id)
    except Exception:
        log.exception("maharaj_write_crashed", message_id=message_id)
        await maharaj_pipeline.mark_failed(message_id)
        return None


async def run_ticket_timers(ctx: dict[str, Any]) -> dict[str, int]:
    """Phase 5 timers; idempotent, safe to run every few minutes."""
    async with get_sessionmaker()() as db:
        report = await ticket_timers.run_all(db, utcnow())
        await db.commit()
    counts = report.counts()
    (log.error if counts.get("failed") else log.info)("ticket_timers", **counts)
    return counts


async def kitchen_sweeps(ctx: dict[str, Any]) -> dict[str, int]:
    """Phases 6-7: approval expiry, subscription transitions + reminders, weekly summary.
    Each step commits on its own; one failing step does not stop the others."""
    now = utcnow()
    counts: dict[str, int] = {"kitchen_sweep_failures": 0}
    async with get_sessionmaker()() as db:
        try:
            expired = await ladder.expire_approvals(db, now)
            await db.commit()
            counts["approvals_expired"] = len(expired)
        except Exception:
            await db.rollback()
            counts["kitchen_sweep_failures"] += 1
            log.exception("sweep_failed", sweep="approvals")
        try:
            counts.update(await subscription.sweep(db, now))
            await db.commit()
        except Exception:
            await db.rollback()
            counts["kitchen_sweep_failures"] += 1
            log.exception("sweep_failed", sweep="subscriptions")
        try:
            weekly = await insights.send_weekly(db, now)
            await db.commit()
            counts["weekly_summaries"] = len(weekly)
        except Exception:
            await db.rollback()
            counts["kitchen_sweep_failures"] += 1
            log.exception("sweep_failed", sweep="weekly")
        pushes = push_outbox.take_pending(db)
    if pushes:
        await push_outbox.kick()
    (log.error if counts["kitchen_sweep_failures"] else log.info)("kitchen_sweeps", **counts)
    return counts


async def flush_push_outbox(ctx: dict[str, Any]) -> dict[str, int]:
    """Deliver pushes queued by committed transactions (M7)."""
    result = await push_outbox.flush()
    if result["sent"] or result["failed"]:
        log.info("push_outbox", **result)
    return result


async def purge_housekeeping(ctx: dict[str, Any]) -> dict[str, int]:
    """Daily retention (M6, M9): OTP requests > 1 day, sessions expired or revoked > 7 days,
    inbox > 90 days, delivered / failed pushes > 7 days, marks > 60 days, data exports
    finished > EXPORT_TTL_DAYS (rows and files)."""
    now = utcnow()
    out: dict[str, int] = {}
    async with get_sessionmaker()() as db:
        statements = {
            "otp_requests": delete(OtpRequest).where(
                OtpRequest.created_at < now - timedelta(days=1)
            ),
            "auth_sessions": delete(AuthSession).where(
                (AuthSession.expires_at < now) | (AuthSession.revoked_at < now - timedelta(days=7))
            ),
            "inbox_items": delete(InboxItem).where(InboxItem.created_at < now - timedelta(days=90)),
            "push_outbox": delete(PushOutbox).where(
                PushOutbox.created_at < now - timedelta(days=7),
                (PushOutbox.sent_at.is_not(None)) | (PushOutbox.failed_at.is_not(None)),
            ),
            "notification_marks": delete(NotificationMark).where(
                NotificationMark.created_at < now - timedelta(days=60)
            ),
        }
        for name, stmt in statements.items():
            result = await db.execute(stmt)
            out[name] = int(getattr(result, "rowcount", 0) or 0)
            await db.commit()
        out["exports"] = await export_svc.expire_old(db, now)
        await db.commit()
    log.info("purge_housekeeping", **out)
    return out


async def run_export(ctx: dict[str, Any], job_id: str) -> str | None:
    async with get_sessionmaker()() as db:
        job = await export_svc.run(db, uuid.UUID(job_id))
        await db.commit()
    return str(job.status) if job is not None else None


async def heartbeat(ctx: dict[str, Any]) -> None:
    """Placeholder cron so the schedule is visibly alive in logs."""
    log.info("worker_heartbeat")


async def startup(ctx: dict[str, Any]) -> None:
    s = get_settings()
    configure_logging(s.LOG_LEVEL, s.LOG_JSON)
    log.info("worker_startup")


def _redis_dsn() -> str:
    url = get_settings().REDIS_URL
    # memory:// (tests, single-process dev) has no worker; importing this module must work.
    return url if url.startswith(("redis://", "rediss://", "unix://")) else "redis://localhost:6379"


_TIMEOUT = get_settings().WORKER_JOB_TIMEOUT_SECONDS


class WorkerSettings:
    functions: ClassVar[list[Any]] = [
        purge_deleted,
        purge_chat_sessions,
        purge_housekeeping,
        maharaj_write,
        run_ticket_timers,
        kitchen_sweeps,
        run_export,
        flush_push_outbox,
    ]
    cron_jobs: ClassVar[list[Any]] = [
        cron(purge_deleted, hour={21}, minute={30}, timeout=_TIMEOUT),  # 03:00 IST
        cron(purge_chat_sessions, hour={21}, minute={45}, timeout=_TIMEOUT),  # 03:15 IST
        cron(purge_housekeeping, hour={22}, minute={0}, timeout=_TIMEOUT),  # 03:30 IST
        cron(heartbeat, minute={0, 15, 30, 45}),
        # Every 5 minutes: not_confirmed / auto-close / stuck / no-show / at-risk / 20:00
        # local / duty return. The timeout is below the 5-minute period.
        cron(run_ticket_timers, minute=set(range(0, 60, 5)), unique=True, timeout=_TIMEOUT),
        # Every 5 minutes: swap / dish-change timeout, subscription state, reminders, summary.
        cron(kitchen_sweeps, minute=set(range(2, 60, 5)), unique=True, timeout=_TIMEOUT),
        # Safety net for pushes whose after-commit kick was lost.
        cron(flush_push_outbox, second={30}, unique=True, timeout=55),
    ]
    # Explicit (ARQ's default is 300 s): a job that overruns is cancelled and logged.
    job_timeout = _TIMEOUT
    max_tries = 3
    on_startup = startup
    redis_settings = RedisSettings.from_dsn(_redis_dsn())
