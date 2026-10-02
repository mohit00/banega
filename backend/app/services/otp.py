"""OTP delivery provider abstraction (SMS with voice fallback).

The server generates and verifies every code (``api/auth.py``); a provider only delivers
it. ``Msg91OtpProvider`` uses the MSG91 OTP API v5 with our code passed as ``otp`` (MSG91's
own verify endpoint is never used). Any delivery failure raises :class:`OtpDeliveryError`,
which the API maps to 503 ``otp_unavailable``. The code is never logged.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any, Protocol

import httpx
import structlog

from app.core.config import get_settings

log = structlog.get_logger(__name__)
# httpx logs request URLs (with the ?otp= query) at INFO: keep it quiet.
logging.getLogger("httpx").setLevel(logging.WARNING)


class OtpDeliveryError(RuntimeError):
    """The provider did not accept the message (mapped to 503 otp_unavailable)."""


class OtpProvider(Protocol):
    async def send(self, phone: str, code: str, channel: str = "sms") -> None: ...


class DevOtpProvider:
    """Logs the code instead of sending it. The API also returns it when ENV is dev/test."""

    async def send(self, phone: str, code: str, channel: str = "sms") -> None:
        log.info("otp_dev_send", phone=phone, code=code, channel=channel)


class NotConfiguredProvider:
    def __init__(self, name: str) -> None:
        self.name = name

    async def send(self, phone: str, code: str, channel: str = "sms") -> None:
        raise OtpDeliveryError(f"OTP provider {self.name!r} is not configured")


class Msg91OtpProvider:
    """MSG91 OTP API v5 (India; the template must be DLT-approved).

    - SMS: ``POST {base}/otp?template_id=&mobile=91XXXXXXXXXX&otp=<our code>&otp_expiry=<min>``
      with the ``authkey`` header.
    - Voice (``channel="voice"`` and ``voice_fallback``): the SMS send above stores our code
      at MSG91, then ``GET {base}/otp/retry?retrytype=voice&mobile=`` has MSG91 call and read
      it out. A failed voice call after a delivered SMS is logged, not raised.
    - 5 s timeout per call; one retry on timeouts, connection errors and 5xx.
    """

    def __init__(
        self,
        auth_key: str,
        template_id: str,
        *,
        sender_id: str = "",
        voice_fallback: bool = False,
        expiry_seconds: int = 300,
        base_url: str = "https://control.msg91.com/api/v5",
        timeout: float = 5.0,
        retries: int = 1,
        backoff: float = 0.5,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        if not auth_key or not template_id:
            raise OtpDeliveryError("MSG91_AUTH_KEY and MSG91_OTP_TEMPLATE_ID are required")
        self.auth_key = auth_key
        self.template_id = template_id
        self.sender_id = sender_id
        self.voice_fallback = voice_fallback
        self.expiry_minutes = max(1, expiry_seconds // 60)
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.retries = retries
        self.backoff = backoff
        self.transport = transport

    @staticmethod
    def mobile(phone: str) -> str:
        """E.164 (+919876543210) -> MSG91's 919876543210."""
        digits = phone.lstrip("+")
        if not digits.isdigit():
            raise OtpDeliveryError("invalid phone number")
        return digits

    async def send(self, phone: str, code: str, channel: str = "sms") -> None:
        mobile = self.mobile(phone)
        params = {
            "template_id": self.template_id,
            "mobile": mobile,
            "otp": code,
            "otp_expiry": str(self.expiry_minutes),
        }
        if self.sender_id:
            params["sender"] = self.sender_id
        async with self._client() as client:
            await self._call(client, "POST", "/otp", params, json={}, action="send")
            if channel != "voice":
                return
            if not self.voice_fallback:
                log.info("otp_voice_disabled_sent_sms")
                return
            try:
                await self._call(
                    client,
                    "GET",
                    "/otp/retry",
                    {"retrytype": "voice", "mobile": mobile},
                    action="voice",
                )
            except OtpDeliveryError:
                # The SMS with the same code went out; the user can still use it.
                log.warning("otp_voice_failed_sms_sent")

    def _client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(
            timeout=self.timeout,
            transport=self.transport,
            headers={"authkey": self.auth_key, "accept": "application/json"},
        )

    async def _call(
        self,
        client: httpx.AsyncClient,
        method: str,
        path: str,
        params: dict[str, str],
        *,
        action: str,
        json: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        attempt = 0
        while True:
            try:
                resp = await client.request(method, self.base_url + path, params=params, json=json)
            except httpx.HTTPError as exc:
                if attempt < self.retries:
                    attempt += 1
                    await asyncio.sleep(self.backoff * attempt)
                    continue
                log.warning("msg91_unreachable", action=action, error=type(exc).__name__)
                raise OtpDeliveryError("msg91 unreachable") from exc
            if resp.status_code >= 500 and attempt < self.retries:
                attempt += 1
                await asyncio.sleep(self.backoff * attempt)
                continue
            try:
                body = resp.json()
            except ValueError:
                body = {}
            if not isinstance(body, dict):
                body = {}
            # MSG91 answers {"type": "success", "request_id": ...} or
            # {"type": "error", "message": ...}, sometimes with HTTP 200.
            if resp.is_success and body.get("type") == "success":
                return body
            log.warning(
                "msg91_rejected",
                action=action,
                status=resp.status_code,
                reason=str(body.get("message") or "")[:120],
            )
            raise OtpDeliveryError(f"msg91 {action} failed ({resp.status_code})")


_provider: OtpProvider | None = None


def get_otp_provider() -> OtpProvider:
    global _provider
    if _provider is None:
        s = get_settings()
        if s.OTP_PROVIDER == "dev":
            _provider = DevOtpProvider()
        elif s.OTP_PROVIDER == "msg91" and s.MSG91_AUTH_KEY and s.MSG91_OTP_TEMPLATE_ID:
            _provider = Msg91OtpProvider(
                s.MSG91_AUTH_KEY,
                s.MSG91_OTP_TEMPLATE_ID,
                sender_id=s.MSG91_SENDER_ID,
                voice_fallback=s.OTP_VOICE_FALLBACK,
                expiry_seconds=s.OTP_TTL_SECONDS,
                base_url=s.MSG91_BASE_URL,
            )
        else:
            _provider = NotConfiguredProvider(s.OTP_PROVIDER)
    return _provider


def set_otp_provider(provider: OtpProvider | None) -> None:
    global _provider
    _provider = provider
