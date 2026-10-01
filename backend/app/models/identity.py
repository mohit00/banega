"""Users, OTP requests, auth sessions, devices and notification preferences."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, UniqueConstraint, true
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONType, SoftDelete, Timestamped, UTCDateTime, UUIDPk, str_enum
from app.models.enums import Platform


class User(UUIDPk, Timestamped, SoftDelete, Base):
    __tablename__ = "users"

    # NULL once the account is purged (FR-A8 / DPDP): the number is freed for a new sign-up and
    # phone_deleted_at records when it was erased. Unique allows many NULLs.
    phone: Mapped[str | None] = mapped_column(String(20), unique=True, nullable=True)
    phone_deleted_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    name: Mapped[str | None] = mapped_column(String(80))
    # hinglish | en | hi
    locale: Mapped[str] = mapped_column(String(16), default="hinglish", server_default="hinglish")

    def __str__(self) -> str:
        return f"{self.name or 'User'} ({self.phone or 'deleted'})"


class OtpRequest(UUIDPk, Timestamped, Base):
    __tablename__ = "otp_requests"
    __table_args__ = (Index("ix_otp_requests_phone_created", "phone", "created_at"),)

    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    device_id: Mapped[str | None] = mapped_column(String(128))
    consumed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())


class AuthSession(UUIDPk, Timestamped, Base):
    """One login on one device. Holds the hash of the single currently-valid refresh token."""

    __tablename__ = "auth_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    device_id: Mapped[str | None] = mapped_column(String(128))
    refresh_jti_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(UTCDateTime())


class Device(UUIDPk, Timestamped, Base):
    __tablename__ = "devices"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    platform: Mapped[Platform] = mapped_column(str_enum(Platform, "platform"), nullable=False)
    push_token: Mapped[str] = mapped_column(String(512), unique=True, nullable=False)
    app_version: Mapped[str | None] = mapped_column(String(32))


class NotificationPref(UUIDPk, Timestamped, Base):
    __tablename__ = "notification_prefs"
    __table_args__ = (UniqueConstraint("user_id", "event"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    event: Mapped[str] = mapped_column(String(64), nullable=False)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    # {"start": "22:00", "end": "07:00"} in the household timezone
    quiet_hours: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
