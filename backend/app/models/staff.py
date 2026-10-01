"""Staff (admin panel) accounts and the admin audit log (review B2/B3, H4).

Staff are not app users: they log in to /admin with email + password (argon2id) + TOTP.
Every create / edit / delete / action in the admin writes one :class:`AuditLog` row in the
same transaction as the change.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import Boolean, ForeignKey, Index, String, true
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONType, Timestamped, UTCDateTime, UUIDPk, utcnow


class StaffUser(UUIDPk, Timestamped, Base):
    __tablename__ = "staff_users"

    # Stored lower-case.
    email: Mapped[str] = mapped_column(String(254), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    # Base32 TOTP secret (RFC 6238, 30 s, 6 digits).
    totp_secret: Mapped[str] = mapped_column(String(64), nullable=False)
    # Set when the first valid code is entered; until then the enrolment page shows the
    # otpauth URI (once: totp_shown_at).
    totp_enrolled_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    totp_shown_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, server_default=true())
    last_login: Mapped[datetime | None] = mapped_column(UTCDateTime())

    def __str__(self) -> str:
        return self.email


class AuditLog(UUIDPk, Base):
    __tablename__ = "audit_log"
    __table_args__ = (
        Index("ix_audit_log_model_pk", "model", "pk"),
        Index("ix_audit_log_at", "at"),
    )

    staff_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("staff_users.id", ondelete="SET NULL"), index=True
    )
    # Kept even if the staff row goes: "env:admin" for the dev env-credential login.
    staff_email: Mapped[str | None] = mapped_column(String(254))
    # create | edit | delete | soft_delete | action:<name> | login
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    model: Mapped[str] = mapped_column(String(64), nullable=False)
    pk: Mapped[str | None] = mapped_column(String(64))
    before: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    after: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
