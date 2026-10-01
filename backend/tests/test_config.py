"""Settings refuse unsafe production configuration (review C3, primary #3/#6/#9)."""

from __future__ import annotations

import warnings
from typing import Any

import pytest
from pydantic import ValidationError

from app.core.config import InsecureConfigWarning, Settings

GOOD: dict[str, Any] = {
    "ENV": "prod",
    "DATABASE_URL": "postgresql+asyncpg://banega:Zx9-long-random-pw@db:5432/banega",
    "REDIS_URL": "redis://:pw@redis:6379/0",
    "JWT_SECRET": "k" * 48,
    "OTP_PROVIDER": "msg91",
    "STORE_VERIFIER": "store",
    "PLAY_WEBHOOK_SECRET": "play-secret",
    "PUSH_PROVIDER": "fcm",
    "APPSTORE_BUNDLE_ID": "app.banega",
    "APPSTORE_ISSUER_ID": "issuer",
    "APPSTORE_KEY_ID": "KEY123",
    "APPSTORE_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----x",
}


def make(**overrides: Any) -> Settings:
    return Settings(_env_file=None, **{**GOOD, **overrides})  # type: ignore[call-arg]


def refused(match: str, **overrides: Any) -> None:
    with pytest.raises(ValidationError, match=match):
        make(**overrides)


def test_good_production_config_boots() -> None:
    s = make()
    assert s.ENV == "prod" and not s.is_dev


@pytest.mark.parametrize("env", ["staging", "prod"])
def test_every_guard_applies_outside_dev(env: str) -> None:
    refused("STORE_VERIFIER=fake", ENV=env, STORE_VERIFIER="fake")


def test_fake_store_refused() -> None:
    refused("STORE_VERIFIER=fake", STORE_VERIFIER="fake")


def test_fakes_and_unverified_jws_only_in_dev(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.core.config import get_settings
    from app.services import subscription
    from app.services.store_jws import AppleJwsDecoder

    assert subscription.use_fakes()
    assert not subscription.get_jws_decoder().verified
    monkeypatch.setattr(get_settings(), "ENV", "prod")
    monkeypatch.setattr(get_settings(), "STORE_VERIFIER", "fake")
    assert not subscription.use_fakes()
    assert isinstance(subscription.get_jws_decoder(), AppleJwsDecoder)
    with pytest.raises(RuntimeError):
        subscription.UnverifiedJwsDecoder()


def test_memory_redis_refused() -> None:
    refused("REDIS_URL", REDIS_URL="memory://")
    refused("REDIS_URL", REDIS_URL="")


def test_play_webhook_auth_required() -> None:
    refused("PLAY_WEBHOOK_SECRET", PLAY_WEBHOOK_SECRET="")
    # Pub/Sub OIDC instead of a shared secret is fine.
    make(
        PLAY_WEBHOOK_SECRET="",
        PLAY_PUBSUB_AUDIENCE="https://api.banega.app/v1/webhooks/play",
        PLAY_PUBSUB_SERVICE_ACCOUNT="rtdn@banega.iam.gserviceaccount.com",
    )


def test_noop_push_refused_unless_allowed() -> None:
    refused("PUSH_PROVIDER=noop", PUSH_PROVIDER="noop")
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        make(PUSH_PROVIDER="noop", ALLOW_NOOP_PUSH=True)
    assert any(issubclass(w.category, InsecureConfigWarning) for w in caught)


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+asyncpg://banega:banega-dev-password@db:5432/banega",
        "postgresql+asyncpg://banega:banega@localhost:5432/banega",
    ],
)
def test_default_db_password_refused(url: str) -> None:
    refused("default dev database password", DATABASE_URL=url)


@pytest.mark.parametrize(
    "missing",
    ["APPSTORE_BUNDLE_ID", "APPSTORE_ISSUER_ID", "APPSTORE_KEY_ID", "APPSTORE_PRIVATE_KEY"],
)
def test_appstore_config_required(missing: str) -> None:
    refused(missing, **{missing: ""})


def test_root_cert_must_exist() -> None:
    refused("APPSTORE_ROOT_CERT_PATH", APPSTORE_ROOT_CERT_PATH="/nope/root.cer")


def test_dev_secrets_refused() -> None:
    refused("JWT_SECRET", JWT_SECRET="dev-insecure-change-me-but-long-enough-000")
    refused("OTP_PROVIDER=dev", OTP_PROVIDER="dev")


def test_all_problems_reported_at_once() -> None:
    with pytest.raises(ValidationError) as exc:
        make(STORE_VERIFIER="fake", REDIS_URL="memory://", PLAY_WEBHOOK_SECRET="")
    text = str(exc.value)
    assert "STORE_VERIFIER" in text and "REDIS_URL" in text and "PLAY_WEBHOOK_SECRET" in text


def test_dev_and_test_stay_permissive() -> None:
    for env in ("dev", "test"):
        s = Settings(  # type: ignore[call-arg]
            _env_file=None, ENV=env, STORE_VERIFIER="fake", REDIS_URL="memory://"
        )
        assert s.is_dev


def test_hmac_keys_are_split_but_derived_by_default() -> None:
    s = make()
    assert s.hmac_key("otp") != s.hmac_key("invite")
    assert s.hmac_key("otp") != s.JWT_SECRET.encode()
    assert make(OTP_HMAC_KEY="explicit-otp-key").hmac_key("otp") == b"explicit-otp-key"
