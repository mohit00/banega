"""purge tombstone: users.phone nullable + phone_deleted_at (review C2)

Revision ID: 0007_purge_tombstone
Revises: 0006_feedback
Create Date: 2026-09-27

The nightly purge used to write ``deleted:{uuid}`` (44 chars) into ``users.phone``
(VARCHAR(20)), which fails on Postgres and rolled back every purge. A purged user now has
``phone = NULL`` and ``phone_deleted_at`` set.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0007_purge_tombstone"
down_revision: str | None = "0006_feedback"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.add_column(sa.Column("phone_deleted_at", sa.DateTime(timezone=True)))
        batch_op.alter_column("phone", existing_type=sa.String(length=20), nullable=True)
    # Tombstones written by the old purge (only possible where VARCHAR is not enforced).
    op.execute(
        "UPDATE users SET phone = NULL, phone_deleted_at = updated_at "
        "WHERE phone LIKE 'deleted:%'"
    )


def downgrade() -> None:
    bind = op.get_bind()
    # A short unique tombstone that fits VARCHAR(20): "del:" + 16 hex chars of the id.
    if bind.dialect.name == "postgresql":
        op.execute(
            "UPDATE users SET phone = 'del:' || substr(replace(id::text, '-', ''), 1, 16) "
            "WHERE phone IS NULL"
        )
    else:
        op.execute(
            "UPDATE users SET phone = 'del:' || substr(replace(id, '-', ''), 1, 16) "
            "WHERE phone IS NULL"
        )
    with op.batch_alter_table("users", schema=None) as batch_op:
        batch_op.alter_column("phone", existing_type=sa.String(length=20), nullable=False)
        batch_op.drop_column("phone_deleted_at")
