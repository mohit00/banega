from __future__ import annotations

from httpx import AsyncClient


async def test_health(client: AsyncClient) -> None:
    r = await client.get("/v1/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.headers["x-request-id"]


async def test_request_id_is_echoed(client: AsyncClient) -> None:
    r = await client.get("/v1/health", headers={"X-Request-ID": "abc123"})
    assert r.headers["x-request-id"] == "abc123"


async def test_error_envelope_for_unknown_route(client: AsyncClient) -> None:
    r = await client.get("/v1/nope")
    assert r.status_code == 404
    body = r.json()
    assert set(body) == {"code", "message_en", "message_hi", "details"}
    assert body["code"] == "not_found"


async def test_error_envelope_for_validation(client: AsyncClient) -> None:
    r = await client.post("/v1/auth/otp", json={"phone": "12"})
    assert r.status_code == 422
    assert r.json()["code"] == "validation_error"
    assert r.json()["details"]["errors"]


async def test_protected_route_requires_token(client: AsyncClient) -> None:
    r = await client.get("/v1/me")
    assert r.status_code == 401
    assert r.json()["code"] == "unauthorized"


async def test_readiness(client: AsyncClient) -> None:
    r = await client.get("/v1/health/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"
