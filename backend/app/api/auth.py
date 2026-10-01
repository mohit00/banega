"""Phone OTP login, token refresh (rotating) and logout (F-5.1-01).

Abuse controls (review H2): per number (hourly), per device (daily), per client IP (hourly,
X-Forwarded-For from trusted proxies only) and global (per minute) send limits, checked
before any counter is consumed; each code allows OTP_MAX_WRONG_ATTEMPTS guesses, then it is
burned; wrong-code locks are scoped to phone + device (or IP) and double on every repeat, so
a stranger cannot lock the owner's number; a code is consumed with a compare-and-set UPDATE
(two concurrent correct verifies cannot both log in).

Refresh (review M3): tokens rotate on every use; the previous refresh token keeps working
for REFRESH_GRACE_SECONDS and returns the same new pair (parallel refreshes on app resume),
after that a replay revokes the session.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from datetime import timedelta
from typing import Annotated

import structlog
from fastapi import APIRouter, Header, Request, status
from sqlalchemy import select, update

from app.api.deps import DB, Auth
from app.core.client_ip import client_ip
from app.core.config import get_settings
from app.core.errors import AppError, TooManyRequests, Unauthorized
from app.core.kv import get_kv
from app.core.security import (
    constant_time_equals,
    create_token,
    decode_token,
    hmac_hash,
    hmac_hash_candidates,
    new_otp_code,
    utcnow,
)
from app.models import AuthSession, OtpRequest, User
from app.schemas import OtpRequestIn, OtpRequestOut, OtpVerifyIn, RefreshIn, TokenPair
from app.services.cooks import link_pending_cook
from app.services.otp import get_otp_provider

router = APIRouter(prefix="/auth", tags=["auth"])
log = structlog.get_logger(__name__)


def _locked_error(retry_after: int) -> TooManyRequests:
    minutes = max(1, (retry_after + 59) // 60)
    return TooManyRequests(
        "otp_locked",
        f"Too many wrong codes. Try again in {minutes} minutes.",
        f"Bahut baar galat code. {minutes} minute baad try kijiye.",
        details={"retry_after": retry_after},
    )


def _scope(phone: str, device_id: str | None, ip: str) -> str:
    """Wrong-code locks apply to this phone from this device (or IP) only."""
    return f"{phone}|{('dev:' + device_id) if device_id else ('ip:' + ip)}"


async def _check_lock(scope: str) -> None:
    kv = get_kv()
    if await kv.get(f"otp:lock:{scope}") is not None:
        raise _locked_error(await kv.ttl(f"otp:lock:{scope}"))


async def _lock(scope: str) -> int:
    """Exponential backoff: OTP_LOCK_SECONDS, then x2 per repeat within a day, capped."""
    s = get_settings()
    kv = get_kv()
    n = await kv.incr(f"otp:lockcount:{scope}", 86400)
    seconds = int(min(s.OTP_LOCK_SECONDS * 2 ** (n - 1), s.OTP_LOCK_MAX_SECONDS))
    await kv.set(f"otp:lock:{scope}", "1", seconds)
    log.warning("otp_locked", lock_seconds=seconds, repeat=n)
    return seconds


@router.post("/otp", response_model=OtpRequestOut, status_code=status.HTTP_200_OK)
async def request_otp(
    body: OtpRequestIn,
    db: DB,
    request: Request,
    x_device_id: Annotated[str | None, Header()] = None,
) -> OtpRequestOut:
    s = get_settings()
    kv = get_kv()
    phone = body.phone
    device_id = body.device_id or x_device_id
    ip = client_ip(request)

    await _check_lock(_scope(phone, device_id, ip))

    if s.OTP_RESEND_SECONDS > 0 and not await kv.set(
        f"otp:cooldown:{phone}", "1", s.OTP_RESEND_SECONDS, nx=True
    ):
        raise TooManyRequests(
            "otp_resend_too_soon",
            "Please wait before asking for a new code.",
            "Naya code maangne se pehle thoda rukiye.",
            details={"retry_after": await kv.ttl(f"otp:cooldown:{phone}")},
        )

    minute = int(utcnow().timestamp() // 60)
    # (key, window, limit, error). All are checked before any is consumed, so a request
    # refused for the device / IP / global limit does not use up the number's hourly slot.
    limits: list[tuple[str, int, int, TooManyRequests]] = [
        (
            f"otp:global:{minute}",
            120,
            s.OTP_MAX_GLOBAL_PER_MINUTE,
            TooManyRequests(
                "otp_busy",
                "We are sending too many codes right now. Try again in a minute.",
                "Abhi bahut code bheje ja rahe hain. Ek minute baad try kijiye.",
                details={"retry_after": 60},
            ),
        ),
        (
            f"otp:ip:{ip}",
            3600,
            s.OTP_MAX_PER_IP_PER_HOUR,
            TooManyRequests(
                "otp_ip_limit",
                "Too many codes requested from this network. Try again later.",
                "Is network se bahut code maange gaye. Thodi der baad try kijiye.",
            ),
        ),
    ]
    if device_id:
        limits.append(
            (
                f"otp:dev:{device_id}",
                86400,
                s.OTP_MAX_PER_DEVICE_PER_DAY,
                TooManyRequests(
                    "otp_device_limit",
                    "Too many codes requested from this phone today.",
                    "Aaj is phone se bahut code maange gaye.",
                ),
            )
        )
    limits.append(
        (
            f"otp:num:{phone}",
            3600,
            s.OTP_MAX_PER_NUMBER_PER_HOUR,
            TooManyRequests(
                "otp_number_limit",
                "Too many codes requested for this number. Try again in an hour.",
                "Is number par bahut code maange gaye. Ek ghante baad try kijiye.",
            ),
        )
    )
    for key, _window, limit, error in limits:
        if int(await kv.get(key) or 0) >= limit:
            log.warning("otp_rate_limited", code=error.code)
            raise error
    for key, window, _limit, _error in limits:
        await kv.incr(key, window)

    code = new_otp_code()
    try:
        await get_otp_provider().send(phone, code, body.channel)
    except Exception as exc:
        log.error("otp_send_failed", error=type(exc).__name__)
        raise AppError(
            "otp_unavailable",
            "We could not send the code. Please try again shortly.",
            "Code nahi bhej paaye. Thodi der baad try kijiye.",
            status_code=503,
        ) from exc
    db.add(
        OtpRequest(
            phone=phone,
            code_hash=hmac_hash(f"{phone}:{code}", "otp"),
            expires_at=utcnow() + timedelta(seconds=s.OTP_TTL_SECONDS),
            device_id=device_id,
        )
    )
    await db.commit()
    return OtpRequestOut(
        expires_in=s.OTP_TTL_SECONDS,
        resend_after=s.OTP_RESEND_SECONDS,
        dev_code=code if s.is_dev and s.OTP_PROVIDER == "dev" else None,
    )


async def _issue_tokens(
    db: DB, user: User, device_id: str | None, *, is_new: bool = False
) -> TokenPair:
    session_id = uuid.uuid4()
    access, a_claims = create_token(user.id, session_id, "access")
    refresh, r_claims = create_token(user.id, session_id, "refresh")
    db.add(
        AuthSession(
            id=session_id,
            user_id=user.id,
            device_id=device_id,
            refresh_jti_hash=hmac_hash(r_claims.jti),
            expires_at=r_claims.expires_at,
        )
    )
    await db.commit()
    return TokenPair(
        access_token=access,
        refresh_token=refresh,
        access_expires_at=a_claims.expires_at,
        refresh_expires_at=r_claims.expires_at,
        user_id=user.id,
        is_new_user=is_new,
        pending_deletion=user.deleted_at is not None,
    )


def _otp_expired() -> AppError:
    return AppError(
        "otp_expired",
        "The code has expired. Ask for a new one.",
        "Code purana ho gaya. Naya code maangiye.",
    )


@router.post("/verify", response_model=TokenPair)
async def verify_otp(
    body: OtpVerifyIn,
    db: DB,
    request: Request,
    x_device_id: Annotated[str | None, Header()] = None,
) -> TokenPair:
    s = get_settings()
    phone = body.phone
    device_id = body.device_id or x_device_id
    scope = _scope(phone, device_id, client_ip(request))
    await _check_lock(scope)

    now = utcnow()
    otp = (
        await db.execute(
            select(OtpRequest)
            .where(
                OtpRequest.phone == phone,
                OtpRequest.consumed_at.is_(None),
                OtpRequest.expires_at > now,
                OtpRequest.attempts < s.OTP_MAX_WRONG_ATTEMPTS,
            )
            .order_by(OtpRequest.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if otp is None:
        raise _otp_expired()

    candidates = hmac_hash_candidates(f"{phone}:{body.code}", "otp")
    if not any(constant_time_equals(otp.code_hash, h) for h in candidates):
        # Count on the code itself (atomic), so guesses spread over devices / IPs still
        # burn it after OTP_MAX_WRONG_ATTEMPTS.
        await db.execute(
            update(OtpRequest)
            .where(OtpRequest.id == otp.id)
            .values(attempts=OtpRequest.attempts + 1)
        )
        await db.commit()
        await db.refresh(otp)
        wrong = await get_kv().incr(f"otp:wrong:{scope}", s.OTP_LOCK_SECONDS)
        left = s.OTP_MAX_WRONG_ATTEMPTS - max(otp.attempts, wrong)
        if left <= 0:
            await get_kv().delete(f"otp:wrong:{scope}")
            raise _locked_error(await _lock(scope))
        raise AppError(
            "otp_invalid",
            "That code is not right.",
            "Code galat hai.",
            details={"attempts_left": left},
        )

    # Compare-and-set: exactly one verify can consume this code.
    consumed = await db.execute(
        update(OtpRequest)
        .where(OtpRequest.id == otp.id, OtpRequest.consumed_at.is_(None))
        .values(consumed_at=now)
    )
    if int(getattr(consumed, "rowcount", 0) or 0) != 1:
        await db.rollback()
        raise _otp_expired()
    await get_kv().delete(f"otp:wrong:{scope}")
    user = (await db.execute(select(User).where(User.phone == phone))).scalar_one_or_none()
    is_new = user is None
    if user is None:
        user = User(phone=phone)
        db.add(user)
        await db.flush()
    # FR-K1: a hired cook the admin added by phone gets cook mode on first login.
    if await link_pending_cook(db, user):
        log.info("cook_login_linked", user_id=str(user.id))
    log.info("otp_verified", user_id=str(user.id), new_user=is_new)
    return await _issue_tokens(db, user, device_id, is_new=is_new)


def _grace_key(session_id: uuid.UUID, jti_hash: str) -> str:
    return f"refresh:grace:{session_id}:{jti_hash}"


async def _grace_pair(session_id: uuid.UUID, jti_hash: str) -> TokenPair | None:
    raw = await get_kv().get(_grace_key(session_id, jti_hash))
    return TokenPair.model_validate(json.loads(raw)) if raw else None


@router.post("/refresh", response_model=TokenPair)
async def refresh_tokens(body: RefreshIn, db: DB) -> TokenPair:
    s = get_settings()
    claims = decode_token(body.refresh_token, "refresh")
    presented = hmac_hash(claims.jti)
    session = await db.get(AuthSession, claims.session_id)
    now = utcnow()
    if session is None or session.revoked_at is not None or session.expires_at <= now:
        raise Unauthorized("session_revoked")
    if not constant_time_equals(session.refresh_jti_hash, presented):
        # Rotated moments ago by a parallel refresh: hand out the same new pair.
        pair = await _grace_pair(session.id, presented)
        if pair is not None:
            return pair
        # A rotated-out refresh token replayed after the grace window: treat as stolen.
        session.revoked_at = now
        await db.commit()
        log.warning("refresh_token_reuse", session_id=str(session.id))
        raise Unauthorized("refresh_reused")
    user = await db.get(User, session.user_id)
    if user is None:
        raise Unauthorized()
    access, a_claims = create_token(user.id, session.id, "access")
    refresh, r_claims = create_token(user.id, session.id, "refresh")
    pair = TokenPair(
        access_token=access,
        refresh_token=refresh,
        access_expires_at=a_claims.expires_at,
        refresh_expires_at=r_claims.expires_at,
        user_id=user.id,
        pending_deletion=user.deleted_at is not None,
    )
    # Compare-and-set on the stored hash: of two refreshes racing here only one rotates.
    rotated = await db.execute(
        update(AuthSession)
        .where(AuthSession.id == session.id, AuthSession.refresh_jti_hash == presented)
        .values(refresh_jti_hash=hmac_hash(r_claims.jti), expires_at=r_claims.expires_at)
    )
    if int(getattr(rotated, "rowcount", 0) or 0) != 1:
        await db.rollback()  # expires ``session``: use claims.session_id from here on
        # The winner stores its pair right after committing; wait for it briefly.
        for _ in range(20):
            pair_won = await _grace_pair(claims.session_id, presented)
            if pair_won is not None:
                return pair_won
            await asyncio.sleep(0.1)
        raise Unauthorized("refresh_reused")
    await db.commit()
    if s.REFRESH_GRACE_SECONDS > 0:
        try:
            await get_kv().set(
                _grace_key(session.id, presented), pair.model_dump_json(), s.REFRESH_GRACE_SECONDS
            )
        except Exception:  # Redis down: no grace window, rotation still works
            log.warning("refresh_grace_store_failed", session_id=str(session.id))
    return pair


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(auth: Auth, db: DB) -> None:
    session = await db.get(AuthSession, auth.session_id)
    if session is not None and session.revoked_at is None:
        session.revoked_at = utcnow()
        await db.commit()


async def revoke_all_sessions(db: DB, user_id: uuid.UUID) -> None:
    await db.execute(
        update(AuthSession)
        .where(AuthSession.user_id == user_id, AuthSession.revoked_at.is_(None))
        .values(revoked_at=utcnow())
    )


@router.post("/logout-all", status_code=status.HTTP_204_NO_CONTENT)
async def logout_all(auth: Auth, db: DB) -> None:
    await revoke_all_sessions(db, auth.user.id)
    await db.commit()
