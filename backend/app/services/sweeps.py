"""Shared worker sweep loop (review H1): id batches, one transaction per item, failures
logged and counted (never fatal for the rest)."""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable, MutableMapping
from typing import Any

import structlog
from sqlalchemy import Select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.kv import get_kv

log = structlog.get_logger(__name__)

MAX_BATCHES = 50


async def each(
    db: AsyncSession,
    name: str,
    ids_query: Callable[[set[uuid.UUID]], Select[Any]],
    handle: Callable[[uuid.UUID], Awaitable[None]],
    failed: MutableMapping[str, int],
) -> None:
    """``ids_query(seen)`` selects candidate ids (excluding ``seen``); ``handle(id)`` re-selects
    the row (``FOR UPDATE SKIP LOCKED``) and does the work; it is committed on its own."""
    batch = get_settings().WORKER_BATCH_SIZE
    seen: set[uuid.UUID] = set()
    for _ in range(MAX_BATCHES):
        ids = list((await db.execute(ids_query(seen).limit(batch))).scalars())
        await db.rollback()  # end the read transaction; each item gets its own
        if not ids:
            return
        for item_id in ids:
            seen.add(item_id)
            try:
                await handle(item_id)
                await db.commit()
            except Exception:
                await db.rollback()
                db.expunge_all()
                failed[name] = failed.get(name, 0) + 1
                log.exception("sweep_item_failed", sweep=name, id=str(item_id))
                try:
                    await get_kv().incr(f"metrics:worker_failures:{name}", 7 * 86400)
                except Exception:
                    log.warning("sweep_metric_failed", sweep=name)
        if len(ids) < batch:
            return
