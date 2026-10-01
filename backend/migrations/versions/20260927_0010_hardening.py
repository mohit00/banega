"""hardening: allergen picklist (members.allergens_other + normalised allergens),
notification_marks (worker dedupe), push_outbox (push after commit), tickets.at_risk_alerted_at
(accepted-not-cooking alert), one pending export per household, members.vrat_days +
members.show_on_home (client fields)
(review H3, H1/M10, M6, M7; primary #4, #7/#8)

Revision ID: 0010_hardening
Revises: 0009_constraints
Create Date: 2026-09-27

Data: member / ingredient / recipe allergens are normalised to the Allergen picklist
("Peanuts" -> peanut, "kaju" -> tree_nut). Member values off the picklist move to
members.allergens_other (a warning, never a hard No); unknown ingredient / recipe values are
dropped (they could only ever match a member's free text).
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0010_hardening"
down_revision: str | None = "0009_constraints"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON = sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql")

# Frozen copy of app.services.allergens at this revision (migrations must not import app code
# that may change later).
PICKLIST = {
    "peanut",
    "tree_nut",
    "milk",
    "gluten",
    "sesame",
    "soy",
    "egg",
    "fish",
    "shellfish",
    "mustard",
}
SYNONYMS = {
    "peanuts": "peanut",
    "groundnut": "peanut",
    "groundnuts": "peanut",
    "moongphali": "peanut",
    "mungfali": "peanut",
    "nuts": "tree_nut",
    "tree_nuts": "tree_nut",
    "treenut": "tree_nut",
    "cashew": "tree_nut",
    "kaju": "tree_nut",
    "almond": "tree_nut",
    "badam": "tree_nut",
    "walnut": "tree_nut",
    "akhrot": "tree_nut",
    "pista": "tree_nut",
    "pistachio": "tree_nut",
    "dairy": "milk",
    "lactose": "milk",
    "doodh": "milk",
    "wheat": "gluten",
    "maida": "gluten",
    "atta": "gluten",
    "til": "sesame",
    "soya": "soy",
    "soybean": "soy",
    "eggs": "egg",
    "anda": "egg",
    "machli": "fish",
    "prawn": "shellfish",
    "prawns": "shellfish",
    "shrimp": "shellfish",
    "crab": "shellfish",
    "jhinga": "shellfish",
    "sarson": "mustard",
    "rai": "mustard",
}


def _norm(value: object) -> str | None:
    key = str(value).strip().lower().replace("-", "_").replace(" ", "_")
    if key in PICKLIST:
        return key
    return SYNONYMS.get(key) or SYNONYMS.get(key.replace("_", ""))


def _split(values: object) -> tuple[list[str], list[str]]:
    known: set[str] = set()
    unknown: list[str] = []
    for v in values if isinstance(values, list) else []:
        n = _norm(v)
        if n is None:
            text = str(v).strip()
            if text and text not in unknown:
                unknown.append(text)
        else:
            known.add(n)
    return sorted(known), unknown


def _normalise_allergens() -> None:
    bind = op.get_bind()
    members = sa.table(
        "members",
        sa.column("id", sa.Uuid()),
        sa.column("allergens", JSON),
        sa.column("allergens_other", sa.String(200)),
    )
    for mid, allergens, other in bind.execute(
        sa.select(members.c.id, members.c.allergens, members.c.allergens_other)
    ).all():
        known, unknown = _split(allergens)
        if known == (allergens or []) and not unknown:
            continue
        extra = ", ".join([*([other] if other else []), *unknown])[:200] or None
        bind.execute(
            members.update()
            .where(members.c.id == mid)
            .values(allergens=known, allergens_other=extra)
        )
    for name in ("ingredients", "recipes"):
        t = sa.table(name, sa.column("id", sa.Uuid()), sa.column("allergens", JSON))
        for rid, allergens in bind.execute(sa.select(t.c.id, t.c.allergens)).all():
            known, _ = _split(allergens)
            if known != (allergens or []):
                bind.execute(t.update().where(t.c.id == rid).values(allergens=known))


def _pending_exports_dedupe() -> None:
    """Older duplicate pending export jobs of a household are marked failed."""
    bind = op.get_bind()
    rows = bind.execute(
        sa.text(
            "SELECT id, household_id FROM export_jobs WHERE status = 'pending' "
            "ORDER BY household_id, created_at DESC"
        )
    ).all()
    seen: set[object] = set()
    for jid, hid in rows:
        if hid in seen:
            bind.execute(
                sa.text(
                    "UPDATE export_jobs SET status = 'failed', error = 'superseded' WHERE id = :id"
                ),
                {"id": jid},
            )
        seen.add(hid)


def upgrade() -> None:
    with op.batch_alter_table("members", schema=None) as batch_op:
        batch_op.add_column(sa.Column("allergens_other", sa.String(length=200), nullable=True))
        batch_op.add_column(
            sa.Column("vrat_days", JSON, server_default=sa.text("'[]'"), nullable=False)
        )
        batch_op.add_column(
            sa.Column("show_on_home", sa.Boolean(), server_default=sa.false(), nullable=False)
        )
    _normalise_allergens()

    op.create_table(
        "notification_marks",
        sa.Column("household_id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.String(length=40), nullable=False),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_notification_marks_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_notification_marks")),
        sa.UniqueConstraint(
            "household_id",
            "kind",
            "local_date",
            name=op.f("uq_notification_marks_household_id"),
        ),
    )
    op.create_table(
        "push_outbox",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("household_id", sa.Uuid(), nullable=True),
        sa.Column("event", sa.String(length=40), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("data", JSON, nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
        sa.Column("sent_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error", sa.String(length=200), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.ForeignKeyConstraint(
            ["household_id"],
            ["households.id"],
            name=op.f("fk_push_outbox_household_id_households"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], name=op.f("fk_push_outbox_user_id_users"), ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_push_outbox")),
    )
    with op.batch_alter_table("push_outbox", schema=None) as batch_op:
        batch_op.create_index(
            batch_op.f("ix_push_outbox_household_id"), ["household_id"], unique=False
        )
        batch_op.create_index(
            "ix_push_outbox_pending", ["sent_at", "failed_at", "created_at"], unique=False
        )
        batch_op.create_index(batch_op.f("ix_push_outbox_user_id"), ["user_id"], unique=False)

    with op.batch_alter_table("tickets", schema=None) as batch_op:
        batch_op.add_column(
            sa.Column("at_risk_alerted_at", sa.DateTime(timezone=True), nullable=True)
        )

    _pending_exports_dedupe()
    with op.batch_alter_table("export_jobs", schema=None) as batch_op:
        batch_op.create_index(
            "uq_export_jobs_pending_household",
            ["household_id"],
            unique=True,
            postgresql_where=sa.text("status = 'pending'"),
            sqlite_where=sa.text("status = 'pending'"),
        )


def downgrade() -> None:
    with op.batch_alter_table("export_jobs", schema=None) as batch_op:
        batch_op.drop_index(
            "uq_export_jobs_pending_household",
            postgresql_where=sa.text("status = 'pending'"),
            sqlite_where=sa.text("status = 'pending'"),
        )
    with op.batch_alter_table("tickets", schema=None) as batch_op:
        batch_op.drop_column("at_risk_alerted_at")
    with op.batch_alter_table("push_outbox", schema=None) as batch_op:
        batch_op.drop_index(batch_op.f("ix_push_outbox_user_id"))
        batch_op.drop_index("ix_push_outbox_pending")
        batch_op.drop_index(batch_op.f("ix_push_outbox_household_id"))
    op.drop_table("push_outbox")
    op.drop_table("notification_marks")
    with op.batch_alter_table("members", schema=None) as batch_op:
        batch_op.drop_column("show_on_home")
        batch_op.drop_column("vrat_days")
        batch_op.drop_column("allergens_other")
