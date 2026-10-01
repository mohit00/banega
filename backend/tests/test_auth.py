from __future__ import annotations

from httpx import AsyncClient

from app.core.config import get_settings
from app.core.kv import MemoryStore, get_kv
from tests.conftest import Login

PHONE = "+919811111111"


async def _otp(client: AsyncClient, phone: str = PHONE, device_id: str | None = None) -> str:
    r = await client.post("/v1/auth/otp", json={"phone": phone, "device_id": device_id})
    assert r.status_code == 200, r.text
    return str(r.json()["dev_code"])


async def test_otp_flow_creates_user_and_returns_tokens(client: AsyncClient) -> None:
    code = await _otp(client)
    assert len(code) == 6
    r = await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["is_new_user"] is True
    me = await client.get("/v1/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.status_code == 200
    assert me.json()["user"]["phone"] == PHONE
    assert me.json()["membership"] is None


async def test_phone_is_normalised_to_e164(client: AsyncClient) -> None:
    code = await _otp(client, "98111 11111")
    r = await client.post("/v1/auth/verify", json={"phone": "+91 98111-11111", "code": code})
    assert r.status_code == 200


async def test_code_is_single_use(client: AsyncClient) -> None:
    code = await _otp(client)
    assert (await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})).is_success
    r = await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})
    assert r.status_code == 400
    assert r.json()["code"] == "otp_expired"


async def test_three_wrong_codes_lock_the_number(client: AsyncClient) -> None:
    code = await _otp(client)
    wrong = "000000" if code != "000000" else "111111"
    r1 = await client.post("/v1/auth/verify", json={"phone": PHONE, "code": wrong})
    assert r1.status_code == 400
    assert r1.json()["details"]["attempts_left"] == 2
    await client.post("/v1/auth/verify", json={"phone": PHONE, "code": wrong})
    r3 = await client.post("/v1/auth/verify", json={"phone": PHONE, "code": wrong})
    assert r3.status_code == 429
    assert r3.json()["code"] == "otp_locked"
    # Even the right code is refused while locked, and so are new sends.
    r4 = await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})
    assert r4.status_code == 429
    r5 = await client.post("/v1/auth/otp", json={"phone": PHONE})
    assert r5.status_code == 429


async def test_rate_limit_five_per_number_per_hour(client: AsyncClient) -> None:
    for _ in range(5):
        await _otp(client)
    r = await client.post("/v1/auth/otp", json={"phone": PHONE})
    assert r.status_code == 429
    assert r.json()["code"] == "otp_number_limit"


async def test_rate_limit_ten_per_device_per_day(client: AsyncClient) -> None:
    for i in range(10):
        await _otp(client, f"+9198222222{i:02d}", device_id="dev-1")
    r = await client.post(
        "/v1/auth/otp", json={"phone": "+919833333333"}, headers={"X-Device-Id": "dev-1"}
    )
    assert r.status_code == 429
    assert r.json()["code"] == "otp_device_limit"


async def test_resend_cooldown(client: AsyncClient) -> None:
    s = get_settings()
    s.OTP_RESEND_SECONDS = 30
    try:
        await _otp(client)
        r = await client.post("/v1/auth/otp", json={"phone": PHONE})
        assert r.status_code == 429
        assert r.json()["code"] == "otp_resend_too_soon"
    finally:
        s.OTP_RESEND_SECONDS = 0


async def test_refresh_rotates_and_detects_reuse(client: AsyncClient) -> None:
    code = await _otp(client)
    tokens = (await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})).json()
    r = await client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert r.status_code == 200
    new = r.json()
    assert new["refresh_token"] != tokens["refresh_token"]
    # Within the grace window a parallel refresh with the old token gets the same pair.
    again = await client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert again.status_code == 200 and again.json() == new
    # After it, replaying the old refresh token revokes the session.
    get_kv_store().clear()  # the grace entry expires (60 s)
    replay = await client.post("/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert replay.status_code == 401
    assert replay.json()["code"] == "refresh_reused"
    after = await client.post("/v1/auth/refresh", json={"refresh_token": new["refresh_token"]})
    assert after.status_code == 401


async def test_access_token_cannot_be_used_as_refresh(client: AsyncClient) -> None:
    code = await _otp(client)
    tokens = (await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})).json()
    r = await client.post("/v1/auth/refresh", json={"refresh_token": tokens["access_token"]})
    assert r.status_code == 401


async def test_logout_revokes_only_this_session(client: AsyncClient, login: Login) -> None:
    a = await login(PHONE)
    b = await login(PHONE)
    assert (await client.post("/v1/auth/logout", headers=a)).status_code == 204
    assert (await client.get("/v1/me", headers=a)).status_code == 401
    assert (await client.get("/v1/me", headers=b)).status_code == 200


async def test_logout_all(client: AsyncClient, login: Login) -> None:
    a = await login(PHONE)
    b = await login(PHONE)
    assert (await client.post("/v1/auth/logout-all", headers=a)).status_code == 204
    assert (await client.get("/v1/me", headers=a)).status_code == 401
    assert (await client.get("/v1/me", headers=b)).status_code == 401


async def test_delete_me_and_restore(client: AsyncClient, login: Login) -> None:
    h = await login(PHONE)
    r = await client.delete("/v1/me", headers=h)
    assert r.status_code == 200
    assert r.json()["undo_until"]
    assert (await client.get("/v1/me", headers=h)).status_code == 401
    code = await _otp(client)
    tokens = (await client.post("/v1/auth/verify", json={"phone": PHONE, "code": code})).json()
    assert tokens["pending_deletion"] is True
    h2 = {"Authorization": f"Bearer {tokens['access_token']}"}
    r = await client.post("/v1/me/restore", headers=h2)
    assert r.status_code == 200
    assert r.json()["user"]["deleted_at"] is None


async def test_devices_register_and_delete(client: AsyncClient, login: Login) -> None:
    h = await login(PHONE)
    body = {"platform": "android", "push_token": "fcm-token-123456", "app_version": "1.0.0"}
    r = await client.post("/v1/devices", json=body, headers=h)
    assert r.status_code == 201
    device_id = r.json()["id"]
    other = await login("+919844444444")
    assert (await client.delete(f"/v1/devices/{device_id}", headers=other)).status_code == 404
    assert (await client.delete(f"/v1/devices/{device_id}", headers=h)).status_code == 204


def get_kv_store() -> MemoryStore:
    kv = get_kv()
    assert isinstance(kv, MemoryStore)
    return kv
