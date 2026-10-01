"""feedback: ratings, served history, consent, data export, subscription lifecycle (Phase 7)

Revision ID: 0006_feedback
Revises: 0005_pantry
Create Date: 2026-09-26

Adds Household.ratings_enabled (F-5.10-04) and the Subscription store/grace/trial-claim
columns (F-3-03).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0006_feedback"
down_revision: str | None = "0005_pantry"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "consents",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=True),
        sa.Column("version", sa.String(length=32), nullable=False),
        sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_consents_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_consents_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_consents")),
        sa.UniqueConstraint("user_id", "version", name=op.f("uq_consents_user_id")),
    )
    with op.batch_alter_table("consents", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_consents_household_id"), ["household_id"], unique=False
        )
        batch_op.create_index(batch_op.f("ix_consents_user_id"), ["user_id"], unique=False)

    op.create_table(
        "export_jobs",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column(
            "status",
            sa.Enum(
                "pending",
                "done",
                "failed",
                name="export_status",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=False,
        ),
        sa.Column("file_path", sa.String(length=512), nullable=True),
        sa.Column("error", sa.String(length=200), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_export_jobs_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["requested_by"],
            ["users.id"],
            name=op.f("fk_export_jobs_requested_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_export_jobs")),
    )
    with op.batch_alter_table("export_jobs", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_export_jobs_household_id"), ["household_id"], unique=False
        )

    op.create_table(
        "ratings",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("ticket_id", sa.Uuid(), nullable=False),
        sa.Column("recipe_id", sa.Uuid(), nullable=False),
        sa.Column("member_id", sa.Uuid(), nullable=False),
        sa.Column("rated_by_user_id", sa.Uuid(), nullable=True),
        sa.Column("score", sa.Integer(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint("score BETWEEN 1 AND 3", name=op.f("ck_ratings_score_range")),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_ratings_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["member_id"],
            ["members.id"],
            name=op.f("fk_ratings_member_id_members"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["rated_by_user_id"],
            ["users.id"],
            name=op.f("fk_ratings_rated_by_user_id_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["recipe_id"],
            ["recipes.id"],
            name=op.f("fk_ratings_recipe_id_recipes"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["ticket_id"],
            ["tickets.id"],
            name=op.f("fk_ratings_ticket_id_tickets"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ratings")),
        sa.UniqueConstraint(
            "ticket_id", "recipe_id", "member_id", name=op.f("uq_ratings_ticket_id")
        ),
    )
    with op.batch_alter_table("ratings", schema=None) as batch_op:
        batch_op.create_index(
            "ix_ratings_household_recipe", ["household_id", "recipe_id"], unique=False
        )

    op.create_table(
        "served_history",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("recipe_id", sa.Uuid(), nullable=False),
        sa.Column("ticket_id", sa.Uuid(), nullable=True),
        sa.Column("served_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_served_history_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["recipe_id"],
            ["recipes.id"],
            name=op.f("fk_served_history_recipe_id_recipes"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["ticket_id"],
            ["tickets.id"],
            name=op.f("fk_served_history_ticket_id_tickets"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_served_history")),
    )
    with op.batch_alter_table("served_history", schema=None) as batch_op:
        batch_op.create_index(
            "ix_served_history_household_served", ["household_id", "served_at"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_served_history_ticket_id"), ["ticket_id"], unique=False
        )

    with op.batch_alter_table("households", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "ratings_enabled", sa.Boolean(), server_default=sa.text("true"), nullable=False
            )
        )

    with op.batch_alter_table("subscriptions", schema=None) as batch_op:
        batch_op.add_column(sa.Column("grace_until", sa.DateTime(timezone=True), nullable=True))
        batch_op.add_column(
            sa.Column("original_transaction_id", sa.String(length=128), nullable=True)
        )
        batch_op.add_column(sa.Column("purchase_token", sa.String(length=512), nullable=True))
        batch_op.add_column(sa.Column("last_event_at", sa.DateTime(timezone=True), nullable=True))
        batch_op.add_column(sa.Column("trial_phone", sa.String(length=20), nullable=True))
        batch_op.add_column(sa.Column("trial_device_id", sa.String(length=128), nullable=True))
        batch_op.create_index(
            batch_op.f("ix_subscriptions_original_transaction_id"),
            ["original_transaction_id"],
            unique=False,
        )
        batch_op.create_index(
            batch_op.f("ix_subscriptions_purchase_token"), ["purchase_token"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_subscriptions_trial_device_id"), ["trial_device_id"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_subscriptions_trial_phone"), ["trial_phone"], unique=False
        )


def downgrade() -> None:
    with op.batch_alter_table("subscriptions", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_subscriptions_trial_phone"))
        batch_op.drop_index(batch_op.f("ix_subscriptions_trial_device_id"))
        batch_op.drop_index(batch_op.f("ix_subscriptions_purchase_token"))
        batch_op.drop_index(batch_op.f("ix_subscriptions_original_transaction_id"))
        batch_op.drop_column("trial_device_id")
        batch_op.drop_column("trial_phone")
        batch_op.drop_column("last_event_at")
        batch_op.drop_column("purchase_token")
        batch_op.drop_column("original_transaction_id")
        batch_op.drop_column("grace_until")

    with op.batch_alter_table("households", schema=None) as batch_op:
        batch_op.drop_column("ratings_enabled")

    with op.batch_alter_table("served_history", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_served_history_ticket_id"))
        batch_op.drop_index("ix_served_history_household_served")

    op.drop_table("served_history")
    with op.batch_alter_table("ratings", schema=None) as batch_op:
        batch_op.drop_index("ix_ratings_household_recipe")

    op.drop_table("ratings")
    with op.batch_alter_table("export_jobs", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_export_jobs_household_id"))

    op.drop_table("export_jobs")
    with op.batch_alter_table("consents", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_consents_user_id"))
        batch_op.drop_index(batch_op.f("ix_consents_household_id"))

    op.drop_table("consents")
