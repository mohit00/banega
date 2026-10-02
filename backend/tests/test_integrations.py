"""Production integrations with mocked transports (no network): MSG91 OTP, FCM HTTP v1 push
(through the outbox), Google Play Developer API verification + authoritative RTDN, the
service-account loader and the production settings guards for all three."""

from __future__ import annotations

import base64
import json
import uuid
from collections.abc import Callable, Iterator
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import pytest
from httpx import AsyncClient
from pydantic import ValidationError
from sqlalchemy import select, update
from structlog.testing import capture_logs

from app.core.config import Settings, get_settings
from app.core.db import get_sessionmaker
from app.core.security import utcnow
from app.core.sentry import scrub_text
from app.models import Device, PushOutbox, Subscription, SubscriptionStatus
from app.services import google_sa, push_outbox
from app.services import notifications as notify
from app.services import otp as otp_svc
from app.services import subscription as sub_svc
from app.services.notifications import FcmPush, PushMessage, PushResult
from app.services.otp import Msg91OtpProvider, OtpDeliveryError
from app.services.subscription import PlayDeveloperApi, StoreApiVerifier, play_state
from tests.conftest import Login

S = SubscriptionStatus
Handler = Callable[[httpx.Request], httpx.Response]


class Recorder:
    """httpx.MockTransport that records every request and answers from a handler."""

    def __init__(self, handler: Handler) -> None:
        self.requests: list[httpx.Request] = []
        self.handler = handler
        self.transport = httpx.MockTransport(self._handle)

    def _handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return self.handler(request)


class FakeTokens:
    def __init__(self) -> None:
        self.calls = 0

    async def token(self) -> str:
        self.calls += 1
        return "ya29.fake-access-token"


def ok(body: dict[str, Any] | None = None) -> httpx.Response:
    return httpx.Response(200, json=body if body is not None else {"type": "success"})


# ---- MSG91 -----------------------------------------------------------------------------------


def msg91(rec: Recorder, **kw: Any) -> Msg91OtpProvider:
    return Msg91OtpProvider("auth-key-123", "tmpl-1", transport=rec.transport, backoff=0, **kw)


async def test_msg91_sends_our_code_with_the_dlt_template() -> None:
    rec = Recorder(lambda r: ok({"type": "success", "request_id": "abc"}))
    with capture_logs() as logs:
        await msg91(rec, sender_id="KORNEA").send("+919876543210", "482913")
    (req,) = rec.requests
    assert req.method == "POST"
    assert req.url.path == "/api/v5/otp"
    q = req.url.params
    assert q["template_id"] == "tmpl-1" and q["mobile"] == "919876543210"
    assert q["otp"] == "482913" and q["otp_expiry"] == "5" and q["sender"] == "KORNEA"
    # The key travels in a header, never in the URL.
    assert req.headers["authkey"] == "auth-key-123" and "authkey" not in q
    assert "482913" not in json.dumps(logs)


async def test_msg91_voice_fallback_uses_the_retry_endpoint() -> None:
    rec = Recorder(lambda r: ok())
    await msg91(rec, voice_fallback=True).send("+919876543210", "111222", "voice")
    assert [r.url.path for r in rec.requests] == ["/api/v5/otp", "/api/v5/otp/retry"]
    retry = rec.requests[1]
    assert retry.method == "GET"
    assert retry.url.params["retrytype"] == "voice"
    assert retry.url.params["mobile"] == "919876543210"
    assert "otp" not in retry.url.params

    # Fallback off: a voice request is delivered by SMS only.
    rec = Recorder(lambda r: ok())
    await msg91(rec).send("+919876543210", "111222", "voice")
    assert [r.url.path for r in rec.requests] == ["/api/v5/otp"]

    # A failed call after the SMS went out is not an error (the SMS carries the same code).
    rec = Recorder(
        lambda r: ok() if r.url.path.endswith("/otp") else ok({"type": "error", "message": "x"})
    )
    await msg91(rec, voice_fallback=True).send("+919876543210", "111222", "voice")


