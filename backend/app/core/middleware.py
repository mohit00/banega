"""Pure-ASGI middlewares: request id + access log, and Idempotency-Key replay."""

from __future__ import annotations

import asyncio
import contextlib
import hashlib
import json
import time
import uuid

import structlog
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import get_settings
from app.core.errors import error_body
from app.core.kv import get_kv
from app.core.security import decode_token

log = structlog.get_logger("app.access")

REQUEST_ID_HEADER = b"x-request-id"


def _header(scope: Scope, name: bytes) -> str | None:
    for k, v in scope.get("headers", []):
        if k.lower() == name:
            return str(v.decode("latin-1"))
    return None


class RequestIdMiddleware:
    """Binds a request id (incoming X-Request-ID or a new uuid) to logs and echoes it back."""

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        incoming = _header(scope, REQUEST_ID_HEADER)
        request_id = incoming if incoming and len(incoming) <= 128 else uuid.uuid4().hex
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)
        start = time.perf_counter()
        status_code = 500

        async def send_wrapper(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                headers = list(message.get("headers", []))
                headers.append((REQUEST_ID_HEADER, request_id.encode()))
                message["headers"] = headers
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            log.info(
                "request",
                method=scope.get("method"),
                path=scope.get("path"),
                status=status_code,
                duration_ms=round((time.perf_counter() - start) * 1000, 1),
            )


# Responses worth replaying: success, and client errors that repeat identically for the same
# request. 401/402/403/409/412/429 depend on state that can change (a login, a payment, a
# race, a rate window), so a retry must run again.
STORABLE_4XX = frozenset({400, 404, 422})
# Never cached: token responses must not sit in Redis under a shared "anon" key.
SKIP_PREFIXES = ("/v1/auth/",)


def _storable(status: int) -> bool:
    return 200 <= status < 300 or status in STORABLE_4XX


class IdempotencyMiddleware:
    """Replays the stored response for a repeated ``POST`` with the same Idempotency-Key.

    Key scope: caller (JWT subject, or a hash of the Authorization header when absent/invalid)
    + path + key. A different body with the same key is a 422; a concurrent duplicate while
    the first is still running is a 409. The "pending" marker is a short lease
    (IDEMPOTENCY_LEASE_SECONDS) renewed while the request runs, so a crashed worker frees the
    key quickly. Only 2xx and 400/404/422 are stored. ``/v1/auth/*`` is never cached. When
    the store (Redis) is unavailable the request runs without idempotency (fail open, logged).
    """

    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("method") != "POST":
            await self.app(scope, receive, send)
            return
        idem_key = _header(scope, b"idempotency-key")
        path = str(scope.get("path") or "")
        if not idem_key or path.startswith(SKIP_PREFIXES):
            await self.app(scope, receive, send)
            return

        # Buffer the request body so it can be fingerprinted and replayed to the app.
        chunks: list[bytes] = []
        more = True
        while more:
            message = await receive()
            if message["type"] != "http.request":
                break
            chunks.append(message.get("body", b""))
            more = message.get("more_body", False)
        body = b"".join(chunks)
        body_hash = hashlib.sha256(body).hexdigest()

        caller = _caller(scope)
        store_key = "idem:" + hashlib.sha256(f"{caller}|{path}|{idem_key}".encode()).hexdigest()
        kv = get_kv()
        settings = get_settings()
        pending = json.dumps({"state": "pending", "body_hash": body_hash})

        try:
            existing = await kv.get(store_key)
            claimed = existing is None and await kv.set(
                store_key, pending, settings.IDEMPOTENCY_LEASE_SECONDS, nx=True
            )
            if not claimed and existing is None:
                existing = await kv.get(store_key)
        except Exception as exc:  # Redis down: run the request, no replay protection
            log.warning("idempotency_store_unavailable", error=type(exc).__name__)
            await self.app(scope, _replay(body), send)
            return

        if claimed:
            await self._run_and_store(scope, body, send, store_key, body_hash, pending)
            return
        record = json.loads(existing or "{}")
        if record.get("body_hash") != body_hash:
            await _send_json(
                send,
                422,
                error_body(
                    "idempotency_key_reused",
                    "This Idempotency-Key was used with a different request.",
                    "Ye Idempotency-Key kisi aur request ke saath use ho chuki hai.",
                ),
            )
            return
        if record.get("state") != "done":
            await _send_json(
                send,
                409,
                error_body(
                    "idempotency_in_progress",
                    "The original request is still being processed.",
                    "Pehli request abhi chal rahi hai.",
                ),
            )
            return
        headers = [(k.encode(), v.encode()) for k, v in record.get("headers", [])]
        headers.append((b"idempotent-replayed", b"true"))
        await send({"type": "http.response.start", "status": record["status"], "headers": headers})
        await send({"type": "http.response.body", "body": record["body"].encode()})

    async def _run_and_store(
        self, scope: Scope, body: bytes, send: Send, store_key: str, body_hash: str, pending: str
    ) -> None:
        settings = get_settings()
        lease = settings.IDEMPOTENCY_LEASE_SECONDS
        kv = get_kv()
        status_code = 500
        resp_headers: list[tuple[str, str]] = []
        resp_body: list[bytes] = []

        async def capture(message: Message) -> None:
            nonlocal status_code
            if message["type"] == "http.response.start":
                status_code = message["status"]
                resp_headers.extend(
                    (k.decode("latin-1"), v.decode("latin-1"))
                    for k, v in message.get("headers", [])
                    if k.lower() in (b"content-type", b"location")
                )
            elif message["type"] == "http.response.body":
                resp_body.append(message.get("body", b""))
            await send(message)

        async def renew() -> None:
            while True:
                await asyncio.sleep(max(1.0, lease / 3))
                try:
                    await kv.set(store_key, pending, lease)
                except Exception:
                    return

        renewer = asyncio.create_task(renew())
        try:
            await self.app(scope, _replay(body), capture)
        except BaseException:
            renewer.cancel()
            with contextlib.suppress(Exception):
                await kv.delete(store_key)
            raise
        renewer.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await renewer
        try:
            if not _storable(status_code):
                await kv.delete(store_key)
                return
            await kv.set(
                store_key,
                json.dumps(
                    {
                        "state": "done",
                        "body_hash": body_hash,
                        "status": status_code,
                        "headers": resp_headers,
                        "body": b"".join(resp_body).decode("utf-8", errors="replace"),
                    }
                ),
                settings.IDEMPOTENCY_TTL_SECONDS,
            )
        except Exception as exc:  # the response already went out; only replay is lost
            log.warning("idempotency_store_failed", error=type(exc).__name__)


def _replay(body: bytes) -> Receive:
    sent = False

    async def receive() -> Message:
        nonlocal sent
        if not sent:
            sent = True
            return {"type": "http.request", "body": body, "more_body": False}
        return {"type": "http.disconnect"}

    return receive


def _caller(scope: Scope) -> str:
    auth = _header(scope, b"authorization")
    if not auth:
        return "anon"
    token = auth.split(" ", 1)[-1].strip()
    try:
        return f"user:{decode_token(token, 'access').user_id}"
    except Exception:
        return "auth:" + hashlib.sha256(auth.encode()).hexdigest()


async def _send_json(send: Send, status: int, payload: dict[str, object]) -> None:
    body = json.dumps(payload).encode()
    await send(
        {
            "type": "http.response.start",
            "status": status,
            "headers": [(b"content-type", b"application/json")],
        }
    )
    await send({"type": "http.response.body", "body": body})
