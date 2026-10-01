"""JWT access/refresh tokens and hashing helpers.

Access tokens live 15 minutes. Refresh tokens live 90 days and are rotated on every use:
each AuthSession row stores the hash of the one refresh token that is currently valid, so a
replayed (already rotated) refresh token is detected and revokes the whole session.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

import jwt

from app.core.config import get_settings
from app.core.errors import Unauthorized

TokenType = Literal["access", "refresh"]


def utcnow() -> datetime:
    return datetime.now(UTC)


HashPurpose = Literal["otp", "invite", "refresh"]


def _legacy_key() -> bytes:
    return get_settings().JWT_SECRET.encode()


def _key(purpose: HashPurpose) -> bytes:
    # Refresh-token ids keep the JWT key: rotating it logs everybody out anyway.
    return _legacy_key() if purpose == "refresh" else get_settings().hmac_key(purpose)


def hmac_hash(value: str, purpose: HashPurpose = "refresh") -> str:
    """Keyed hash for OTP codes, invite tokens and refresh token ids (never stored in clear).

    OTP codes and invite tokens use their own keys (``OTP_HMAC_KEY`` / ``INVITE_HMAC_KEY``,
    derived from JWT_SECRET when unset)."""
    return hmac.new(_key(purpose), value.encode(), hashlib.sha256).hexdigest()


def hmac_hash_candidates(value: str, purpose: HashPurpose) -> list[str]:
    """Current hash first, then the pre-split JWT_SECRET hash (rows written before the key
    split keep verifying until they expire: OTPs in minutes, invites in 7 days)."""
    current = hmac_hash(value, purpose)
    legacy = hmac.new(_legacy_key(), value.encode(), hashlib.sha256).hexdigest()
    return [current] if legacy == current else [current, legacy]


def constant_time_equals(a: str, b: str) -> bool:
    return hmac.compare_digest(a, b)


def new_otp_code(length: int = 6) -> str:
    return "".join(secrets.choice("0123456789") for _ in range(length))


def new_url_token(nbytes: int = 24) -> str:
    return secrets.token_urlsafe(nbytes)


@dataclass(frozen=True)
class TokenClaims:
    user_id: uuid.UUID
    session_id: uuid.UUID
    token_type: TokenType
    jti: str
    expires_at: datetime


def _encode(claims: dict[str, Any]) -> str:
    s = get_settings()
    return jwt.encode(claims, s.JWT_SECRET, algorithm=s.JWT_ALGORITHM)


def create_token(
    user_id: uuid.UUID, session_id: uuid.UUID, token_type: TokenType, *, now: datetime | None = None
) -> tuple[str, TokenClaims]:
    s = get_settings()
    now = now or utcnow()
    ttl = (
        timedelta(minutes=s.ACCESS_TOKEN_MINUTES)
        if token_type == "access"
        else timedelta(days=s.REFRESH_TOKEN_DAYS)
    )
    exp = now + ttl
    jti = secrets.token_hex(16)
    token = _encode(
        {
            "sub": str(user_id),
            "sid": str(session_id),
            "typ": token_type,
            "jti": jti,
            "iat": int(now.timestamp()),
            "exp": int(exp.timestamp()),
        }
    )
    return token, TokenClaims(user_id, session_id, token_type, jti, exp)


def decode_token(token: str, expected_type: TokenType) -> TokenClaims:
    s = get_settings()
    try:
        data = jwt.decode(
            token,
            s.JWT_SECRET,
            algorithms=[s.JWT_ALGORITHM],
            options={"require": ["sub", "sid", "typ", "exp", "jti"]},
        )
    except jwt.ExpiredSignatureError as exc:
        raise Unauthorized("token_expired", "Session expired.", "Session khatam ho gaya.") from exc
    except jwt.PyJWTError as exc:
        raise Unauthorized("invalid_token") from exc
    if data.get("typ") != expected_type:
        raise Unauthorized("invalid_token")
    try:
        return TokenClaims(
            user_id=uuid.UUID(data["sub"]),
            session_id=uuid.UUID(data["sid"]),
            token_type=expected_type,
            jti=str(data["jti"]),
            expires_at=datetime.fromtimestamp(int(data["exp"]), UTC),
        )
    except (ValueError, KeyError) as exc:
        raise Unauthorized("invalid_token") from exc