@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, json={"type": "error", "message": "Invalid authkey"}),
        httpx.Response(401, json={"type": "error", "message": "AuthenticationFailure"}),
        httpx.Response(400, text="not json"),
    ],
)
async def test_msg91_rejections_raise(response: httpx.Response) -> None:
    rec = Recorder(lambda r: response)
    with pytest.raises(OtpDeliveryError):
        await msg91(rec).send("+919876543210", "123456")
    assert len(rec.requests) == 1  # 4xx / error bodies are not retried


async def test_msg91_retries_timeouts_and_5xx_once() -> None:
    answers: list[Any] = [httpx.ConnectTimeout("slow"), ok()]

    def flaky(request: httpx.Request) -> httpx.Response:
        a = answers.pop(0)
        if isinstance(a, Exception):
            raise a
        return a  # type: ignore[no-any-return]

    rec = Recorder(flaky)
    await msg91(rec).send("+919876543210", "123456")
    assert len(rec.requests) == 2

    rec = Recorder(lambda r: httpx.Response(503))
    with pytest.raises(OtpDeliveryError):
        await msg91(rec).send("+919876543210", "123456")
    assert len(rec.requests) == 2


async def test_msg91_failure_is_503_otp_unavailable(client: AsyncClient) -> None:
    rec = Recorder(lambda r: ok({"type": "error", "message": "template not approved"}))
    otp_svc.set_otp_provider(msg91(rec))
    try:
        r = await client.post("/v1/auth/otp", json={"phone": "+919800000301"})
        assert r.status_code == 503 and r.json()["code"] == "otp_unavailable"
        rec.handler = lambda r: ok()
        r = await client.post("/v1/auth/otp", json={"phone": "+919800000301"})
        assert r.status_code == 200
        sent = rec.requests[-1].url.params["otp"]
        assert len(sent) == 6 and sent.isdigit()
    finally:
        otp_svc.set_otp_provider(None)


def test_msg91_is_selected_by_configuration(monkeypatch: pytest.MonkeyPatch) -> None:
    s = get_settings()
    monkeypatch.setattr(s, "OTP_PROVIDER", "msg91")
    otp_svc.set_otp_provider(None)
    try:
        assert isinstance(otp_svc.get_otp_provider(), otp_svc.NotConfiguredProvider)
        otp_svc.set_otp_provider(None)
        monkeypatch.setattr(s, "MSG91_AUTH_KEY", "k")
        monkeypatch.setattr(s, "MSG91_OTP_TEMPLATE_ID", "t")
        monkeypatch.setattr(s, "OTP_VOICE_FALLBACK", True)
        p = otp_svc.get_otp_provider()
        assert isinstance(p, Msg91OtpProvider) and p.voice_fallback and p.expiry_minutes == 5
    finally:
        otp_svc.set_otp_provider(None)


def test_sentry_scrubs_query_string_secrets() -> None:
    url = "https://control.msg91.com/api/v5/otp?template_id=t&mobile=919876543210&otp=482913"
    out = scrub_text(url)
    assert "482913" not in out and "919876543210" not in out and "template_id=t" in out


# ---- FCM -------------------------------------------------------------------------------------


def fcm_error(status: int, code: str, *, error_code: str = "", field: str = "", msg: str = ""):  # type: ignore[no-untyped-def]
    details: list[dict[str, Any]] = []
    if error_code:
        details.append(
            {
                "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                "errorCode": error_code,
            }
        )
    if field:
        details.append(
            {
                "@type": "type.googleapis.com/google.rpc.BadRequest",
                "fieldViolations": [{"field": field, "description": "bad"}],
            }
        )
    return httpx.Response(
        status, json={"error": {"code": status, "message": msg, "status": code, "details": details}}
    )


def by_token(answers: dict[str, httpx.Response]) -> Handler:
    def handle(request: httpx.Request) -> httpx.Response:
        token = json.loads(request.content)["message"]["token"]
        return answers[token]

    return handle


def message(*tokens: str) -> PushMessage:
    return PushMessage(
        user_id=uuid.uuid4(),
        tokens=tuple(("android", t) for t in tokens),
        title="Naya ticket: Lunch",
        body="Dal, chawal",
        data={"event": "ticket_created", "ticket_id": "t-1", "_retry_tokens": "x"},
    )


