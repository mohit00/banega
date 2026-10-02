"""invites.code_hash: a short human-typeable invite code ("Join my family with a code")

Revision ID: 0012_invite_code
Revises: 0011_side_category
Create Date: 2026-10-02
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012_invite_code"
down_revision: str | None = "0011_side_category"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    with op.batch_alter_table("invites", schema=None) as batch_op:
        batch_op.add_column(sa.Column("code_hash", sa.String(length=64), nullable=True))
        batch_op.create_index(batch_op.f("ix_invites_code_hash"), ["code_hash"], unique=False)


def downgrade() -> None:
    with op.batch_alter_table("invites", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_invites_code_hash"))
        batch_op.drop_column("code_hash")
