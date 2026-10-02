"""Push delivery after commit (review M7).

:func:`app.services.notifications.emit` writes one :class:`PushOutbox` row per recipient in
the caller's transaction (next to the inbox rows). Once the transaction has committed,
:func:`kick` hands delivery to the ARQ worker (``flush_push_outbox``) or, without a real
Redis (dev, tests), delivers inline. A cron runs :func:`flush` every minute as a safety net,
so a push whose kick was lost still goes out. Rows are claimed with
``FOR UPDATE SKIP LOCKED`` so two workers never send the same push. Failed sends are retried
with backoff (``BACKOFF_SECONDS``); tokens FCM reports as unregistered are deleted.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import queue
from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import Device, PushOutbox

log = structlog.get_logger(__name__)

MAX_ATTEMPTS = 5
# Earliest time of attempt n (0-based), in seconds after the row was created: immediately,
# then about 1 min, 5 min, 15 min and 1 h (the 1-minute cron picks retries up).
BACKOFF_SECONDS: tuple[int, ...] = (0, 60, 300, 900, 3600)
# Key in PushOutbox.data listing the tokens still to retry (never sent to the device).
RETRY_KEY = "_retry_tokens"
SESSION_FLAG = "push_outbox_pending"


def mark_pending(db: AsyncSession) -> None:
    db.info[SESSION_FLAG] = True


def take_pending(db: AsyncSession) -> bool:
    return bool(db.info.pop(SESSION_FLAG, False))


def due(row: PushOutbox, now: datetime) -> bool:
    """Backoff: attempt ``row.attempts`` may run once its delay since creation has passed."""
    delay = BACKOFF_SECONDS[min(row.attempts, len(BACKOFF_SECONDS) - 1)]
    created = row.created_at
    if created.tzinfo is None:
        created = created.replace(tzinfo=UTC)
    return now >= created + timedelta(seconds=delay)


async def flush(limit: int = 500) -> dict[str, int]:
    """Deliver unsent pushes (oldest first). Each batch is claimed with SKIP LOCKED.

    Tokens the provider reports as gone are deleted from ``devices``; tokens that failed
    transiently are kept on the row (``_retry_tokens``) and retried alone, with backoff, up
    to ``MAX_ATTEMPTS``; an adapter exception retries the whole row the same way."""
    from app.services.notifications import PushMessage, get_push

    sent = failed = dead_total = 0
    adapter = get_push()
    async with get_sessionmaker()() as db:
        now = utcnow()
        rows = [
            r
            for r in (
                await db.execute(
                    select(PushOutbox)
                    .where(PushOutbox.sent_at.is_(None), PushOutbox.failed_at.is_(None))
                    .order_by(PushOutbox.created_at)
                    .limit(limit)
                    .with_for_update(skip_locked=True)
                )
            ).scalars()
            if due(r, now)
        ]
        if not rows:
            return {"sent": 0, "failed": 0}
        devices: dict[uuid.UUID, list[tuple[str, str]]] = defaultdict(list)
        for d in (
            await db.execute(select(Device).where(Device.user_id.in_({r.user_id for r in rows})))
        ).scalars():
            devices[d.user_id].append((str(d.platform), d.push_token))
        dead_tokens: set[str] = set()
        for row in rows:
            data = dict(row.data or {})
            only = data.pop(RETRY_KEY, None)
            tokens = tuple(
                t
                for t in devices.get(row.user_id, ())
                if t[1] not in dead_tokens and (only is None or t[1] in only)
            )
            row.attempts += 1
            if not tokens:
                row.sent_at = now  # nothing to deliver to; the inbox row is the record
                continue
            try:
                result = await adapter.send(
                    PushMessage(
                        user_id=row.user_id,
                        tokens=tokens,
                        title=row.title,
                        body=row.body,
                        data={str(k): str(v) for k, v in data.items()},
                    )
                )
            except Exception as exc:  # best effort; retried by a later flush
                row.last_error = type(exc).__name__[:200]
                if row.attempts >= MAX_ATTEMPTS:
                    row.failed_at = now
                    failed += 1
                log.warning("push_failed", notification=row.event, attempts=row.attempts)
                continue
            if result is not None and result.dead:
                dead_tokens.update(result.dead)
            if result is not None and result.retry:
                row.data = {**data, RETRY_KEY: [t for _, t in result.retry]}
                row.last_error = "partial_retry"
                if row.attempts >= MAX_ATTEMPTS:
                    row.failed_at = now
                    failed += 1
                log.warning("push_partial", notification=row.event, retry=len(result.retry))
                continue
            row.sent_at = now
            sent += 1
        if dead_tokens:
            dead_total = len(dead_tokens)
            await db.execute(delete(Device).where(Device.push_token.in_(dead_tokens)))
            log.info("push_dead_tokens_removed", count=dead_total)
        await db.commit()
    return {"sent": sent, "failed": failed, "dead_tokens": dead_total}


async def kick() -> None:
    """After a commit that wrote outbox rows: the worker delivers, or we do it now."""
    # One job per second at most (ARQ refuses a duplicate job id while it is known).
    bucket = int(utcnow().timestamp())
    if await queue.enqueue("flush_push_outbox", job_id=f"flush_push_outbox:{bucket}"):
        return
    try:
        await flush()
    except Exception:
        log.exception("push_flush_failed")
