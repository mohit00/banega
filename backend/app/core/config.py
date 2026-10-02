"""Application settings, loaded from environment variables (and an optional .env file)."""

from __future__ import annotations

import hashlib
import hmac
import warnings
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Passwords that ship in infra/.env.example, docker-compose.yml and the Settings default.
DEV_DB_PASSWORDS = ("banega-dev-password", "banega")
APPLE_ROOT_CERT = Path(__file__).resolve().parents[1] / "certs" / "AppleRootCA-G3.cer"


class InsecureConfigWarning(UserWarning):
    """A production setting that is allowed but not launch-ready (e.g. ALLOW_NOOP_PUSH)."""


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    ENV: Literal["dev", "test", "staging", "prod"] = "dev"
    DATABASE_URL: str = "postgresql+asyncpg://banega:banega@localhost:5432/banega"
    # Empty or "memory://" selects the in-process store (tests, single-process dev).
    REDIS_URL: str = "redis://localhost:6379/0"
    JWT_SECRET: str = Field(default="dev-insecure-change-me", min_length=16)
    JWT_ALGORITHM: str = "HS256"
    # Separate keys for the keyed hashes of OTP codes and invite tokens. Empty = derived from
    # JWT_SECRET (HMAC(JWT_SECRET, purpose)); setting one rotates it independently of the
    # JWT key (outstanding OTP codes / invite links made with the old key stop matching).
    OTP_HMAC_KEY: str = ""
    INVITE_HMAC_KEY: str = ""
    ACCESS_TOKEN_MINUTES: int = 15
    REFRESH_TOKEN_DAYS: int = 90

    OTP_PROVIDER: Literal["dev", "msg91", "twilio"] = "dev"
    OTP_TTL_SECONDS: int = 300
    OTP_RESEND_SECONDS: int = 30
    OTP_MAX_PER_NUMBER_PER_HOUR: int = 5
    OTP_MAX_PER_DEVICE_PER_DAY: int = 10
    OTP_MAX_WRONG_ATTEMPTS: int = 3
    OTP_LOCK_SECONDS: int = 600
    # Wrong-code locks are scoped to phone + device/IP and double per repeat, up to this cap.
    OTP_LOCK_MAX_SECONDS: int = 6 * 3600
    # Per client IP and global (all numbers) OTP send limits: SMS pumping guard.
    OTP_MAX_PER_IP_PER_HOUR: int = 20
    OTP_MAX_GLOBAL_PER_MINUTE: int = 300
    # Proxies whose X-Forwarded-For is trusted (nginx in compose). Comma-separated IPs or
    # CIDRs; the client IP is the right-most address that is not a trusted proxy.
    TRUSTED_PROXIES: str = "127.0.0.1/32,::1/128,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

    INVITE_TTL_DAYS: int = 7
    INVITE_LINK_BASE: str = "https://banega.app/invite/"
    # F-3-03: server-side trial, 7 days from household creation, one per phone + device.
    TRIAL_DAYS: int = 7
    UNDO_WINDOW_DAYS: int = 7
    IDEMPOTENCY_TTL_SECONDS: int = 24 * 3600
    # While the first request runs its "pending" marker lives this long and is renewed, so a
    # crashed worker does not block the key for a day.
    IDEMPOTENCY_LEASE_SECONDS: int = 30
    # Parallel refreshes (app resume) within this window get the same new token pair.
    REFRESH_GRACE_SECONDS: int = 60

    LOG_LEVEL: str = "INFO"
    LOG_JSON: bool = True
    # Crash reporting (optional): empty DSN = Sentry is never initialised. Events are
    # scrubbed of phone numbers, tokens, auth headers and request bodies (app/core/sentry.py).
    SENTRY_DSN: str = ""
    SENTRY_TRACES_SAMPLE_RATE: float = 0.0
    SENTRY_RELEASE: str = ""

    # ---- Maharaj chat (Phase 4) ----------------------------------------------------------
    # Empty key = no LLM: the rule parser and the template writer answer every message.
    ANTHROPIC_API_KEY: str = ""
    MAHARAJ_PARSE_MODEL: str = "claude-sonnet-5"
    MAHARAJ_WRITE_MODEL: str = "claude-sonnet-5"
    MAHARAJ_LLM_PARSE: bool = True
    MAHARAJ_LLM_WRITE: bool = True
    # LLM calls (parse + write) per household per local day; beyond it, rules + templates.
    MAHARAJ_DAILY_BUDGET: int = 200
    MAHARAJ_PARSE_TIMEOUT: float = 2.5
    MAHARAJ_WRITE_TIMEOUT: float = 3.0
    MAHARAJ_PARSE_CACHE_SECONDS: int = 24 * 3600
    # Messages per user per window.
    MAHARAJ_RATE_LIMIT: int = 30
    MAHARAJ_RATE_WINDOW_SECONDS: int = 600
    # Relax soft filters (F-7-01 order) while fewer results than this.
    MAHARAJ_MIN_RESULTS: int = 3
    # Published-catalogue snapshot (recommendations, Maharaj): stamp re-checked at most this
    # often; 0 = on every call (tests).
    CATALOGUE_CACHE_SECONDS: int = 60
    MAHARAJ_MAX_CARDS: int = 4
    # auto = ARQ when REDIS_URL is a real Redis, else an in-process background task.
    MAHARAJ_WRITE_MODE: Literal["auto", "arq", "background"] = "auto"
    CHAT_IDLE_MINUTES: int = 30
    CHAT_RETENTION_DAYS: int = 30
    # Optional embeddings for pgvector retrieval; empty = keyword + filter retrieval only.
    VOYAGE_API_KEY: str = ""
    EMBEDDING_MODEL: str = ""

    # ---- menus, tickets, notifications (Phase 5) ------------------------------------------
    # noop = log only (dev/tests); fcm = FCM HTTP v1 (Android + iOS via APNs).
    PUSH_PROVIDER: Literal["noop", "fcm"] = "noop"
    FCM_PROJECT_ID: str = ""
    # Outside dev/test PUSH_PROVIDER=noop refuses to boot unless this is set (staging).
    ALLOW_NOOP_PUSH: bool = False
    # F-5.7-02 / F-5.7-12 timers.
    TICKET_NOT_CONFIRMED_AFTER_MINUTES: int = 180
    TICKET_NOT_CONFIRMED_CLOSE_HOURS: int = 24
    TICKET_NO_SHOW_BEFORE_MINUTES: int = 90
    # Accepted but not Cooking this long before due -> at-risk alert. Per slot:
    # Household.slot_defaults[slot].no_show_minutes / .at_risk_minutes.
    TICKET_AT_RISK_BEFORE_MINUTES: int = 45
    # Alert sweeps only look this far back (an outage must not alert on history).
    TICKET_ALERT_LOOKBACK_HOURS: int = 6
    # new / unassigned tickets nobody picked up are cancelled this long after due.
    TICKET_STUCK_CANCEL_HOURS: int = 24
    WORKER_BATCH_SIZE: int = 200
    WORKER_JOB_TIMEOUT_SECONDS: int = 240
    TOMORROW_NOTIFY_LOCAL_TIME: str = "20:00"

    # ---- billing, consent, export (Phase 7) ----------------------------------------------
    # auto = fake store verification + unverified App Store JWS in dev/test, real adapters
    # elsewhere; fake is refused outside dev/test.
    STORE_VERIFIER: Literal["auto", "fake", "store"] = "auto"
    # Play RTDN push: a shared secret in the X-Webhook-Secret header (added by a proxy),
    # and/or the Pub/Sub push OIDC token (Authorization: Bearer, Google-signed; audience and
    # service account below). Outside dev/test at least one must be configured.
    PLAY_WEBHOOK_SECRET: str = ""
    PLAY_PUBSUB_AUDIENCE: str = ""
    PLAY_PUBSUB_SERVICE_ACCOUNT: str = ""
    # App Store: bundle id + environment checked in every signed notification; the root
    # certificate the x5c chain must end in (Apple Root CA - G3, bundled); App Store Server
    # API credentials (issuer id, key id, .p8 private key) for purchase verification.
    APPSTORE_BUNDLE_ID: str = ""
    APPSTORE_ENVIRONMENT: Literal["Production", "Sandbox"] = "Production"
    APPSTORE_ROOT_CERT_PATH: str = str(APPLE_ROOT_CERT)
    APPSTORE_ISSUER_ID: str = ""
    APPSTORE_KEY_ID: str = ""
    APPSTORE_PRIVATE_KEY: str = ""
    # DPDP notice version the app shows on the first-run consent screen (F-X-02).
    CONSENT_VERSION: str = "2026-09"
    # Uploaded media and data exports (exports under MEDIA_DIR/exports, never served by nginx).
    MEDIA_DIR: str = "media"
    # Data exports (files + job rows) are deleted this many days after they finish.
    EXPORT_TTL_DAYS: int = 7

    @model_validator(mode="after")
    def _check_prod_secrets(self) -> Settings:
        """Fail loud outside dev/test: no fakes, no dev secrets, no unauthenticated webhooks."""
        if self.is_dev:
            return self
        problems: list[str] = []
        if len(self.JWT_SECRET) < 32 or self.JWT_SECRET.startswith("dev-"):
            problems.append("JWT_SECRET must be a random value of at least 32 characters")
        if self.OTP_PROVIDER == "dev":
            problems.append("OTP_PROVIDER=dev is not allowed outside dev/test")
        if self.STORE_VERIFIER == "fake":
            problems.append(
                "STORE_VERIFIER=fake is not allowed outside dev/test (any string would "
                "activate a subscription and App Store notifications would go unverified)"
            )
        if not self.REDIS_URL or self.REDIS_URL.startswith("memory://"):
            problems.append("REDIS_URL must be a real Redis outside dev/test (not memory://)")
        if not self.PLAY_WEBHOOK_SECRET and not (
            self.PLAY_PUBSUB_AUDIENCE and self.PLAY_PUBSUB_SERVICE_ACCOUNT
        ):
            problems.append(
                "PLAY_WEBHOOK_SECRET (or PLAY_PUBSUB_AUDIENCE + PLAY_PUBSUB_SERVICE_ACCOUNT) "
                "must be set outside dev/test"
            )
        if any(f":{pw}@" in self.DATABASE_URL for pw in DEV_DB_PASSWORDS):
            problems.append("DATABASE_URL uses the default dev database password")
        missing = [
            name
            for name in (
                "APPSTORE_BUNDLE_ID",
                "APPSTORE_ISSUER_ID",
                "APPSTORE_KEY_ID",
                "APPSTORE_PRIVATE_KEY",
            )
            if not getattr(self, name)
        ]
        if missing:
            problems.append("store verification is on outside dev/test; set " + ", ".join(missing))
        if not Path(self.APPSTORE_ROOT_CERT_PATH).is_file():
            problems.append(f"APPSTORE_ROOT_CERT_PATH not found: {self.APPSTORE_ROOT_CERT_PATH}")
        if self.PUSH_PROVIDER == "noop":
            if not self.ALLOW_NOOP_PUSH:
                problems.append(
                    "PUSH_PROVIDER=noop delivers no push notifications; set PUSH_PROVIDER=fcm "
                    "or ALLOW_NOOP_PUSH=1 (staging only)"
                )
            else:
                warnings.warn(
                    "PUSH_PROVIDER=noop outside dev/test: no push notification will be "
                    "delivered (ALLOW_NOOP_PUSH=1)",
                    InsecureConfigWarning,
                    stacklevel=2,
                )
        if problems:
            raise ValueError(
                "Refusing to start with an unsafe configuration:\n- " + "\n- ".join(problems)
            )
        return self

    @property
    def is_dev(self) -> bool:
        return self.ENV in ("dev", "test")

    def hmac_key(self, purpose: Literal["otp", "invite"]) -> bytes:
        """Per-purpose HMAC key: the explicit env key, else derived from JWT_SECRET."""
        explicit = self.OTP_HMAC_KEY if purpose == "otp" else self.INVITE_HMAC_KEY
        if explicit:
            return explicit.encode()
        return hmac.new(self.JWT_SECRET.encode(), purpose.encode(), hashlib.sha256).digest()


@lru_cache
def get_settings() -> Settings:
    return Settings()
