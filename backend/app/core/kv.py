"""Tiny key-value abstraction over Redis, with an in-memory fallback for tests and local dev.

Used for OTP rate limits and locks, and for Idempotency-Key replay.
"""

from __future__ import annotations

import time
from typing import Protocol

from redis.asyncio import Redis

from app.core.config import get_settings


class KVStore(Protocol):
    async def get(self, key: str) -> str | None: ...
    async def set(self, key: str, value: str, ttl: int, *, nx: bool = False) -> bool: ...
    async def incr(self, key: str, ttl: int) -> int: ...
    async def delete(self, key: str) -> None: ...
    async def ttl(self, key: str) -> int: ...


class MemoryStore:
    def __init__(self) -> None:
        self._data: dict[str, tuple[str, float]] = {}

    def _live(self, key: str) -> tuple[str, float] | None:
        item = self._data.get(key)
        if item is None:
            return None
        if item[1] <= time.monotonic():
            self._data.pop(key, None)
            return None
        return item

    async def get(self, key: str) -> str | None:
        item = self._live(key)
        return item[0] if item else None

    async def set(self, key: str, value: str, ttl: int, *, nx: bool = False) -> bool:
        if nx and self._live(key) is not None:
            return False
        self._data[key] = (value, time.monotonic() + ttl)
        return True

    async def incr(self, key: str, ttl: int) -> int:
        item = self._live(key)
        if item is None:
            self._data[key] = ("1", time.monotonic() + ttl)
            return 1
        value = int(item[0]) + 1
        self._data[key] = (str(value), item[1])
        return value

    async def delete(self, key: str) -> None:
        self._data.pop(key, None)

    async def ttl(self, key: str) -> int:
        item = self._live(key)
        return max(0, int(item[1] - time.monotonic())) if item else -2

    def clear(self) -> None:
        self._data.clear()


class RedisStore:
    def __init__(self, url: str) -> None:
        self._r: Redis = Redis.from_url(url, decode_responses=True)

    async def get(self, key: str) -> str | None:
        value = await self._r.get(key)
        return None if value is None else str(value)

    async def set(self, key: str, value: str, ttl: int, *, nx: bool = False) -> bool:
        return bool(await self._r.set(key, value, ex=ttl, nx=nx))

    async def incr(self, key: str, ttl: int) -> int:
        async with self._r.pipeline(transaction=True) as pipe:
            pipe.incr(key)
            pipe.expire(key, ttl, nx=True)
            value, _ = await pipe.execute()
        return int(value)

    async def delete(self, key: str) -> None:
        await self._r.delete(key)

    async def ttl(self, key: str) -> int:
        return int(await self._r.ttl(key))

    async def close(self) -> None:
        await self._r.aclose()


_store: KVStore | None = None


def get_kv() -> KVStore:
    global _store
    if _store is None:
        url = get_settings().REDIS_URL
        _store = MemoryStore() if not url or url.startswith("memory://") else RedisStore(url)
    return _store


def set_kv(store: KVStore | None) -> None:
    global _store
    _store = store
