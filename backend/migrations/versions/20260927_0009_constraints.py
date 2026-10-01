"""constraints: one active membership per login, one hired cook per household, unique cook
phone per household, unique store purchase ids, missing FK / status / inbox indexes
(review H5, primary #1 and #12)

Revision ID: 0009_constraints
Revises: 0008_staff_audit
Create Date: 2026-09-27

Existing rows that would break the new unique indexes are repaired first (older duplicates
are released: membership -> removed, hired cook -> removed_at, purchase ids -> NULL on the
older subscription).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009_constraints"
down_revision: str | None = "0008_staff_audit"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def _dedupe() -> None:
    bind = op.get_bind()
    # Memberships: keep the newest active one per user, preferring live households.
    rows = bind.execute(
        sa.text(
            "SELECT m.id, m.user_id FROM household_memberships m "
            "JOIN households h ON h.id = m.household_id WHERE m.status = 'active' "
            "ORDER BY m.user_id, (h.deleted_at IS NULL) DESC, m.created_at DESC"
        )
    ).all()
    seen: set[object] = set()
    for mid, uid in rows:
        if uid in seen:
            bind.execute(
                sa.text("UPDATE household_memberships SET status = 'removed' WHERE id = :id"),
                {"id": mid},
            )
        seen.add(uid)
    # Hired cooks: keep the newest active one per household.
    rows = bind.execute(
        sa.text(
            "SELECT id, household_id FROM cooks WHERE kind = 'hired' AND removed_at IS NULL "
            "ORDER BY household_id, created_at DESC"
        )
    ).all()
    seen = set()
    for cid, hid in rows:
        if hid in seen:
            bind.execute(
                sa.text("UPDATE cooks SET removed_at = CURRENT_TIMESTAMP WHERE id = :id"),
                {"id": cid},
            )
        seen.add(hid)
    # Same active phone twice in one household.
    rows = bind.execute(
        sa.text(
            "SELECT id, household_id, phone FROM cooks "
            "WHERE phone IS NOT NULL AND removed_at IS NULL ORDER BY household_id, created_at DESC"
        )
    ).all()
    seen = set()
    for cid, hid, phone in rows:
        if (hid, phone) in seen:
            bind.execute(
                sa.text("UPDATE cooks SET removed_at = CURRENT_TIMESTAMP WHERE id = :id"),
                {"id": cid},
            )
        seen.add((hid, phone))
    # Store purchase ids: the most recently updated subscription keeps them.
    for col in ("purchase_token", "original_transaction_id"):
        rows = bind.execute(
            sa.text(
                f"SELECT id, {col} FROM subscriptions WHERE {col} IS NOT NULL "
                f"ORDER BY {col}, updated_at DESC"
            )
        ).all()
        seen = set()
        for sid, value in rows:
            if value in seen:
                bind.execute(
                    sa.text(f"UPDATE subscriptions SET {col} = NULL WHERE id = :id"), {"id": sid}
                )
            seen.add(value)


def upgrade() -> None:
    _dedupe()
    with op.batch_alter_table("cooks", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_cooks_member_id"), ["member_id"], unique=False)
        batch_op.create_index(batch_op.f("ix_cooks_user_id"), ["user_id"], unique=False)
        batch_op.create_index(
            "uq_cooks_active_phone_per_household",
            ["household_id", "phone"],
            unique=True,
            postgresql_where=sa.text("phone IS NOT NULL AND removed_at IS NULL"),
            sqlite_where=sa.text("phone IS NOT NULL AND removed_at IS NULL"),
        )
        batch_op.create_index(
            "uq_cooks_one_hired_per_household",
            ["household_id"],
            unique=True,
            postgresql_where=sa.text("kind = 'hired' AND removed_at IS NULL"),
            sqlite_where=sa.text("kind = 'hired' AND removed_at IS NULL"),
        )

    with op.batch_alter_table("household_memberships", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_household_memberships_cook_id"), ["cook_id"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_household_memberships_member_id"), ["member_id"], unique=False
        )
        batch_op.create_index(
            "uq_household_memberships_active_user",
            ["user_id"],
            unique=True,
            postgresql_where=sa.text("status = 'active'"),
            sqlite_where=sa.text("status = 'active'"),
        )

    with op.batch_alter_table("inbox_items", schema=None) as batch_op:
        batch_op.create_index(
            "ix_inbox_items_household_event_created",
            ["household_id", "event", "created_at"],
            unique=False,
        )

    with op.batch_alter_table("invites", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_invites_created_by"), ["created_by"], unique=False)
        batch_op.create_index(batch_op.f("ix_invites_member_id"), ["member_id"], unique=False)

    with op.batch_alter_table("recipes", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_recipes_status"), ["status"], unique=False)

    with op.batch_alter_table("subscriptions", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_subscriptions_original_transaction_id"))
        batch_op.create_index(
            batch_op.f("ix_subscriptions_original_transaction_id"),
            ["original_transaction_id"],
            unique=True,
        )
        batch_op.drop_index(batch_op.f("ix_subscriptions_purchase_token"))
        batch_op.create_index(
            batch_op.f("ix_subscriptions_purchase_token"), ["purchase_token"], unique=True
        )

    with op.batch_alter_table("substitution_rules", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_substitution_rules_to_ingredient_id"), ["to_ingredient_id"], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table("substitution_rules", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_substitution_rules_to_ingredient_id"))

    with op.batch_alter_table("subscriptions", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_subscriptions_purchase_token"))
        batch_op.create_index(
            batch_op.f("ix_subscriptions_purchase_token"), ["purchase_token"], unique=False
        )
        batch_op.drop_index(batch_op.f("ix_subscriptions_original_transaction_id"))
        batch_op.create_index(
            batch_op.f("ix_subscriptions_original_transaction_id"),
            ["original_transaction_id"],
            unique=False,
        )

    with op.batch_alter_table("recipes", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_recipes_status"))

    with op.batch_alter_table("invites", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_invites_member_id"))
        batch_op.drop_index(batch_op.f("ix_invites_created_by"))

    with op.batch_alter_table("inbox_items", schema=None) as batch_op:
        batch_op.drop_index("ix_inbox_items_household_event_created")

    with op.batch_alter_table("household_memberships", schema=None) as batch_op:
        batch_op.drop_index(
            "uq_household_memberships_active_user",
            postgresql_where=sa.text("status = 'active'"),
            sqlite_where=sa.text("status = 'active'"),
        )
        batch_op.drop_index(batch_op.f("ix_household_memberships_member_id"))
        batch_op.drop_index(batch_op.f("ix_household_memberships_cook_id"))

    with op.batch_alter_table("cooks", schema=None) as batch_op:
        batch_op.drop_index(
            "uq_cooks_one_hired_per_household",
            postgresql_where=sa.text("kind = 'hired' AND removed_at IS NULL"),
            sqlite_where=sa.text("kind = 'hired' AND removed_at IS NULL"),
        )
        batch_op.drop_index(
            "uq_cooks_active_phone_per_household",
            postgresql_where=sa.text("phone IS NOT NULL AND removed_at IS NULL"),
            sqlite_where=sa.text("phone IS NOT NULL AND removed_at IS NULL"),
        )
        batch_op.drop_index(batch_op.f("ix_cooks_user_id"))
        batch_op.drop_index(batch_op.f("ix_cooks_member_id"))
