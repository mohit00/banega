"""Day menus, cooking tickets, their change log and messages, the in-app inbox and the cook
duty log (Phase 5; FRD §5.6, §5.7 as amended by docs/frd-review.md F-5.6-01, F-5.7-01/02/06).

``Menu`` is the editable plan for one (date, slot); ``Ticket`` is the confirmed snapshot the
cook works from. ``Ticket.version`` / ``Menu.version`` are optimistic-lock counters: every
write bumps them by one and the UPDATE is guarded by the old value (If-Match, claim CAS).
"""

from __future__ import annotations

import uuid
from datetime import date as date_type
from datetime import datetime
from decimal import Decimal
from typing import Any

from sqlalchemy import (
    Boolean,
    Date,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    Uuid,
    false,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, JSONType, Timestamped, UTCDateTime, UUIDPk, str_enum, utcnow
from app.models.enums import TicketStatus


def _default_guests() -> dict[str, Any]:
    return {"adults": 0, "kids": 0, "diet": None}


class Menu(UUIDPk, Timestamped, Base):
    __tablename__ = "menus"
    __table_args__ = (UniqueConstraint("household_id", "date", "slot"),)

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    date: Mapped[date_type] = mapped_column(Date, nullable=False)
    slot: Mapped[str] = mapped_column(String(16), nullable=False)
    # [member_id as str]
    eaters: Mapped[list[str]] = mapped_column(JSONType, default=list)
    # {"adults": int, "kids": int, "diet": "veg" | "jain" | "non_veg" | None}
    guests: Mapped[dict[str, Any]] = mapped_column(JSONType, default=_default_guests)
    # Adult-equivalent servings: adult 1.0, kid 0.5, guests added the same way.
    servings: Mapped[Decimal] = mapped_column(Numeric(6, 2), default=Decimal("0"))
    due_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    assignee_cook_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("cooks.id", ondelete="SET NULL")
    )
    notes: Mapped[str | None] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1", nullable=False)
    # Latest ticket confirmed from this menu (no FK: menus <-> tickets would be a cycle).
    ticket_id: Mapped[uuid.UUID | None] = mapped_column(Uuid())

    __mapper_args__ = {"version_id_col": version, "version_id_generator": False}


class MenuDish(UUIDPk, Base):
    __tablename__ = "menu_dishes"
    __table_args__ = (UniqueConstraint("menu_id", "recipe_id"),)

    menu_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("menus.id", ondelete="CASCADE"), index=True, nullable=False
    )
    recipe_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("recipes.id", ondelete="CASCADE"), nullable=False
    )
    sort_order: Mapped[int] = mapped_column(Integer, default=0, server_default="0")


class Ticket(UUIDPk, Timestamped, Base):
    __tablename__ = "tickets"
    __table_args__ = (
        Index("ix_tickets_household_date", "household_id", "date"),
        Index("ix_tickets_status_due", "status", "due_at"),
    )

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), nullable=False
    )
    menu_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("menus.id", ondelete="SET NULL"), index=True
    )
    date: Mapped[date_type] = mapped_column(Date, nullable=False)
    slot: Mapped[str] = mapped_column(String(16), nullable=False)
    due_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    status: Mapped[TicketStatus] = mapped_column(
        str_enum(TicketStatus, "ticket_status"), nullable=False
    )
    assignee_cook_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("cooks.id", ondelete="SET NULL"), index=True
    )
    confirmed_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    # Snapshots taken at confirm / edit time: [MenuDish], [EaterRef], Guests.
    dishes: Mapped[list[dict[str, Any]]] = mapped_column(JSONType, default=list)
    eaters: Mapped[list[dict[str, Any]]] = mapped_column(JSONType, default=list)
    guests: Mapped[dict[str, Any]] = mapped_column(JSONType, default=_default_guests)
    servings: Mapped[Decimal] = mapped_column(Numeric(6, 2), default=Decimal("0"))
    notes: Mapped[str | None] = mapped_column(Text)
    stock_issue_open: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    # "Updated" tag (FR-K3): set by an edit, cleared when the assignee accepts again.
    updated: Mapped[bool] = mapped_column(Boolean, default=False, server_default=false())
    accepted_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    started_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    ready_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    completed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    completed_by: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    rated_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    cancel_reason: Mapped[str | None] = mapped_column(String(200))
    # When ``status`` last changed (drives the 24 h not_confirmed -> cancelled timer).
    status_changed_at: Mapped[datetime] = mapped_column(
        UTCDateTime(), default=utcnow, nullable=False
    )
    # F-5.7-12: the no-show alert fires once per ticket.
    no_show_alerted_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    # Accepted but not cooking shortly before due: the at-risk alert fires once per ticket.
    at_risk_alerted_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1", nullable=False)

    # Read side only (admin inline); the services append events by ticket_id.
    events: Mapped[list[TicketEvent]] = relationship(
        back_populates="ticket",
        order_by="TicketEvent.at",
        lazy="selectin",
        viewonly=True,
    )

    __mapper_args__ = {"version_id_col": version, "version_id_generator": False}


class TicketEvent(UUIDPk, Base):
    """The ticket's change_log: every action appends one row."""

    __tablename__ = "ticket_events"
    __table_args__ = (Index("ix_ticket_events_ticket_at", "ticket_id", "at"),)

    ticket_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tickets.id", ondelete="CASCADE"), nullable=False
    )
    at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    # None = the system (worker timers, off-duty reassignment).
    by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    action: Mapped[str] = mapped_column(String(40), nullable=False)
    detail: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)

    ticket: Mapped[Ticket] = relationship(back_populates="events", viewonly=True)


class TicketMessage(UUIDPk, Base):
    """K6: the simple cook <-> family thread on one ticket."""

    __tablename__ = "ticket_messages"
    __table_args__ = (Index("ix_ticket_messages_ticket_created", "ticket_id", "created_at"),)

    ticket_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("tickets.id", ondelete="CASCADE"), nullable=False
    )
    author_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
    text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)


class InboxItem(UUIDPk, Base):
    """The in-app inbox is the source of truth for notifications; push is best effort."""

    __tablename__ = "inbox_items"
    __table_args__ = (
        Index("ix_inbox_items_user_created", "user_id", "created_at"),
        # Dedupe lookups ("already sent today?") and the 90-day purge.
        Index("ix_inbox_items_household_event_created", "household_id", "event", "created_at"),
    )

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    event: Mapped[str] = mapped_column(String(40), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    ticket_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("tickets.id", ondelete="SET NULL")
    )
    # Phase 6-7 deep links: {approval_id?, ration_request_id?, link?}.
    data: Mapped[dict[str, Any]] = mapped_column(JSONType, default=dict)
    read_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)

    @property
    def approval_id(self) -> str | None:
        return (self.data or {}).get("approval_id")

    @property
    def ration_request_id(self) -> str | None:
        return (self.data or {}).get("ration_request_id")

    @property
    def link(self) -> str | None:
        return (self.data or {}).get("link")


class CookDutyLog(UUIDPk, Base):
    """FR-K13: every On/Off duty change, for the monthly duty history."""

    __tablename__ = "cook_duty_log"
    __table_args__ = (Index("ix_cook_duty_log_cook_at", "cook_id", "at"),)

    cook_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("cooks.id", ondelete="CASCADE"), nullable=False
    )
    at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    on_duty: Mapped[bool] = mapped_column(Boolean, nullable=False)
    until: Mapped[datetime | None] = mapped_column(UTCDateTime())
    reason: Mapped[str | None] = mapped_column(String(40))
    by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="SET NULL")
    )
