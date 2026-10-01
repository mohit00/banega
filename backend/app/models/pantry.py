"""Pantry stock, ration requests, approvals and ticket stock issues (Phase 6; FRD §5.8, §5.9 as
amended by docs/frd-review.md F-5.8-01/02, F-5.6-04, F-5.9-01, F-2-02/04).

``StockItem`` is the single source of truth for "do we have it" (F-5.6-04): menu and ticket
``required_items`` read it at render time. Only ingredients with a ``Staple`` row are tracked;
a staple without a ``StockItem`` row reads ``in`` (rows are materialised on the first
``GET /v1/stock``).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    Boolean,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, JSONType, Timestamped, UTCDateTime, UUIDPk, str_enum, utcnow
from app.models.enums import (
    ApprovalDecision,
    ApprovalType,
    IssueResolution,
    LadderStep,
    RationStatus,
    StockLevel,
)


class StockItem(UUIDPk, Timestamped, Base):
    __tablename__ = "stock_items"
    __table_args__ = (UniqueConstraint("household_id", "ingredient_id"),)

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ingredients.id", ondelete="CASCADE"), nullable=False
    )
    level: Mapped[StockLevel] = mapped_column(
        str_enum(StockLevel, "stock_level"), default=StockLevel.in_, nullable=False
    )
    qty: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(16))
    updated_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )


class RationRequest(UUIDPk, Timestamped, Base):
    __tablename__ = "ration_requests"
    __table_args__ = (Index("ix_ration_requests_household_status", "household_id", "status"),)

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    ticket_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("tickets.id", ondelete="SET NULL")
    )
    status: Mapped[RationStatus] = mapped_column(
        str_enum(RationStatus, "ration_status"), default=RationStatus.pending, nullable=False
    )
    raised_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    # F-2-04: an admin / family cook raising her own list approves it in the same step.
    auto_approved: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    decided_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    decided_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    note: Mapped[str | None] = mapped_column(Text)
    decision_note: Mapped[str | None] = mapped_column(Text)
    bought_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    bought_at: Mapped[datetime | None] = mapped_column(UTCDateTime())

    items: Mapped[list[RationItem]] = relationship(
        back_populates="request",
        cascade="all, delete-orphan",
        order_by="RationItem.sort_order",
        lazy="selectin",
    )


class RationItem(UUIDPk, Base):
    __tablename__ = "ration_items"

    request_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ration_requests.id", ondelete="CASCADE"), index=True, nullable=False
    )
    # Null = the cook's free text did not match the catalogue; ``name`` keeps it.
    ingredient_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ingredients.id", ondelete="SET NULL")
    )
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    qty: Mapped[Decimal | None] = mapped_column(Numeric(10, 3))
    unit: Mapped[str | None] = mapped_column(String(16))
    note: Mapped[str | None] = mapped_column(String(200))
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")

    request: Mapped[RationRequest] = relationship(back_populates="items")


class Approval(UUIDPk, Base):
    """One approval step (§2.1): a swap or dish change on a ticket, or a ration request.

    ``decision`` null = pending. The first response wins: deciding is a guarded UPDATE
    (``WHERE decision IS NULL``). ``auto`` marks a self-approval (F-2-04), logged but skipped.
    """

    __tablename__ = "approvals"
    __table_args__ = (Index("ix_approvals_household_decision", "household_id", "decision"),)

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    ticket_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("tickets.id", ondelete="CASCADE"), index=True
    )
    ration_request_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ration_requests.id", ondelete="CASCADE"), index=True
    )
    type: Mapped[ApprovalType] = mapped_column(
        str_enum(ApprovalType, "approval_type"), nullable=False
    )
    requested_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    decided_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    decision: Mapped[ApprovalDecision | None] = mapped_column(
        str_enum(ApprovalDecision, "approval_decision")
    )
    decided_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    auto: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    expires_at: Mapped[datetime | None] = mapped_column(UTCDateTime(), index=True)
    # {issue_id, action, ingredient_id, substitute_ingredient_id | recipe_id, ...}
    payload: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)


class TicketStockIssue(UUIDPk, Base):
    """An item marked Out on a ticket and how the §5.9 ladder resolved it."""

    __tablename__ = "ticket_stock_issues"
    __table_args__ = (Index("ix_ticket_stock_issues_ticket", "ticket_id", "ingredient_id"),)

    ticket_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tickets.id", ondelete="CASCADE"), nullable=False
    )
    ingredient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ingredients.id", ondelete="CASCADE"), nullable=False
    )
    # First applicable ladder step when the item was marked Out.
    step: Mapped[LadderStep] = mapped_column(str_enum(LadderStep, "ladder_step"), nullable=False)
    resolution: Mapped[IssueResolution | None] = mapped_column(
        str_enum(IssueResolution, "issue_resolution")
    )
    substitute_ingredient_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("ingredients.id", ondelete="SET NULL")
    )
    new_recipe_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("recipes.id", ondelete="SET NULL")
    )
    approval_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("approvals.id", ondelete="SET NULL")
    )
    raised_by: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
