"""ARQ job queue access shared by the API (one pool per process, created once under a lock)."""

from __future__ import annotations

import asyncio
from typing import Any

import structlog

from app.core.config import get_settings

log = structlog.get_logger(__name__)

_pool: Any = None
_lock: asyncio.Lock | None = None


def queue_enabled() -> bool:
    """A real Redis (the ARQ worker runs); memory:// means run jobs in-process."""
    url = get_settings().REDIS_URL
    return bool(url) and not url.startswith("memory://")


async def _get_pool() -> Any:
    global _pool, _lock
    if _pool is not None:
        return _pool
    if _lock is None:
        _lock = asyncio.Lock()
    async with _lock:
        if _pool is None:
            from arq import create_pool
            from arq.connections import RedisSettings

            _pool = await create_pool(RedisSettings.from_dsn(get_settings().REDIS_URL))
    return _pool


async def enqueue(function: str, *args: Any, job_id: str | None = None) -> bool:
    """True when handed to the worker; False when there is no queue or it failed (the caller
    then runs the work inline or relies on the cron safety net)."""
    if not queue_enabled():
        return False
    try:
        pool = await _get_pool()
        await pool.enqueue_job(function, *args, _job_id=job_id)
        return True
    except Exception as exc:
        log.warning("enqueue_failed", function=function, error=type(exc).__name__)
        return False


def reset() -> None:
    """Tests / after fork."""
    global _pool, _lock
    _pool = None
    _lock = None
