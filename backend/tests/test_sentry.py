"""Optional Sentry: off without a DSN; events are scrubbed of phones, tokens and bodies."""

from __future__ import annotations

from typing import Any

import pytest

from app.core import sentry
from app.core.config import get_settings
from app.core.sentry import FILTERED, init_sentry, scrub_breadcrumb, scrub_event, scrub_text

JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"


@pytest.fixture
def settings(monkeypatch: pytest.MonkeyPatch) -> Any:
    s = get_settings()
    monkeypatch.setattr(s, "SENTRY_DSN", "")
    return s


def test_no_dsn_is_a_noop(settings: Any) -> None:
    settings.SENTRY_DSN = ""
    assert init_sentry("api") is False


def test_scrub_text_masks_phones_and_tokens() -> None:
    for phone in ("+919876543210", "+91 98765 43210", "9876543210", "09876543210"):
        assert phone not in scrub_text(f"user {phone} failed"), phone
    assert JWT not in scrub_text(f"token={JWT}")
    assert "abc.def" not in scrub_text("Authorization: Bearer abc.def")
    # UUIDs, prices and timestamps survive.
    keep = "ticket 3f1c9a2e-5b7d-4c11-9e0a-1234567890ab at 2026-10-02T08:00:00Z cost 1234"
    assert scrub_text(keep) == keep


def test_scrub_event_drops_bodies_headers_and_pii() -> None:
    event: dict[str, Any] = {
        "request": {
            "url": "https://api.banega.app/v1/invites/+919876543210",
            "data": {"phone": "+919876543210", "code": "123456"},
            "cookies": {"s": "x"},
            "headers": {
                "Authorization": f"Bearer {JWT}",
                "X-Device-Id": "dev-1",
                "Accept-Language": "en",
            },
            "query_string": "phone=%2B919876543210&phone2=9876543210",
        },
        "user": {"id": "u1", "ip_address": "1.2.3.4", "username": "+919876543210"},
        "exception": {"values": [{"value": "no user with phone +919876543210"}]},
        "extra": {"access_token": JWT, "note": "call 9876543210", "status_code": 500},
        "breadcrumbs": {"values": [{"message": f"refresh {JWT}"}]},
    }
    out = scrub_event(event, {})
    req = out["request"]
    assert "data" not in req and "cookies" not in req
    assert set(req["headers"]) == {"Accept-Language"}
    assert "9876543210" not in req["url"] and "9876543210" not in req["query_string"]
    assert out["user"] == {"id": "u1"}
    assert "9876543210" not in out["exception"]["values"][0]["value"]
    assert out["extra"]["access_token"] == FILTERED
    assert out["extra"]["status_code"] == 500
    assert "9876543210" not in out["extra"]["note"]
    assert JWT not in str(out["breadcrumbs"])
    assert JWT not in str(scrub_breadcrumb({"message": JWT, "data": {"phone": "+919876543210"}}))


def test_init_with_dsn_uses_the_scrubber(settings: Any, monkeypatch: Any) -> None:
    import sentry_sdk

    seen: dict[str, Any] = {}
    monkeypatch.setattr(sentry_sdk, "init", lambda **kw: seen.update(kw))
    monkeypatch.setattr(sentry_sdk, "set_tag", lambda *a: None)
    settings.SENTRY_DSN = "https://public@example.ingest.sentry.io/1"
    try:
        assert init_sentry("worker") is True
    finally:
        settings.SENTRY_DSN = ""
    assert seen["before_send"] is sentry.scrub_event
    assert seen["send_default_pii"] is False
    assert seen["max_request_body_size"] == "never"
