"""Maharaj chat (Phase 4). Sessions are per user and private (F-5.4-01): only the user who
created a session can read it; the household admin cannot. Idle sessions are hard-deleted
after CHAT_RETENTION_DAYS by the worker."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import ForeignKey, Index, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, JSONType, UTCDateTime, UUIDPk, str_enum, utcnow
from app.models.enums import ChatAuthor, ChatMessageStatus


class ChatSession(UUIDPk, Base):
    __tablename__ = "chat_sessions"

    household_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("households.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    slot: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    last_active_at: Mapped[datetime] = mapped_column(
        UTCDateTime(), default=utcnow, index=True, nullable=False
    )
    # Idle expiry: last_active_at + CHAT_IDLE_MINUTES (F-5.4-03).
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)


class ChatMessage(UUIDPk, Base):
    __tablename__ = "chat_messages"
    __table_args__ = (Index("ix_chat_messages_session_created", "session_id", "created_at"),)

    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("chat_sessions.id", ondelete="CASCADE"), nullable=False
    )
    author: Mapped[ChatAuthor] = mapped_column(str_enum(ChatAuthor, "chat_author"), nullable=False)
    # Null while the LLM writer is still filling a bot reply (status pending).
    text: Mapped[str | None] = mapped_column(Text)
    # Bot only: {"query": ParsedQuery, "reply": template/writer context}.
    parsed_filters: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    recipe_ids: Mapped[list[str]] = mapped_column(JSONType, default=list)
    chips: Mapped[list[str]] = mapped_column(JSONType, default=list)
    slot: Mapped[str | None] = mapped_column(String(16))
    # {"parse": ms, "retrieve": ms, "rank": ms, "write": ms}
    latency_ms: Mapped[dict[str, Any] | None] = mapped_column(JSONType)
    status: Mapped[ChatMessageStatus] = mapped_column(
        str_enum(ChatMessageStatus, "chat_message_status"),
        default=ChatMessageStatus.complete,
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
