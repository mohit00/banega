"""Optional crash reporting (Sentry).

Nothing happens unless ``SENTRY_DSN`` is set (and ``sentry-sdk`` is installed). Every event
and breadcrumb goes through :func:`scrub_event` first: request bodies, cookies and auth /
device headers are dropped; phone numbers, JWTs, bearer tokens and OTP-like secrets are
masked anywhere they appear (messages, exception values, local variables, extras)."""

from __future__ import annotations

import re
from typing import Any

import structlog

from app.core.config import get_settings

log = structlog.get_logger(__name__)

FILTERED = "[Filtered]"

# E.164 numbers and bare Indian mobiles ("+91 98765 43210", "09876543210", "9876543210").
_PHONE_RE = re.compile(
    r"(?<![\w-])(?:(?:\+|%2B)\d{1,3}[\s-]?)?(?:0)?[6-9]\d{4}[\s-]?\d{5}(?![\w-])"
    r"|(?:\+|%2B)\d{10,15}(?!\d)",
    re.IGNORECASE,
)
_JWT_RE = re.compile(r"eyJ[\w-]{5,}\.[\w-]{5,}\.[\w-]{5,}")
_BEARER_RE = re.compile(r"(?i)\bbearer\s+[\w.~+/=-]+")
# Secrets in URL query strings (outbound httpx breadcrumbs: MSG91 ?otp=, ?authkey=).
_QUERY_SECRET_RE = re.compile(
    r"(?i)([?&](?:otp|authkey|code|token|access_token|key|mobile)=)[^&#\s]+"
)
# Keys whose values are secrets or personal data whatever they contain.
_SENSITIVE_KEYS = re.compile(
    r"(?i)(phone|token|password|passwd|secret|otp|authorization|cookie|api[_-]?key|dsn|"
    r"push|device[_-]?id|idempotency)|^(code|invite_code|dev_code)$"
)
_DROP_HEADERS = {
    "authorization",
    "cookie",
    "set-cookie",
    "x-device-id",
    "idempotency-key",
    "x-forwarded-for",
    "x-real-ip",
}


def scrub_text(value: str) -> str:
    value = _JWT_RE.sub(FILTERED, value)
    value = _BEARER_RE.sub(f"Bearer {FILTERED}", value)
    value = _QUERY_SECRET_RE.sub(rf"\g<1>{FILTERED}", value)
    return _PHONE_RE.sub(FILTERED, value)


def _scrub(value: Any, depth: int = 0) -> Any:
    if depth > 12:
        return FILTERED
    if isinstance(value, str):
        return scrub_text(value)
    if isinstance(value, dict):
        out: dict[Any, Any] = {}
        for k, v in value.items():
            if isinstance(k, str) and _SENSITIVE_KEYS.search(k) and v not in (None, "", [], {}):
                out[k] = FILTERED
            else:
                out[k] = _scrub(v, depth + 1)
        return out
    if isinstance(value, list | tuple):
        return [_scrub(v, depth + 1) for v in value]
    return value


def _scrub_request(request: dict[str, Any]) -> dict[str, Any]:
    request = dict(request)
    # Bodies carry phone numbers, OTP codes, member health notes: never sent.
    request.pop("data", None)
    request.pop("cookies", None)
    request.pop("env", None)
    headers = request.get("headers")
    if isinstance(headers, dict):
        request["headers"] = {
            k: scrub_text(str(v)) for k, v in headers.items() if k.lower() not in _DROP_HEADERS
        }
    elif isinstance(headers, list):
        request["headers"] = [
            [k, scrub_text(str(v))]
            for k, v in headers
            if isinstance(k, str) and k.lower() not in _DROP_HEADERS
        ]
    if isinstance(request.get("query_string"), str):
        request["query_string"] = scrub_text(request["query_string"])
    if isinstance(request.get("url"), str):
        request["url"] = scrub_text(request["url"])
    return request


def scrub_event(event: dict[str, Any], hint: dict[str, Any] | None = None) -> dict[str, Any]:
    """``before_send`` / ``before_send_transaction``: never raises, never drops the event."""
    event = dict(event)
    request = event.get("request")
    if isinstance(request, dict):
        event["request"] = _scrub_request(request)
    user = event.get("user")
    if isinstance(user, dict):
        # Only the opaque id: no phone, name, email or IP address.
        event["user"] = {"id": user["id"]} if user.get("id") else {}
    for key in ("message", "logentry", "exception", "breadcrumbs", "extra", "contexts", "tags"):
        if key in event:
            event[key] = _scrub(event[key])
    return event


def scrub_breadcrumb(crumb: dict[str, Any], hint: dict[str, Any] | None = None) -> dict[str, Any]:
    return dict(_scrub(crumb))


def init_sentry(component: str) -> bool:
    """Initialise Sentry for ``component`` ("api" | "worker") when SENTRY_DSN is set."""
    s = get_settings()
    if not s.SENTRY_DSN:
        return False
    try:
        import sentry_sdk
        from sentry_sdk.integrations.arq import ArqIntegration
        from sentry_sdk.integrations.fastapi import FastApiIntegration
        from sentry_sdk.integrations.starlette import StarletteIntegration
    except ImportError:  # pragma: no cover - sentry-sdk is a regular dependency
        log.warning("sentry_sdk_missing")
        return False
    sentry_sdk.init(
        dsn=s.SENTRY_DSN,
        environment=s.ENV,
        release=s.SENTRY_RELEASE or None,
        server_name=component,
        send_default_pii=False,
        max_request_body_size="never",
        include_local_variables=False,
        traces_sample_rate=s.SENTRY_TRACES_SAMPLE_RATE,
        integrations=[StarletteIntegration(), FastApiIntegration(), ArqIntegration()],
        before_send=scrub_event,  # type: ignore[arg-type]
        before_send_transaction=scrub_event,  # type: ignore[arg-type]
        before_breadcrumb=scrub_breadcrumb,
    )
    sentry_sdk.set_tag("component", component)
    log.info("sentry_enabled", component=component)
    return True
