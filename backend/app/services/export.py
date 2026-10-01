"""Data export (DPDP access right, F-X-02; contract Phase 7): ``POST /v1/export`` queues an
``ExportJob`` (one pending job per household: a repeat returns it); the worker
(``run_export``) writes one JSON file under
``MEDIA_DIR/exports/{household_id}/{job_id}.json`` and drops an inbox item with the download
link (``GET /v1/export/{job_id}/download``, authenticated; nginx denies /media/exports/).
Without a real Redis (tests, single-process dev) the job runs inline.

Chat sessions are private (F-5.4-01): only the requester's own sessions are included.
Finished jobs and their files are deleted EXPORT_TTL_DAYS later (:func:`expire_old`, daily).
"""

from __future__ import annotations

import asyncio
import json
import shutil
import uuid
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.models import (
    Approval,
    ChatMessage,
    ChatSession,
    Consent,
    Cook,
    CookDutyLog,
    ExportJob,
    ExportStatus,
    Household,
    Member,
    Menu,
    MenuDish,
    Rating,
    RationRequest,
    ServedHistory,
    StockItem,
    Subscription,
    Ticket,
    TicketEvent,
    TicketMessage,
    TicketStockIssue,
)
from app.models.base import Base, utcnow
from app.services import notifications as notify

log = structlog.get_logger(__name__)

SKIP_COLUMNS = {"embedding", "token_hash", "refresh_jti_hash", "code_hash"}


def export_root() -> Path:
    return Path(get_settings().MEDIA_DIR).resolve() / "exports"


def household_dir(household_id: uuid.UUID) -> Path:
    return export_root() / str(household_id)


def _jsonable(value: Any) -> Any:
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if hasattr(value, "value") and not isinstance(value, str | int | float | bool):
        return value.value
    return value


def row_dict(row: Base) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for col in row.__table__.columns:
        if col.key in SKIP_COLUMNS:
            continue
        out[col.key] = _jsonable(getattr(row, col.key))
    return out


async def _rows(db: AsyncSession, model: type[Base], *where: Any) -> list[dict[str, Any]]:
    return [row_dict(r) for r in (await db.execute(select(model).where(*where))).scalars()]


async def build(
    db: AsyncSession, household: Household, requester: uuid.UUID | None
) -> dict[str, Any]:
    hid = household.id
    ticket_ids = list(
        (await db.execute(select(Ticket.id).where(Ticket.household_id == hid))).scalars()
    )
    menu_ids = list((await db.execute(select(Menu.id).where(Menu.household_id == hid))).scalars())
    cook_ids = list((await db.execute(select(Cook.id).where(Cook.household_id == hid))).scalars())
    cooks = await _rows(db, Cook, Cook.household_id == hid)
    for c in cooks:
        phone = c.pop("phone", None)
        c["phone_masked"] = f"******{phone[-4:]}" if phone else None
    ration = list(
        (await db.execute(select(RationRequest).where(RationRequest.household_id == hid))).scalars()
    )
    chats: list[dict[str, Any]] = []
    if requester is not None:
        for s in (
            await db.execute(
                select(ChatSession).where(
                    ChatSession.household_id == hid, ChatSession.user_id == requester
                )
            )
        ).scalars():
            chats.append(
                {
                    **row_dict(s),
                    "messages": await _rows(db, ChatMessage, ChatMessage.session_id == s.id),
                }
            )
    return {
        "format": "banega-export/1",
        "exported_at": utcnow().isoformat(),
        "household": row_dict(household),
        "subscription": await _rows(db, Subscription, Subscription.household_id == hid),
        "members": await _rows(db, Member, Member.household_id == hid),
        "cooks": cooks,
        "cook_duty_log": await _rows(db, CookDutyLog, CookDutyLog.cook_id.in_(cook_ids))
        if cook_ids
        else [],
        "menus": await _rows(db, Menu, Menu.household_id == hid),
        "menu_dishes": await _rows(db, MenuDish, MenuDish.menu_id.in_(menu_ids))
        if menu_ids
        else [],
        "tickets": await _rows(db, Ticket, Ticket.household_id == hid),
        "ticket_events": await _rows(db, TicketEvent, TicketEvent.ticket_id.in_(ticket_ids))
        if ticket_ids
        else [],
        "ticket_messages": await _rows(db, TicketMessage, TicketMessage.ticket_id.in_(ticket_ids))
        if ticket_ids
        else [],
        "ticket_stock_issues": await _rows(
            db, TicketStockIssue, TicketStockIssue.ticket_id.in_(ticket_ids)
        )
        if ticket_ids
        else [],
        "stock": await _rows(db, StockItem, StockItem.household_id == hid),
        "ration_requests": [
            {**row_dict(r), "items": [row_dict(i) for i in r.items]} for r in ration
        ],
        "approvals": await _rows(db, Approval, Approval.household_id == hid),
        "ratings": await _rows(db, Rating, Rating.household_id == hid),
        "served_history": await _rows(db, ServedHistory, ServedHistory.household_id == hid),
        "consents": await _rows(db, Consent, Consent.household_id == hid),
        "my_chats": chats,
    }


def download_path(job: ExportJob) -> str:
    return f"/v1/export/{job.id}/download"


async def run(db: AsyncSession, job_id: uuid.UUID) -> ExportJob | None:
    job = await db.get(ExportJob, job_id)
    if job is None or job.status != ExportStatus.pending:
        return job
    household = await db.get(Household, job.household_id)
    if household is None:
        return None
    try:
        data = await build(db, household, job.requested_by)
        folder = household_dir(household.id)
        path = folder / f"{job.id}.json"
        text = json.dumps(data, ensure_ascii=False, indent=1)

        def write() -> None:
            folder.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")

        await asyncio.to_thread(write)
        job.file_path = str(path)
        job.status = ExportStatus.done
        job.finished_at = utcnow()
        await notify.emit(
            db,
            "export_ready",
            household,
            requester=job.requested_by,
            params={"link": download_path(job)},
            data={"link": download_path(job)},
        )
    except Exception as exc:  # pragma: no cover - disk errors
        log.exception("export_failed", job_id=str(job.id))
        job.status = ExportStatus.failed
        job.error = type(exc).__name__[:200]
        job.finished_at = utcnow()
    await db.flush()
    return job


async def expire_old(db: AsyncSession, now: datetime) -> int:
    """Delete finished export jobs (and their files) older than EXPORT_TTL_DAYS."""
    from datetime import timedelta

    from sqlalchemy import delete, or_

    cutoff = now - timedelta(days=get_settings().EXPORT_TTL_DAYS)
    stale = or_(
        ExportJob.finished_at <= cutoff,
        # A pending job that never ran (worker lost it) frees the household slot too.
        (ExportJob.status == ExportStatus.pending) & (ExportJob.created_at <= cutoff),
    )
    jobs = list((await db.execute(select(ExportJob).where(stale))).scalars())
    for job in jobs:
        if job.file_path:
            path = Path(job.file_path)
            await asyncio.to_thread(path.unlink, True)
    if jobs:
        await db.execute(delete(ExportJob).where(ExportJob.id.in_([j.id for j in jobs])))
    return len(jobs)


def remove_files(household_id: uuid.UUID) -> bool:
    folder = household_dir(household_id)
    if folder.exists():
        shutil.rmtree(folder, ignore_errors=True)
        return True
    return False


async def enqueue(job_id: uuid.UUID) -> bool:
    """True when handed to the ARQ worker; False = the caller runs it inline."""
    from app.core import queue

    return await queue.enqueue("run_export", str(job_id))
