"""Ratings, served history, consent and data export (Phase 7; FRD §5.10, F-5.10-01..04,
F-X-02, FR-A8/A9).

Only tickets that reached ``completed`` produce ratings and served history (never
``not_confirmed`` or ``cancelled``).
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, Timestamped, UTCDateTime, UUIDPk, str_enum, utcnow
from app.models.enums import ExportStatus


class Rating(UUIDPk, Timestamped, Base):
    """1 bura | 2 theek | 3 bahut accha, one per (ticket, recipe, member); upsert."""

    __tablename__ = "ratings"
    __table_args__ = (
        UniqueConstraint("ticket_id", "recipe_id", "member_id"),
        CheckConstraint("score BETWEEN 1 AND 3", name="score_range"),
        Index("ix_ratings_household_recipe", "household_id", "recipe_id"),
    )

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    ticket_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tickets.id", ondelete="CASCADE"), nullable=False
    )
    recipe_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("recipes.id", ondelete="CASCADE"), nullable=False
    )
    member_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("members.id", ondelete="CASCADE"), nullable=False
    )
    # The member herself, or a proxy for a profile-only member (rate_for_profile_member).
    rated_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    score: Mapped[int] = mapped_column(Integer, nullable=False)
    note: Mapped[str | None] = mapped_column(Text)


class ServedHistory(UUIDPk, Base):
    """What was actually cooked (FR-F6): one row per dish of a completed ticket."""

    __tablename__ = "served_history"
    __table_args__ = (Index("ix_served_history_household_served", "household_id", "served_at"),)

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    recipe_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("recipes.id", ondelete="CASCADE"), nullable=False
    )
    ticket_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("tickets.id", ondelete="CASCADE"), index=True
    )
    served_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)


class Consent(UUIDPk, Base):
    """DPDP consent (F-X-02, FR-A9): one row per user and notice version."""

    __tablename__ = "consents"
    __table_args__ = (UniqueConstraint("user_id", "version"),)

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    # Null when accepted before the household existed (first-run screen); set on create/join.
    household_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True
    )
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    accepted_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)


class ExportJob(UUIDPk, Base):
    """POST /v1/export: an async JSON dump of the household data (inbox link when ready).
    One pending job per household; files and rows are deleted EXPORT_TTL_DAYS after."""

    __tablename__ = "export_jobs"
    __table_args__ = (
        Index(
            "uq_export_jobs_pending_household",
            "household_id",
            unique=True,
            postgresql_where=text("status = 'pending'"),
            sqlite_where=text("status = 'pending'"),
        ),
    )

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    requested_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    status: Mapped[ExportStatus] = mapped_column(
        str_enum(ExportStatus, "export_status"), default=ExportStatus.pending, nullable=False
    )
    file_path: Mapped[str | None] = mapped_column(String(512))
    error: Mapped[str | None] = mapped_column(String(200))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    finished_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
