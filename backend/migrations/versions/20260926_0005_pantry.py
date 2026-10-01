"""pantry: stock levels, ration requests, approvals, ticket stock issues (Phase 6)

Revision ID: 0005_pantry
Revises: 0004_kitchen
Create Date: 2026-09-26

Adds Household.auto_decrement (FR-S4 Should, off by default). StockItem is the single
source of truth for stock (F-5.6-04); approvals follow the §2.1 table (F-2-02/04).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005_pantry"
down_revision: str | None = "0004_kitchen"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "stock_items",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("ingredient_id", sa.Uuid(), nullable=False),
        sa.Column(
            "level",
            sa.Enum(
                "in",
                "low",
                "out",
                name="stock_level",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=False,
        ),
        sa.Column("qty", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("unit", sa.String(length=16), nullable=True),
        sa.Column("updated_by", sa.Uuid(), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_stock_items_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["ingredient_id"],
            ["ingredients.id"],
            name=op.f("fk_stock_items_ingredient_id_ingredients"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["updated_by"],
            ["users.id"],
            name=op.f("fk_stock_items_updated_by_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_stock_items")),
        sa.UniqueConstraint(
            "household_id", "ingredient_id", name=op.f("uq_stock_items_household_id")
        ),
    )
    with op.batch_alter_table("stock_items", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_stock_items_household_id"), ["household_id"], unique=False
        )

    op.create_table(
        "ration_requests",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("ticket_id", sa.Uuid(), nullable=True),
        sa.Column(
            "status",
            sa.Enum(
                "pending",
                "approved",
                "rejected",
                "bought",
                name="ration_status",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=False,
        ),
        sa.Column("raised_by", sa.Uuid(), nullable=True),
        sa.Column("auto_approved", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column("decision_note", sa.Text(), nullable=True),
        sa.Column("bought_by", sa.Uuid(), nullable=True),
        sa.Column("bought_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["bought_by"],
            ["users.id"],
            name=op.f("fk_ration_requests_bought_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["decided_by"],
            ["users.id"],
            name=op.f("fk_ration_requests_decided_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_ration_requests_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["raised_by"],
            ["users.id"],
            name=op.f("fk_ration_requests_raised_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["ticket_id"],
            ["tickets.id"],
            name=op.f("fk_ration_requests_ticket_id_tickets"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ration_requests")),
    )
    with op.batch_alter_table("ration_requests", schema=None) as batch_op:
        batch_op.create_index(
            "ix_ration_requests_household_status", ["household_id", "status"], unique=False
        )

    op.create_table(
        "approvals",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("ticket_id", sa.Uuid(), nullable=True),
        sa.Column("ration_request_id", sa.Uuid(), nullable=True),
        sa.Column(
            "type",
            sa.Enum(
                "swap",
                "change_dish",
                "ration",
                name="approval_type",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=False,
        ),
        sa.Column("requested_by", sa.Uuid(), nullable=True),
        sa.Column("decided_by", sa.Uuid(), nullable=True),
        sa.Column(
            "decision",
            sa.Enum(
                "approved",
                "rejected",
                "expired",
                name="approval_decision",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=True,
        ),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("auto", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "payload",
            sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql"),
            nullable=False,
        ),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["decided_by"],
            ["users.id"],
            name=op.f("fk_approvals_decided_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_approvals_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["ration_request_id"],
            ["ration_requests.id"],
            name=op.f("fk_approvals_ration_request_id_ration_requests"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["requested_by"],
            ["users.id"],
            name=op.f("fk_approvals_requested_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["ticket_id"],
            ["tickets.id"],
            name=op.f("fk_approvals_ticket_id_tickets"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_approvals")),
    )
    with op.batch_alter_table("approvals", schema=None) as batch_op:
        batch_op.create_index(batch_op.f("ix_approvals_expires_at"), ["expires_at"], unique=False)
        batch_op.create_index(
            "ix_approvals_household_decision", ["household_id", "decision"], unique=False
        )
        batch_op.create_index(
            batch_op.f("ix_approvals_ration_request_id"), ["ration_request_id"], unique=False
        )
        batch_op.create_index(batch_op.f("ix_approvals_ticket_id"), ["ticket_id"], unique=False)

    op.create_table(
        "ration_items",
        sa.Column("request_id", sa.Uuid(), nullable=False),
        sa.Column("ingredient_id", sa.Uuid(), nullable=True),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("qty", sa.Numeric(precision=10, scale=3), nullable=True),
        sa.Column("unit", sa.String(length=16), nullable=True),
        sa.Column("note", sa.String(length=200), nullable=True),
        sa.Column("sort_order", sa.Integer(), server_default="0", nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["ingredient_id"],
            ["ingredients.id"],
            name=op.f("fk_ration_items_ingredient_id_ingredients"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["request_id"],
            ["ration_requests.id"],
            name=op.f("fk_ration_items_request_id_ration_requests"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ration_items")),
    )
    with op.batch_alter_table("ration_items", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_ration_items_request_id"), ["request_id"], unique=False
        )

    op.create_table(
        "ticket_stock_issues",
        sa.Column("ticket_id", sa.Uuid(), nullable=False),
        sa.Column("ingredient_id", sa.Uuid(), nullable=False),
        sa.Column(
            "step",
            sa.Enum(
                "save_dish",
                "swap",
                "change_dish",
                name="ladder_step",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=False,
        ),
        sa.Column(
            "resolution",
            sa.Enum(
                "skip",
                "swap",
                "change_dish",
                name="issue_resolution",
                native_enum=False,
                create_constraint=True,
                length=32,
            ),
            nullable=True,
        ),
        sa.Column("substitute_ingredient_id", sa.Uuid(), nullable=True),
        sa.Column("new_recipe_id", sa.Uuid(), nullable=True),
        sa.Column("approval_id", sa.Uuid(), nullable=True),
        sa.Column("raised_by", sa.Uuid(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["approval_id"],
            ["approvals.id"],
            name=op.f("fk_ticket_stock_issues_approval_id_approvals"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["ingredient_id"],
            ["ingredients.id"],
            name=op.f("fk_ticket_stock_issues_ingredient_id_ingredients"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["new_recipe_id"],
            ["recipes.id"],
            name=op.f("fk_ticket_stock_issues_new_recipe_id_recipes"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["raised_by"],
            ["users.id"],
            name=op.f("fk_ticket_stock_issues_raised_by_users"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["substitute_ingredient_id"],
            ["ingredients.id"],
            name=op.f("fk_ticket_stock_issues_substitute_ingredient_id_ingredients"),
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["ticket_id"],
            ["tickets.id"],
            name=op.f("fk_ticket_stock_issues_ticket_id_tickets"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_ticket_stock_issues")),
    )
    with op.batch_alter_table("ticket_stock_issues", schema=None) as batch_op:
        batch_op.create_index(
            "ix_ticket_stock_issues_ticket", ["ticket_id", "ingredient_id"], unique=False
        )

    with op.batch_alter_table("inbox_items", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "data",
                sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql"),
                server_default=sa.text("'{}'"),
                nullable=False,
            )
        )

    with op.batch_alter_table("households", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column(
                "auto_decrement", sa.Boolean(), server_default=sa.text("false"), nullable=False
            )
        )


def downgrade() -> None:
    with op.batch_alter_table("inbox_items", schema=None) as batch_op:
        batch_op.drop_column("data")

    with op.batch_alter_table("households", schema=None) as batch_op:
        batch_op.drop_column("auto_decrement")

    with op.batch_alter_table("ticket_stock_issues", schema=None) as batch_op:
        batch_op.drop_index("ix_ticket_stock_issues_ticket")

    op.drop_table("ticket_stock_issues")
    with op.batch_alter_table("ration_items", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_ration_items_request_id"))

    op.drop_table("ration_items")
    with op.batch_alter_table("approvals", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_approvals_ticket_id"))
        batch_op.drop_index(batch_op.f("ix_approvals_ration_request_id"))
        batch_op.drop_index("ix_approvals_household_decision")
        batch_op.drop_index(batch_op.f("ix_approvals_expires_at"))

    op.drop_table("approvals")
    with op.batch_alter_table("ration_requests", schema=None) as batch_op:
        batch_op.drop_index("ix_ration_requests_household_status")

    op.drop_table("ration_requests")
    with op.batch_alter_table("stock_items", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_stock_items_household_id"))

    op.drop_table("stock_items")
