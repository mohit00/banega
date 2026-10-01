"""staff accounts (email + argon2id + TOTP) and the admin audit log (review B2/B3, H4)

Revision ID: 0008_staff_audit
Revises: 0007_purge_tombstone
Create Date: 2026-09-27
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008_staff_audit"
down_revision: str | None = "0007_purge_tombstone"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON = sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")


def upgrade() -> None:
    op.create_table(
        "staff_users",
        sa.Column("email", sa.String(length=254), nullable=False),
        sa.Column("password_hash", sa.String(length=255), nullable=False),
        sa.Column("totp_secret", sa.String(length=64), nullable=False),
        sa.Column("totp_enrolled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("totp_shown_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column("last_login", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_staff_users")),
        sa.UniqueConstraint("email", name=op.f("uq_staff_users_email")),
    )
    op.create_table(
        "audit_log",
        sa.Column("staff_id", sa.Uuid(), nullable=True),
        sa.Column("staff_email", sa.String(length=254), nullable=True),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("model", sa.String(length=64), nullable=False),
        sa.Column("pk", sa.String(length=64), nullable=True),
        sa.Column("before", JSON, nullable=True),
        sa.Column("after", JSON, nullable=True),
        sa.Column("at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["staff_id"],
            ["staff_users.id"],
            name=op.f("fk_audit_log_staff_id_staff_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_audit_log")),
    )
    with op.batch_alter_table("audit_log", schema=None) as batch_op:
        batch_op.create_index("ix_audit_log_at", ["at"], unique=False)
        batch_op.create_index("ix_audit_log_model_pk", ["model", "pk"], unique=False)
        batch_op.create_index(batch_op.f("ix_audit_log_staff_id"), ["staff_id"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("audit_log", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_audit_log_staff_id"))
        batch_op.drop_index("ix_audit_log_model_pk")
        batch_op.drop_index("ix_audit_log_at")
    op.drop_table("audit_log")
    op.drop_table("staff_users")
