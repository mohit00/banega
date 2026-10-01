"""OTP abuse controls and refresh races (review H2, M3; primary minors)."""

from __future__ import annotations

import asyncio
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select

from app.core.client_ip import client_ip
from app.core.config import get_settings
from app.core.db import get_sessionmaker
from app.models import OtpRequest
from app.services import otp as otp_svc

PHONE = "+919812121212"


def _ip(addr: str) -> dict[str, str]:
    # Tests connect from 127.0.0.1, a trusted proxy: X-Forwarded-For is honoured.
    return {"X-Forwarded-For": f"6.6.6.6, {addr}"}


async def _send(client: AsyncClient, phone: str = PHONE, **kw: Any) -> Any:
    headers = kw.pop("headers", None)
    return await client.post("/v1/auth/otp", json={"phone": phone, **kw}, headers=headers)


def _wrong(code: str) -> str:
    return "000000" if code != "000000" else "111111"


async def test_per_ip_limit(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "OTP_MAX_PER_IP_PER_HOUR", 3)
    for i in range(3):
        assert (await _send(client, f"+91981000000{i}", headers=_ip("1.2.3.4"))).status_code == 200
    r = await _send(client, "+919810000009", headers=_ip("1.2.3.4"))
    assert r.status_code == 429 and r.json()["code"] == "otp_ip_limit"
    # Another client address is unaffected; the spoofable left part of XFF is ignored.
    assert (await _send(client, "+919810000009", headers=_ip("5.6.7.8"))).status_code == 200


async def test_global_limit(client: AsyncClient, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(get_settings(), "OTP_MAX_GLOBAL_PER_MINUTE", 2)
    assert (await _send(client, "+919810000011")).status_code == 200
    assert (await _send(client, "+919810000012")).status_code == 200
    r = await _send(client, "+919810000013")
    assert r.status_code == 429 and r.json()["code"] == "otp_busy"


async def test_device_limit_does_not_consume_the_number_slot(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(get_settings(), "OTP_MAX_PER_DEVICE_PER_DAY", 1)
    assert (await _send(client, device_id="d1")).status_code == 200
    for _ in range(6):
        r = await _send(client, device_id="d1")
        assert r.json()["code"] == "otp_device_limit"
    # The number's 5-per-hour budget is untouched by the refused requests.
    for _ in range(4):
        assert (await _send(client, device_id=None)).status_code == 200


async def test_wrong_code_lock_is_scoped_to_the_device(client: AsyncClient) -> None:
    """A stranger guessing from their phone locks themselves, not the owner."""
    code = (await _send(client, device_id="attacker")).json()["dev_code"]
    for _ in range(3):
        r = await client.post(
            "/v1/auth/verify",
            json={"phone": PHONE, "code": _wrong(code), "device_id": "attacker"},
        )
    assert r.status_code == 429 and r.json()["code"] == "otp_locked"
    # The attacker's device is locked...
    assert (await _send(client, device_id="attacker")).status_code == 429
    # ...the owner's is not, and the burned code is gone: a fresh one works.
    fresh = (await _send(client, device_id="owner")).json()["dev_code"]
    ok = await client.post(
        "/v1/auth/verify", json={"phone": PHONE, "code": fresh, "device_id": "owner"}
    )
    assert ok.status_code == 200, ok.text


async def test_code_burns_after_max_attempts_across_devices(client: AsyncClient) -> None:
    code = (await _send(client)).json()["dev_code"]
    for dev in ("a", "b", "c"):
        await client.post(
            "/v1/auth/verify", json={"phone": PHONE, "code": _wrong(code), "device_id": dev}
        )
    # The right code from a fourth device no longer works: the code is burned.
    r = await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code, "device_id": "d"})
    assert r.status_code == 400 and r.json()["code"] == "otp_expired"
    async with get_sessionmaker()() as db:
        row = (await db.execute(select(OtpRequest))).scalar_one()
        assert row.attempts == 3 and row.consumed_at is None


async def test_lock_backs_off_exponentially(client: AsyncClient) -> None:
    from app.core.kv import get_kv

    retry: list[int] = []
    for _ in range(2):
        await get_kv().delete(f"otp:lock:{PHONE}|dev:x")
        code = (await _send(client, device_id="x")).json()["dev_code"]
        for _ in range(3):
            r = await client.post(
                "/v1/auth/verify", json={"phone": PHONE, "code": _wrong(code), "device_id": "x"}
            )
        retry.append(r.json()["details"]["retry_after"])
    s = get_settings()
    assert retry == [s.OTP_LOCK_SECONDS, 2 * s.OTP_LOCK_SECONDS]


async def test_concurrent_correct_verifies_log_in_once(client: AsyncClient) -> None:
    code = (await _send(client)).json()["dev_code"]
    results = await asyncio.gather(
        *[client.post("/v1/auth/verify", json={"phone": PHONE, "code": code}) for _ in range(4)]
    )
    assert sorted(r.status_code for r in results).count(200) == 1


async def test_provider_failure_is_503(client: AsyncClient) -> None:
    class Broken:
        async def send(self, phone: str, code: str, channel: str = "sms") -> None:
            raise NotImplementedError("msg91 not wired")

    otp_svc.set_otp_provider(Broken())
    try:
        r = await _send(client)
        assert r.status_code == 503 and r.json()["code"] == "otp_unavailable"
    finally:
        otp_svc.set_otp_provider(None)


async def test_parallel_refreshes_get_the_same_pair(client: AsyncClient) -> None:
    code = (await _send(client)).json()["dev_code"]
    tokens = (await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})).json()
    results = await asyncio.gather(
        *[
            client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
            for _ in range(3)
        ]
    )
    assert [r.status_code for r in results] == [200, 200, 200]
    assert len({r.json()["refresh_token"] for r in results}) == 1
    new = results[0].json()
    me = await client.get("/v1/me", headers={"Authorization": f"Bearer {new['access_token']}"})
    assert me.status_code == 200
    nxt = await client.post("/v1/auth/refresh", json={"refresh_token": new["refresh_token"]})
    assert nxt.status_code == 200


def test_client_ip_ignores_untrusted_forwarded_for() -> None:
    from starlette.requests import Request

    def req(peer: str, xff: str | None) -> Request:
        headers = [(b"x-forwarded-for", xff.encode())] if xff else []
        return Request({"type": "http", "client": (peer, 1234), "headers": headers})

    assert client_ip(req("203.0.113.9", "1.1.1.1")) == "203.0.113.9"  # peer not a proxy
    assert client_ip(req("172.18.0.5", "1.1.1.1, 9.9.9.9")) == "9.9.9.9"
    assert client_ip(req("172.18.0.5", "1.1.1.1, 9.9.9.9, 10.0.0.2")) == "9.9.9.9"
    assert client_ip(req("172.18.0.5", None)) == "172.18.0.5"
