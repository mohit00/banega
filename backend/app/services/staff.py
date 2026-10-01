"""Staff accounts for the admin panel: argon2id passwords, TOTP, lockout, audit log, and the
soft deletes the admin uses instead of SQL DELETE (review B2/B3, H4).

The admin app (admin/main.py) is a thin Starlette-Admin layer over these functions, so they
are unit-tested here without the admin UI.
"""

from __future__ import annotations

import decimal
import enum
import uuid
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Any

import pyotp
import structlog
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from sqlalchemy import func, inspect, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.kv import get_kv
from app.core.security import utcnow
from app.models import (
    AuditLog,
    AuthSession,
    Cook,
    Household,
    Ingredient,
    Member,
    StaffUser,
    User,
)
from app.permissions import Actor

log = structlog.get_logger(__name__)

ISSUER = "Banega Admin"
MAX_FAILURES = 5
LOCK_SECONDS = 15 * 60
MIN_PASSWORD = 12
# Never copied into the audit log.
SECRET_FIELDS = frozenset(
    {
        "password_hash",
        "totp_secret",
        "token_hash",
        "code_hash",
        "refresh_jti_hash",
        "embedding",
        "purchase_token",
    }
)
SYSTEM_ACTOR_ID = uuid.UUID(int=0)

_hasher = PasswordHasher()


