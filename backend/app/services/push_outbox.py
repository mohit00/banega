"""Push delivery after commit (review M7).

:func:`app.services.notifications.emit` writes one :class:`PushOutbox` row per recipient in
the caller's transaction (next to the inbox rows). Once the transaction has committed,
:func:`kick` hands delivery to the ARQ worker (``flush_push_outbox``) or, without a real
Redis (dev, tests), delivers inline. A cron runs :func:`flush` every minute as a safety net,
so a push whose kick was lost still goes out. Rows are claimed with
``FOR UPDATE SKIP LOCKED`` so two workers never send the same push.
"""

from __future__ import annotations

import uuid
from collections import defaultdict

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import queue
from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.models import Device, PushOutbox

log = structlog.get_logger(__name__)

MAX_ATTEMPTS = 5
SESSION_FLAG = "push_outbox_pending"


def mark_pending(db: AsyncSession) -> None:
    db.info[SESSION_FLAG] = True


def take_pending(db: AsyncSession) -> bool:
    return bool(db.info.pop(SESSION_FLAG, False))


async def flush(limit: int = 500) -> dict[str, int]:
    """Deliver unsent pushes (oldest first). Each batch is claimed with SKIP LOCKED."""
    from app.services.notifications import PushMessage, get_push

    sent = failed = 0
    adapter = get_push()
    async with get_sessionmaker()() as db:
        rows = list(
            (
                await db.execute(
                    select(PushOutbox)
                    .where(PushOutbox.sent_at.is_(None), PushOutbox.failed_at.is_(None))
                    .order_by(PushOutbox.created_at)
                    .limit(limit)
                    .with_for_update(skip_locked=True)
                )
            ).scalars()
        )
        if not rows:
            return {"sent": 0, "failed": 0}
        devices: dict[uuid.UUID, list[tuple[str, str]]] = defaultdict(list)
        for d in (
            await db.execute(select(Device).where(Device.user_id.in_({r.user_id for r in rows})))
        ).scalars():
            devices[d.user_id].append((str(d.platform), d.push_token))
        now = utcnow()
        for row in rows:
            tokens = tuple(devices.get(row.user_id, ()))
            row.attempts += 1
            if not tokens:
                row.sent_at = now  # nothing to deliver to; the inbox row is the record
                continue
            try:
                await adapter.send(
                    PushMessage(
                        user_id=row.user_id,
                        tokens=tokens,
                        title=row.title,
                        body=row.body,
                        data={str(k): str(v) for k, v in (row.data or {}).items()},
                    )
                )
                row.sent_at = now
                sent += 1
            except Exception as exc:  # best effort; retried by the next flush
                row.last_error = type(exc).__name__[:200]
                if row.attempts >= MAX_ATTEMPTS:
                    row.failed_at = now
                    failed += 1
                log.warning("push_failed", notification=row.event, attempts=row.attempts)
        await db.commit()
    return {"sent": sent, "failed": failed}


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