async def test_fcm_v1_request_shape() -> None:
    rec = Recorder(lambda r: ok({"name": "projects/p/messages/1"}))
    tokens = FakeTokens()
    result = await FcmPush("banega-prod", tokens, transport=rec.transport).send(
        message("tok-a", "tok-b")
    )
    assert result == PushResult()
    assert len(rec.requests) == 2  # one request per device
    req = rec.requests[0]
    assert str(req.url) == "https://fcm.googleapis.com/v1/projects/banega-prod/messages:send"
    assert req.headers["Authorization"] == "Bearer ya29.fake-access-token"
    body = json.loads(req.content)["message"]
    assert body["token"] == "tok-a"
    assert body["notification"] == {"title": "Naya ticket: Lunch", "body": "Dal, chawal"}
    # Internal keys never reach the device.
    assert body["data"] == {"event": "ticket_created", "ticket_id": "t-1"}
    assert body["android"]["priority"] == "high"


async def test_fcm_classifies_per_device_errors() -> None:
    rec = Recorder(
        by_token(
            {
                "ok": ok(),
                "gone": fcm_error(404, "NOT_FOUND", error_code="UNREGISTERED"),
                "bad-token": fcm_error(
                    400, "INVALID_ARGUMENT", error_code="INVALID_ARGUMENT", field="message.token"
                ),
                "bad-payload": fcm_error(
                    400, "INVALID_ARGUMENT", field="message.data", msg="data too big"
                ),
                "busy": fcm_error(503, "UNAVAILABLE", error_code="UNAVAILABLE"),
                "quota": fcm_error(429, "RESOURCE_EXHAUSTED", error_code="QUOTA_EXCEEDED"),
                "mismatch": fcm_error(403, "PERMISSION_DENIED", error_code="SENDER_ID_MISMATCH"),
            }
        )
    )
    result = await FcmPush("p", FakeTokens(), transport=rec.transport).send(
        message("ok", "gone", "bad-token", "bad-payload", "busy", "quota", "mismatch")
    )
    assert result is not None
    assert set(result.dead) == {"gone", "bad-token", "mismatch"}
    assert {t for _, t in result.retry} == {"busy", "quota"}