class StaffError(Exception):
    """Login refused; ``message`` is safe to show."""

    def __init__(self, message: str, *, locked_for: int | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.locked_for = locked_for


# ---- passwords + TOTP ----------------------------------------------------------------------


def hash_password(password: str) -> str:
    if len(password) < MIN_PASSWORD:
        raise ValueError(f"password must be at least {MIN_PASSWORD} characters")
    return _hasher.hash(password)


def verify_password(stored: str, password: str) -> bool:
    try:
        return _hasher.verify(stored, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def totp_uri(staff: StaffUser) -> str:
    return pyotp.TOTP(staff.totp_secret).provisioning_uri(name=staff.email, issuer_name=ISSUER)


async def verify_totp(staff: StaffUser, code: str, now: datetime | None = None) -> bool:
    """Current or adjacent 30 s step; each step is accepted once (replay guard in kv)."""
    code = "".join(ch for ch in code if ch.isdigit())
    if len(code) != 6:
        return False
    totp = pyotp.TOTP(staff.totp_secret)
    at = now or utcnow()
    for offset in (0, -1, 1):
        step_at = at + timedelta(seconds=offset * totp.interval)
        if totp.verify(code, for_time=step_at, valid_window=0):
            step = int(step_at.timestamp() // totp.interval)
            fresh = await get_kv().set(f"admin:totp:{staff.id}:{step}", "1", 120, nx=True)
            return fresh
    return False


def normalize_email(email: str) -> str:
    return email.strip().lower()


async def create_staff(db: AsyncSession, email: str, password: str) -> StaffUser:
    email = normalize_email(email)
    if "@" not in email:
        raise ValueError("email must look like an email address")
    exists = (await db.execute(select(StaffUser.id).where(StaffUser.email == email))).first()
    if exists is not None:
        raise ValueError(f"staff {email} already exists")
    staff = StaffUser(
        email=email, password_hash=hash_password(password), totp_secret=pyotp.random_base32()
    )
    db.add(staff)
    await db.flush()
    return staff


async def staff_count(db: AsyncSession) -> int:
    return int((await db.execute(select(func.count()).select_from(StaffUser))).scalar_one())


# ---- login + lockout -----------------------------------------------------------------------


def _lock_key(email: str) -> str:
    return f"admin:lock:{email}"


def _fail_key(email: str) -> str:
    return f"admin:fail:{email}"


async def locked_for(email: str) -> int:
    kv = get_kv()
    if await kv.get(_lock_key(email)) is None:
        return 0
    return max(1, await kv.ttl(_lock_key(email)))


async def record_failure(email: str) -> None:
    kv = get_kv()
    n = await kv.incr(_fail_key(email), LOCK_SECONDS)
    if n >= MAX_FAILURES:
        await kv.set(_lock_key(email), "1", LOCK_SECONDS)
        await kv.delete(_fail_key(email))
        log.warning("admin_login_locked", email=email)


@dataclass(frozen=True, slots=True)
class LoginResult:
    staff: StaffUser
    # True: password ok but TOTP not enrolled yet -> enrolment page.
    needs_enrolment: bool


async def authenticate(
    db: AsyncSession, email: str, password: str, code: str, now: datetime | None = None
) -> LoginResult:
    """Email + password + TOTP. Five failures (any step) lock the email for 15 minutes."""
    email = normalize_email(email)
    wait = await locked_for(email)
    if wait:
        raise StaffError(
            f"Too many failed attempts. Try again in {max(1, wait // 60)} minute(s).",
            locked_for=wait,
        )
    staff = (
        await db.execute(select(StaffUser).where(StaffUser.email == email))
    ).scalar_one_or_none()
    if staff is None or not staff.is_active or not verify_password(staff.password_hash, password):
        await record_failure(email)
        raise StaffError("Invalid email, password or code.")
    if staff.totp_enrolled_at is None:
        if code and await verify_totp(staff, code, now):
            staff.totp_enrolled_at = now or utcnow()
        else:
            return LoginResult(staff, needs_enrolment=True)
    elif not await verify_totp(staff, code, now):
        await record_failure(email)
        raise StaffError("Invalid email, password or code.")
    await get_kv().delete(_fail_key(email))
    staff.last_login = now or utcnow()
    return LoginResult(staff, needs_enrolment=False)


async def enrol(
    db: AsyncSession, staff_id: uuid.UUID, code: str, now: datetime | None = None
) -> StaffUser:
    staff = await db.get(StaffUser, staff_id)
    if staff is None or not staff.is_active:
        raise StaffError("Unknown staff account.")
    if await locked_for(staff.email):
        raise StaffError("Too many failed attempts. Try again later.")
    if not await verify_totp(staff, code, now):
        await record_failure(staff.email)
        raise StaffError("That code is not right. Check the time on your phone.")
    staff.totp_enrolled_at = staff.totp_enrolled_at or now or utcnow()
    staff.last_login = now or utcnow()
    return staff


def reveal_enrolment_uri(staff: StaffUser, now: datetime | None = None) -> str | None:
    """The otpauth URI, only the first time (None afterwards: ask another staff to reset)."""
    if staff.totp_enrolled_at is not None or staff.totp_shown_at is not None:
        return None
    staff.totp_shown_at = now or utcnow()
    return totp_uri(staff)


def reset_totp(staff: StaffUser) -> None:
    staff.totp_secret = pyotp.random_base32()
    staff.totp_enrolled_at = None
    staff.totp_shown_at = None


# ---- audit ------------------------------------------------------------------------------------


def _jsonable(value: Any) -> Any:
    if value is None or isinstance(value, bool | int | float | str):
        return value
    if isinstance(value, uuid.UUID | decimal.Decimal):
        return str(value)
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, enum.Enum):
        return value.value
    if isinstance(value, dict):
        return {str(k): _jsonable(v) for k, v in value.items()}
    if isinstance(value, list | tuple | set):
        return [_jsonable(v) for v in value]
    return str(value)


def snapshot(obj: Any) -> dict[str, Any]:
    """Column values of a mapped object (no relationships, no secrets)."""
    try:
        mapper = inspect(obj).mapper
    except Exception:
        return {}
    out: dict[str, Any] = {}
    state = inspect(obj)
    for attr in mapper.column_attrs:
        key = attr.key
        if key in SECRET_FIELDS or key in state.unloaded:
            continue
        out[key] = _jsonable(getattr(obj, key, None))
    return out


def clean(data: dict[str, Any]) -> dict[str, Any]:
    return {k: _jsonable(v) for k, v in data.items() if k not in SECRET_FIELDS}


def audit(
    db: AsyncSession,
    *,
    staff_id: uuid.UUID | None,
    staff_email: str | None,
    action: str,
    model: str,
    pk: Any = None,
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
) -> AuditLog:
    row = AuditLog(
        staff_id=staff_id,
        staff_email=staff_email,
        action=action[:64],
        model=model[:64],
        pk=None if pk is None else str(pk)[:64],
        before=before,
        after=after,
        at=utcnow(),
    )
    db.add(row)
    return row


# ---- soft deletes (the admin never hard-deletes these) --------------------------------------

SOFT_DELETE_MODELS = (User, Household, Member, Cook, Ingredient)


async def soft_delete(db: AsyncSession, obj: Any, now: datetime | None = None) -> None:
    """Route an admin delete through the same soft delete the API uses."""
    now = now or utcnow()
    if isinstance(obj, User):
        if obj.deleted_at is None:
            obj.deleted_at = now
        await db.execute(
            update(AuthSession)
            .where(AuthSession.user_id == obj.id, AuthSession.revoked_at.is_(None))
            .values(revoked_at=now)
        )
    elif isinstance(obj, Household):
        if obj.deleted_at is None:
            obj.deleted_at = now
    elif isinstance(obj, Member):
        if obj.archived_at is None:
            obj.archived_at = now
    elif isinstance(obj, Cook):
        if obj.removed_at is None:
            from app.services import cooks as cook_svc

            household = await db.get(Household, obj.household_id)
            if household is None:
                obj.removed_at = now
            else:
                actor = Actor(user_id=SYSTEM_ACTOR_ID, household_id=household.id, is_admin=True)
                await cook_svc.remove_cook(db, household, obj, actor, now)
    elif isinstance(obj, Ingredient):
        # recipe_ingredients.ingredient_id is ON DELETE RESTRICT: deactivate instead.
        obj.is_active = False
    else:
        raise TypeError(f"{type(obj).__name__} has no soft delete")
    await db.flush()
