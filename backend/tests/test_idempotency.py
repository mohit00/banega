"""Idempotency-Key middleware (review M2, primary #2)."""

from __future__ import annotations

import json
from typing import Any

import pytest
from httpx import AsyncClient

from app.core import kv as kv_module
from app.core.kv import MemoryStore, get_kv

KEY = {"Idempotency-Key": "k-1"}


async def test_success_is_replayed(client: AsyncClient, login: Any) -> None:
    h = await login()
    r1 = await client.post("/v1/households", json={"name": "A"}, headers={**h, **KEY})
    r2 = await client.post("/v1/households", json={"name": "A"}, headers={**h, **KEY})
    assert r1.status_code == 201 and r2.status_code == 201
    assert r2.headers.get("idempotent-replayed") == "true" and r1.json() == r2.json()


async def test_state_dependent_errors_are_not_cached(client: AsyncClient, login: Any) -> None:
    """A 409 (already in a household) must not be replayed after the state changes."""
    h = await login()
    assert (await client.post("/v1/households", json={"name": "A"}, headers=h)).status_code == 201
    r1 = await client.post("/v1/households", json={"name": "B"}, headers={**h, **KEY})
    assert r1.status_code == 409
    assert (await client.delete("/v1/household", headers=h)).status_code == 200
    r2 = await client.post("/v1/households", json={"name": "B"}, headers={**h, **KEY})
    assert r2.status_code == 201 and "idempotent-replayed" not in r2.headers


async def test_validation_errors_are_replayed(client: AsyncClient, login: Any) -> None:
    h = await login()
    r1 = await client.post("/v1/households", json={"name": ""}, headers={**h, **KEY})
    r2 = await client.post("/v1/households", json={"name": ""}, headers={**h, **KEY})
    assert r1.status_code == r2.status_code == 422
    assert r2.headers.get("idempotent-replayed") == "true"


async def test_auth_endpoints_are_never_cached(client: AsyncClient) -> None:
    body = {"phone": "+919800000801"}
    r1 = await client.post("/v1/auth/otp", json=body, headers=KEY)
    code = r1.json()["dev_code"]
    v = {"phone": body["phone"], "code": code}
    t1 = await client.post("/v1/auth/verify", json=v, headers=KEY)
    t2 = await client.post("/v1/auth/verify", json=v, headers=KEY)
    assert t1.status_code == 200 and t2.status_code == 400  # single-use code, not a replay
    kv = get_kv()
    assert isinstance(kv, MemoryStore)
    assert not [k for k in kv._data if k.startswith("idem:")]


async def test_pending_marker_is_a_short_lease(client: AsyncClient, login: Any) -> None:
    """A crashed request leaves "pending" behind only for the lease, not for a day."""
    h = await login()
    kv = get_kv()
    seen: list[int] = []
    original = kv.set

    async def spy(key: str, value: str, ttl: int, *, nx: bool = False) -> bool:
        if key.startswith("idem:") and json.loads(value)["state"] == "pending":
            seen.append(ttl)
        return await original(key, value, ttl, nx=nx)

    kv.set = spy  # type: ignore[method-assign]
    await client.post("/v1/households", json={"name": "A"}, headers={**h, **KEY})
    assert seen and max(seen) <= 30


class _DownStore(MemoryStore):
    async def get(self, key: str) -> str | None:
        if key.startswith("idem:"):
            raise ConnectionError("redis down")
        return await super().get(key)


async def test_fails_open_when_store_is_down(
    client: AsyncClient, login: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    h = await login()
    kv_module.set_kv(_DownStore())
    r = await client.post("/v1/households", json={"name": "A"}, headers={**h, **KEY})
    assert r.status_code == 201