async def test_fcm_network_error_is_retried() -> None:
    def boom(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    rec = Recorder(boom)
    result = await FcmPush("p", FakeTokens(), transport=rec.transport).send(message("a"))
    assert result == PushResult(retry=(("android", "a"),))


def test_fcm_from_settings_reads_the_service_account(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Any
) -> None:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import rsa

    pem = (
        rsa.generate_private_key(public_exponent=65537, key_size=2048)
        .private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        .decode()
    )
    key = tmp_path / "fcm.json"
    info = {**SA_INFO, "private_key": pem, "token_uri": "https://oauth2.googleapis.com/token"}
    key.write_text(json.dumps(info), encoding="utf-8")
    s = get_settings()
    monkeypatch.setattr(s, "FCM_SERVICE_ACCOUNT_FILE", str(key))
    monkeypatch.setattr(s, "FCM_PROJECT_ID", "")
    push = FcmPush.from_settings()
    assert push.project_id == "banega-test"
    assert isinstance(push.tokens, google_sa.GoogleTokenSource)
    monkeypatch.setattr(s, "FCM_PROJECT_ID", "override")
    assert FcmPush.from_settings().project_id == "override"


@pytest.fixture
def fcm_recorder() -> Iterator[dict[str, Any]]:
    state: dict[str, Any] = {"answers": {}}

    def handle(request: httpx.Request) -> httpx.Response:
        token = json.loads(request.content)["message"]["token"]
        return state["answers"].get(token, ok())

    rec = Recorder(handle)
    state["rec"] = rec
    notify.set_push(FcmPush("p", FakeTokens(), transport=rec.transport))
    yield state
    notify.set_push(None)


async def test_outbox_deletes_dead_tokens_and_retries_only_failed_ones_with_backoff(
    client: AsyncClient, login: Login, fcm_recorder: dict[str, Any]
) -> None:
    headers = await login("+919800000311")
    for token in ("tok-good", "tok-gone", "tok-busy"):
        r = await client.post(
            "/v1/devices", json={"platform": "android", "push_token": token}, headers=headers
        )
        assert r.status_code == 201
    async with get_sessionmaker()() as db:
        user_id = (await db.execute(select(Device.user_id).limit(1))).scalar_one()
    fcm_recorder["answers"] = {
        "tok-gone": fcm_error(404, "NOT_FOUND", error_code="UNREGISTERED"),
        "tok-busy": fcm_error(503, "UNAVAILABLE"),
    }
    async with get_sessionmaker()() as db:
        db.add(
            PushOutbox(
                user_id=user_id,
                event="ticket_created",
                title="Naya ticket",
                body="Dal",
                data={"event": "ticket_created", "ticket_id": "t-9"},
                created_at=utcnow(),
            )
        )
        await db.commit()

    rec: Recorder = fcm_recorder["rec"]
    result = await push_outbox.flush()
    assert result["dead_tokens"] == 1 and result["sent"] == 0
    assert len(rec.requests) == 3
    async with get_sessionmaker()() as db:
        tokens = set((await db.execute(select(Device.push_token))).scalars())
        row = (await db.execute(select(PushOutbox))).scalar_one()
    assert tokens == {"tok-good", "tok-busy"}
    assert row.sent_at is None and row.attempts == 1
    assert row.data[push_outbox.RETRY_KEY] == ["tok-busy"]

    # Backoff: not due again yet.
    await push_outbox.flush()
    assert len(rec.requests) == 3

    # A minute later only the failed device is retried, and it now succeeds.
    fcm_recorder["answers"] = {}
    async with get_sessionmaker()() as db:
        await db.execute(update(PushOutbox).values(created_at=utcnow() - timedelta(seconds=61)))
        await db.commit()
    result = await push_outbox.flush()
    assert result["sent"] == 1
    assert [json.loads(r.content)["message"]["token"] for r in rec.requests[3:]] == ["tok-busy"]
    sent = json.loads(rec.requests[3].content)["message"]["data"]
    assert sent == {"event": "ticket_created", "ticket_id": "t-9"}


def test_backoff_schedule() -> None:
    now = datetime(2026, 10, 1, 12, 0, tzinfo=UTC)
    row = PushOutbox(created_at=now, attempts=0)
    assert push_outbox.due(row, now)
    row.attempts = 1
    assert not push_outbox.due(row, now + timedelta(seconds=59))
    assert push_outbox.due(row, now + timedelta(seconds=60))
    row.attempts = 4
    assert not push_outbox.due(row, now + timedelta(minutes=59))
    assert push_outbox.due(row, now + timedelta(hours=1))


# ---- Google Play -----------------------------------------------------------------------------

NOW = datetime(2026, 10, 2, 10, 0, tzinfo=UTC)
PRODUCTS = frozenset({"banega_weekly_50"})


def sub_v2(state: str, *, expiry: str = "2026-10-09T10:00:00.123456789Z", **extra: Any) -> dict:  # type: ignore[type-arg]
    return {
        "kind": "androidpublisher#subscriptionPurchaseV2",
        "subscriptionState": state,
        "acknowledgementState": "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        "lineItems": [
            {
                "productId": "banega_weekly_50",
                "expiryTime": expiry,
                "offerDetails": {"basePlanId": "weekly"},
            }
        ],
        **extra,
    }


@pytest.mark.parametrize(
    ("state", "expected"),
    [
        ("SUBSCRIPTION_STATE_ACTIVE", S.active),
        ("SUBSCRIPTION_STATE_CANCELED", S.active),  # access until expiry
        ("SUBSCRIPTION_STATE_IN_GRACE_PERIOD", S.grace),
        ("SUBSCRIPTION_STATE_ON_HOLD", S.expired),
        ("SUBSCRIPTION_STATE_PAUSED", S.expired),
        ("SUBSCRIPTION_STATE_EXPIRED", S.expired),
    ],
)
def test_play_state_mapping(state: str, expected: SubscriptionStatus) -> None:
    st = play_state(sub_v2(state), "tok", PRODUCTS, NOW)
    assert st.status == expected
    assert st.renews_at == datetime(2026, 10, 9, 10, 0, 0, 123456, tzinfo=UTC)
    assert st.product_id == "banega_weekly_50" and st.purchase_token == "tok"


