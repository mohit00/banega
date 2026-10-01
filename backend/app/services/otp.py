"""OTP delivery provider abstraction (SMS with voice fallback)."""

from __future__ import annotations

from typing import Protocol

import structlog

from app.core.config import get_settings

log = structlog.get_logger(__name__)


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
        # TODO(phase-1): MSG91 (DLT template) for SMS + voice fallback after two failures.
        raise NotImplementedError(f"OTP provider {self.name!r} is not wired yet")


_provider: OtpProvider | None = None


def get_otp_provider() -> OtpProvider:
    global _provider
    if _provider is None:
        name = get_settings().OTP_PROVIDER
        _provider = DevOtpProvider() if name == "dev" else NotConfiguredProvider(name)
    return _provider


def set_otp_provider(provider: OtpProvider | None) -> None:
    global _provider
    _provider = provider
