"""Operational tables for the worker (review H1, M7).

- :class:`NotificationMark`: "this household already got <kind> on <local date>" (tomorrow's
  tickets, trial reminders, weekly summary). A unique row replaces scanning the inbox.
- :class:`PushOutbox`: pushes are written in the request's transaction and delivered after
  commit by the ARQ worker (never from inside a transaction that may still roll back).
"""

from __future__ import annotations

import uuid
from datetime import date as date_type
from datetime import datetime
from typing import Any

from sqlalchemy import Date, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONType, UTCDateTime, UUIDPk, utcnow


class NotificationMark(UUIDPk, Base):
    __tablename__ = "notification_marks"
    __table_args__ = (UniqueConstraint("household_id", "kind", "local_date"),)

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(String(40), nullable=False)
    local_date: Mapped[date_type] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)


class PushOutbox(UUIDPk, Base):
    __tablename__ = "push_outbox"
    __table_args__ = (Index("ix_push_outbox_pending", "sent_at", "failed_at", "created_at"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    household_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True
    )
    event: Mapped[str] = mapped_column(String(40), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    data: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, server_default="0", nullable=False)
    sent_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    # Given up after MAX_ATTEMPTS (last_error says why).
    failed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    last_error: Mapped[str | None] = mapped_column(String(200))