def test_play_state_edge_cases() -> None:
    past = "2026-10-01T10:00:00Z"
    assert (
        play_state(sub_v2("SUBSCRIPTION_STATE_CANCELED", expiry=past), "t", PRODUCTS, NOW).status
        == S.expired
    )
    with pytest.raises(sub_svc.AppError) as e:
        play_state(sub_v2("SUBSCRIPTION_STATE_PENDING"), "t", PRODUCTS, NOW)
    assert e.value.code == "purchase_pending" and e.value.status_code == 409
    for bad in ("SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED", "SUBSCRIPTION_STATE_UNSPECIFIED"):
        with pytest.raises(sub_svc.AppError, match="store could not confirm"):
            play_state(sub_v2(bad), "t", PRODUCTS, NOW)
    # A product we do not sell is not a Banega plan.
    with pytest.raises(sub_svc.AppError):
        play_state(sub_v2("SUBSCRIPTION_STATE_ACTIVE"), "t", frozenset({"other"}), NOW)
    linked = sub_v2("SUBSCRIPTION_STATE_ACTIVE", linkedPurchaseToken="old-tok")
    assert play_state(linked, "t", PRODUCTS, NOW).linked_purchase_token == "old-tok"


def play_api(rec: Recorder) -> PlayDeveloperApi:
    return PlayDeveloperApi("in.kornea.banega", PRODUCTS, FakeTokens(), transport=rec.transport)


async def test_play_verify_reads_subscriptionsv2_and_acknowledges() -> None:
    body = sub_v2("SUBSCRIPTION_STATE_ACTIVE", acknowledgementState="ACKNOWLEDGEMENT_STATE_PENDING")
    rec = Recorder(lambda r: ok(body) if r.method == "GET" else ok({}))
    state = await StoreApiVerifier(play_api(rec)).verify(
        "play", receipt=None, purchase_token="tok/1", product_id=None, now=NOW
    )
    assert state.status == S.active
    get, ack = rec.requests
    base = (
        "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/in.kornea.banega"
    )
    assert str(get.url) == base + "/purchases/subscriptionsv2/tokens/tok%2F1"
    assert get.headers["Authorization"] == "Bearer ya29.fake-access-token"
    assert ack.method == "POST"
    assert (
        str(ack.url)
        == base + "/purchases/subscriptions/banega_weekly_50/tokens/tok%2F1:acknowledge"
    )

    # Already acknowledged: no second call.
    rec = Recorder(lambda r: ok(sub_v2("SUBSCRIPTION_STATE_ACTIVE")))
    await StoreApiVerifier(play_api(rec)).verify(
        "play", receipt=None, purchase_token="t", product_id=None, now=NOW
    )
    assert len(rec.requests) == 1


@pytest.mark.parametrize(
    ("status", "code"),
    [
        (404, "receipt_invalid"),
        (410, "receipt_invalid"),
        (401, "store_verification_unavailable"),
        (403, "store_verification_unavailable"),
        (500, "store_verification_unavailable"),
    ],
)
async def test_play_api_errors(status: int, code: str) -> None:
    rec = Recorder(lambda r: httpx.Response(status, json={"error": {"code": status}}))
    with pytest.raises(sub_svc.AppError) as e:
        await StoreApiVerifier(play_api(rec)).verify(
            "play", receipt=None, purchase_token="t", product_id=None, now=NOW
        )
    assert e.value.code == code


