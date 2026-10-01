"""chat: Maharaj chat sessions and messages (Phase 4)

Revision ID: 0003_chat
Revises: 0002_catalogue
Create Date: 2026-09-26

Sessions are per user and private (F-5.4-01); the worker deletes sessions idle for more than
CHAT_RETENTION_DAYS (messages cascade).
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003_chat"
down_revision: str | None = "0002_catalogue"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _json() -> sa.types.TypeEngine[object]:
    return sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")


def upgrade() -> None:
    op.create_table(
        "chat_sessions",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("slot", sa.String(length=16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("last_active_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_chat_sessions_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_chat_sessions_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_chat_sessions")),
    )
    op.create_index(
        op.f("ix_chat_sessions_household_id"), "chat_sessions", ["household_id"], unique=False
    )
    op.create_index(op.f("ix_chat_sessions_user_id"), "chat_sessions", ["user_id"], unique=False)
    op.create_index(
        op.f("ix_chat_sessions_last_active_at"), "chat_sessions", ["last_active_at"], unique=False
    )
    op.create_table(
        "chat_messages",
        sa.Column("session_id", sa.Uuid(), nullable=False),
        sa.Column(
            "author",
            sa.Enum(
                "user", "bot", name="chat_author", native_enum=False, create_constraint=True,
                length=32,
            ),
            nullable=False,
        ),
        sa.Column("text", sa.Text(), nullable=True),
        sa.Column("parsed_filters", _json(), nullable=True),
        sa.Column("recipe_ids", _json(), nullable=False),
        sa.Column("chips", _json(), nullable=False),
        sa.Column("slot", sa.String(length=16), nullable=True),
        sa.Column("latency_ms", _json(), nullable=True),
        sa.Column(
            "status",
            sa.Enum(
                "pending", "complete", "failed", name="chat_message_status", native_enum=False,
                create_constraint=True, length=32,
            ),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["chat_sessions.id"],
            name=op.f("fk_chat_messages_session_id_chat_sessions"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_chat_messages")),
    )
    op.create_index(
        "ix_chat_messages_session_created",
        "chat_messages",
        ["session_id", "created_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_chat_messages_session_created", table_name="chat_messages")
    op.drop_table("chat_messages")
    op.drop_index(op.f("ix_chat_sessions_last_active_at"), table_name="chat_sessions")
    op.drop_index(op.f("ix_chat_sessions_user_id"), table_name="chat_sessions")
    op.drop_index(op.f("ix_chat_sessions_household_id"), table_name="chat_sessions")
    op.drop_table("chat_sessions")
