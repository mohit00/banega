"""dish_category gains `side` (chutneys, pickles, launji, sol kadhi and similar accompaniments)

Revision ID: 0011_side_category
Revises: 0010_hardening
Create Date: 2026-09-27
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0011_side_category"
down_revision: str | None = "0010_hardening"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

_OLD = ("dal", "sabzi", "rice", "roti_paratha", "curry", "snack", "sweet", "breakfast",
        "one_pot", "salad_raita", "other")  # fmt: skip
_NEW = (*_OLD[:-1], "side", "other")


def _check(values: tuple[str, ...]) -> str:
    return "dish_category IN (" + ", ".join(f"'{v}'" for v in values) + ")"


def upgrade() -> None:
    with op.batch_alter_table("recipes", schema=None) as batch_op:
        batch_op.drop_constraint(op.f("ck_recipes_dish_category"), type_="check")
        batch_op.create_check_constraint(op.f("ck_recipes_dish_category"), _check(_NEW))


def downgrade() -> None:
    op.execute("UPDATE recipes SET dish_category = 'other' WHERE dish_category = 'side'")
    with op.batch_alter_table("recipes", schema=None) as batch_op:
        batch_op.drop_constraint(op.f("ck_recipes_dish_category"), type_="check")
        batch_op.create_check_constraint(op.f("ck_recipes_dish_category"), _check(_OLD))