async def test_store_api_verifier_without_credentials_is_503(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(get_settings(), "PLAY_SERVICE_ACCOUNT_FILE", "")
    monkeypatch.setattr(get_settings(), "PLAY_SERVICE_ACCOUNT_JSON", "")
    with pytest.raises(sub_svc.AppError) as e:
        await StoreApiVerifier().verify(
            "play", receipt=None, purchase_token="t", product_id=None, now=NOW
        )
    assert e.value.status_code == 503
    monkeypatch.setattr(get_settings(), "APPSTORE_ENABLED", False)
    with pytest.raises(sub_svc.AppError) as e:
        await StoreApiVerifier().verify(
            "app_store", receipt="r", purchase_token=None, product_id=None, now=NOW
        )
    assert e.value.code == "store_not_supported"


def _pubsub(token: str, ntype: int, at: datetime) -> dict[str, Any]:
    note = {
        "packageName": "in.kornea.banega",
        "eventTimeMillis": str(int(at.timestamp() * 1000)),
        "subscriptionNotification": {
            "notificationType": ntype,
            "purchaseToken": token,
            "subscriptionId": "banega_weekly_50",
        },
    }
    return {"message": {"data": base64.b64encode(json.dumps(note).encode()).decode()}}


async def test_restore_and_rtdn_use_the_play_api(
    client: AsyncClient, make_household: Any, monkeypatch: pytest.MonkeyPatch
) -> None:
    admin = await make_household("+919800000321")
    future = (utcnow() + timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    answers: dict[str, dict[str, Any]] = {
        "tok-1": sub_v2(
            "SUBSCRIPTION_STATE_ACTIVE",
            expiry=future,
            acknowledgementState="ACKNOWLEDGEMENT_STATE_PENDING",
        )
    }

    def handle(request: httpx.Request) -> httpx.Response:
        if request.method == "POST":
            return ok({})
        token = request.url.path.rsplit("/", 1)[-1]
        if token not in answers:
            return httpx.Response(404, json={"error": {"code": 404}})
        return ok(answers[token])

    rec = Recorder(handle)
    sub_svc.set_verifier(StoreApiVerifier(play_api(rec)))
    monkeypatch.setattr(get_settings(), "PLAY_WEBHOOK_SECRET", "s3cret")
    secret = {"X-Webhook-Secret": "s3cret"}
    try:
        r = await client.post(
            "/v1/subscription/restore",
            json={"store": "play", "purchase_token": "tok-1"},
            headers=admin,
        )
        assert r.status_code == 200, r.text
        assert r.json()["status"] == "active" and r.json()["renews_at"].startswith(future[:16])
        assert [q.method for q in rec.requests] == ["GET", "POST"]  # read + acknowledge

        # RTDN says "renewed" but Play says on hold: the API wins.
        answers["tok-1"] = sub_v2("SUBSCRIPTION_STATE_ON_HOLD", expiry=future)
        r = await client.post(
            "/v1/webhooks/play", json=_pubsub("tok-1", 2, utcnow()), headers=secret
        )
        assert r.json()["result"] == "expired"

        # Resubscribe: a new token linked to the old one moves the same household.
        answers["tok-2"] = sub_v2(
            "SUBSCRIPTION_STATE_ACTIVE", expiry=future, linkedPurchaseToken="tok-1"
        )
        r = await client.post(
            "/v1/webhooks/play",
            json=_pubsub("tok-2", 4, utcnow() + timedelta(seconds=1)),
            headers=secret,
        )
        assert r.json()["result"] == "active"
        async with get_sessionmaker()() as db:
            row = (await db.execute(select(Subscription))).scalar_one()
        assert row.purchase_token == "tok-2" and row.status == S.active

        # Pending payment: no change; unknown token: 200 "unknown" (Pub/Sub must not loop).
        answers["tok-3"] = sub_v2("SUBSCRIPTION_STATE_PENDING")
        r = await client.post(
            "/v1/webhooks/play", json=_pubsub("tok-3", 4, utcnow()), headers=secret
        )
        assert r.json()["result"] == "pending"
        r = await client.post(
            "/v1/webhooks/play", json=_pubsub("nope", 4, utcnow()), headers=secret
        )
        assert r.json()["result"] == "unknown"

        # Play API down: 503 so Pub/Sub redelivers later.
        rec.handler = lambda r: httpx.Response(500)
        r = await client.post(
            "/v1/webhooks/play",
            json=_pubsub("tok-2", 2, utcnow() + timedelta(seconds=2)),
            headers=secret,
        )
        assert r.status_code == 503
    finally:
        sub_svc.set_verifier(None)


# ---- service accounts and settings guards ----------------------------------------------------

SA_INFO = {
    "type": "service_account",
    "project_id": "banega-test",
    "client_email": "push@banega-test.iam.gserviceaccount.com",
    "private_key": "-----BEGIN PRIVATE KEY-----\nnot-a-key\n-----END PRIVATE KEY-----\n",
}


def test_load_service_account(tmp_path: Any) -> None:
    path = tmp_path / "sa.json"
    path.write_text(json.dumps(SA_INFO), encoding="utf-8")
    assert google_sa.load_service_account(str(path), "", "FCM")["project_id"] == "banega-test"
    assert google_sa.load_service_account("", json.dumps(SA_INFO), "FCM")["client_email"]
    with pytest.raises(google_sa.ServiceAccountError):
        google_sa.load_service_account("", "", "FCM")
    with pytest.raises(google_sa.ServiceAccountError):
        google_sa.load_service_account(str(tmp_path / "missing.json"), "", "FCM")
    with pytest.raises(google_sa.ServiceAccountError):
        google_sa.load_service_account("", '{"type": "authorized_user"}', "FCM")


PROD: dict[str, Any] = {
    "ENV": "prod",
    "DATABASE_URL": "postgresql+asyncpg://banega:Zx9-long-random-pw@db:5432/banega",
    "REDIS_URL": "redis://:pw@redis:6379/0",
    "JWT_SECRET": "k" * 48,
    "OTP_PROVIDER": "msg91",
    "MSG91_AUTH_KEY": "key",
    "MSG91_OTP_TEMPLATE_ID": "tmpl",
    "STORE_VERIFIER": "store",
    "PLAY_WEBHOOK_SECRET": "play-secret",
    "PLAY_SERVICE_ACCOUNT_JSON": json.dumps(SA_INFO),
    "PUSH_PROVIDER": "fcm",
    "FCM_SERVICE_ACCOUNT_JSON": json.dumps(SA_INFO),
    "APPSTORE_ENABLED": False,
}


def prod(**overrides: Any) -> Settings:
    return Settings(_env_file=None, **{**PROD, **overrides})  # type: ignore[call-arg]


def test_android_only_production_config_boots() -> None:
    s = prod()
    assert not s.APPSTORE_ENABLED and s.play_product_ids == frozenset({"banega_weekly_50"})


@pytest.mark.parametrize(
    ("overrides", "match"),
    [
        ({"MSG91_AUTH_KEY": ""}, "MSG91_AUTH_KEY"),
        ({"MSG91_OTP_TEMPLATE_ID": ""}, "MSG91_OTP_TEMPLATE_ID"),
        ({"OTP_PROVIDER": "twilio"}, "twilio is not implemented"),
        ({"FCM_SERVICE_ACCOUNT_JSON": ""}, "FCM_SERVICE_ACCOUNT_FILE"),
        ({"FCM_SERVICE_ACCOUNT_JSON": "{not json"}, "FCM_SERVICE_ACCOUNT_JSON is not valid"),
        ({"FCM_SERVICE_ACCOUNT_FILE": "/nope/fcm.json"}, "FCM_SERVICE_ACCOUNT_FILE not found"),
        ({"PLAY_SERVICE_ACCOUNT_JSON": ""}, "PLAY_SERVICE_ACCOUNT_FILE"),
        ({"PLAY_SERVICE_ACCOUNT_JSON": '{"a": 1}'}, "not a service-account key"),
        ({"PLAY_PRODUCT_IDS": " , "}, "PLAY_PRODUCT_IDS"),
        ({"APPSTORE_ENABLED": True}, "APPSTORE_BUNDLE_ID"),
    ],
)
def test_integration_guards(overrides: dict[str, Any], match: str) -> None:
    with pytest.raises(ValidationError, match=match):
        prod(**overrides)


def test_noop_push_needs_no_fcm_key() -> None:
    with pytest.warns(UserWarning):
        prod(PUSH_PROVIDER="noop", ALLOW_NOOP_PUSH=True, FCM_SERVICE_ACCOUNT_JSON="")
