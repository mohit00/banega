"""kitchen: day menus, tickets (+ change log, messages), inbox, cook duty (Phase 5)

Revision ID: 0004_kitchen
Revises: 0003_chat
Create Date: 2026-09-26

Adds Household.eater_defaults (F-5.6-01) and Cook.off_duty_until / off_duty_reason / phone /
removed_at (F-5.7-06, FR-K20, F-5.7-10). menus.ticket_id has no FK on purpose (menus <->
tickets would be a cycle).
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0004_kitchen'
down_revision: str | None = '0003_chat'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('cook_duty_log',
    sa.Column('cook_id', sa.Uuid(), nullable=False),
    sa.Column('at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('on_duty', sa.Boolean(), nullable=False),
    sa.Column('until', sa.DateTime(timezone=True), nullable=True),
    sa.Column('reason', sa.String(length=40), nullable=True),
    sa.Column('by_user_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['by_user_id'], ['users.id'], name=op.f('fk_cook_duty_log_by_user_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['cook_id'], ['cooks.id'], name=op.f('fk_cook_duty_log_cook_id_cooks'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_cook_duty_log'))
    )
    with op.batch_alter_table('cook_duty_log', schema=None) as batch_op:
        batch_op.create_index('ix_cook_duty_log_cook_at', ['cook_id', 'at'], unique=False)

    op.create_table('menus',
    sa.Column('household_id', sa.Uuid(), nullable=False),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('slot', sa.String(length=16), nullable=False),
    sa.Column('eaters', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('guests', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('servings', sa.Numeric(precision=6, scale=2), nullable=False),
    sa.Column('due_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('assignee_cook_id', sa.Uuid(), nullable=True),
    sa.Column('notes', sa.Text(), nullable=True),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('ticket_id', sa.Uuid(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['assignee_cook_id'], ['cooks.id'], name=op.f('fk_menus_assignee_cook_id_cooks'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['household_id'], ['households.id'], name=op.f('fk_menus_household_id_households'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_menus')),
    sa.UniqueConstraint('household_id', 'date', 'slot', name=op.f('uq_menus_household_id'))
    )
    with op.batch_alter_table('menus', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_menus_household_id'), ['household_id'], unique=False)

    op.create_table('menu_dishes',
    sa.Column('menu_id', sa.Uuid(), nullable=False),
    sa.Column('recipe_id', sa.Uuid(), nullable=False),
    sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['menu_id'], ['menus.id'], name=op.f('fk_menu_dishes_menu_id_menus'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['recipe_id'], ['recipes.id'], name=op.f('fk_menu_dishes_recipe_id_recipes'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_menu_dishes')),
    sa.UniqueConstraint('menu_id', 'recipe_id', name=op.f('uq_menu_dishes_menu_id'))
    )
    with op.batch_alter_table('menu_dishes', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_menu_dishes_menu_id'), ['menu_id'], unique=False)

    op.create_table('tickets',
    sa.Column('household_id', sa.Uuid(), nullable=False),
    sa.Column('menu_id', sa.Uuid(), nullable=True),
    sa.Column('date', sa.Date(), nullable=False),
    sa.Column('slot', sa.String(length=16), nullable=False),
    sa.Column('due_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('status', sa.Enum('new', 'unassigned', 'accepted', 'cooking', 'ready', 'completed', 'not_confirmed', 'cancelled', name='ticket_status', native_enum=False, create_constraint=True, length=32), nullable=False),
    sa.Column('assignee_cook_id', sa.Uuid(), nullable=True),
    sa.Column('confirmed_by_user_id', sa.Uuid(), nullable=True),
    sa.Column('dishes', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('eaters', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('guests', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('servings', sa.Numeric(precision=6, scale=2), nullable=False),
    sa.Column('notes', sa.Text(), nullable=True),
    sa.Column('stock_issue_open', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('updated', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('started_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('ready_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('completed_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('completed_by', sa.Uuid(), nullable=True),
    sa.Column('rated_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('cancel_reason', sa.String(length=200), nullable=True),
    sa.Column('status_changed_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('no_show_alerted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['assignee_cook_id'], ['cooks.id'], name=op.f('fk_tickets_assignee_cook_id_cooks'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['completed_by'], ['users.id'], name=op.f('fk_tickets_completed_by_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['confirmed_by_user_id'], ['users.id'], name=op.f('fk_tickets_confirmed_by_user_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['household_id'], ['households.id'], name=op.f('fk_tickets_household_id_households'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['menu_id'], ['menus.id'], name=op.f('fk_tickets_menu_id_menus'), ondelete='SET NULL'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_tickets'))
    )
    with op.batch_alter_table('tickets', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_tickets_assignee_cook_id'), ['assignee_cook_id'], unique=False)
        batch_op.create_index('ix_tickets_household_date', ['household_id', 'date'], unique=False)
        batch_op.create_index(batch_op.f('ix_tickets_menu_id'), ['menu_id'], unique=False)
        batch_op.create_index('ix_tickets_status_due', ['status', 'due_at'], unique=False)

    op.create_table('inbox_items',
    sa.Column('household_id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('event', sa.String(length=40), nullable=False),
    sa.Column('title', sa.String(length=200), nullable=False),
    sa.Column('body', sa.Text(), nullable=False),
    sa.Column('ticket_id', sa.Uuid(), nullable=True),
    sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['household_id'], ['households.id'], name=op.f('fk_inbox_items_household_id_households'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['ticket_id'], ['tickets.id'], name=op.f('fk_inbox_items_ticket_id_tickets'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_inbox_items_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_inbox_items'))
    )
    with op.batch_alter_table('inbox_items', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_inbox_items_household_id'), ['household_id'], unique=False)
        batch_op.create_index('ix_inbox_items_user_created', ['user_id', 'created_at'], unique=False)

    op.create_table('ticket_events',
    sa.Column('ticket_id', sa.Uuid(), nullable=False),
    sa.Column('at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('by_user_id', sa.Uuid(), nullable=True),
    sa.Column('action', sa.String(length=40), nullable=False),
    sa.Column('detail', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['by_user_id'], ['users.id'], name=op.f('fk_ticket_events_by_user_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['ticket_id'], ['tickets.id'], name=op.f('fk_ticket_events_ticket_id_tickets'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ticket_events'))
    )
    with op.batch_alter_table('ticket_events', schema=None) as batch_op:
        batch_op.create_index('ix_ticket_events_ticket_at', ['ticket_id', 'at'], unique=False)

    op.create_table('ticket_messages',
    sa.Column('ticket_id', sa.Uuid(), nullable=False),
    sa.Column('author_user_id', sa.Uuid(), nullable=True),
    sa.Column('text', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['author_user_id'], ['users.id'], name=op.f('fk_ticket_messages_author_user_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['ticket_id'], ['tickets.id'], name=op.f('fk_ticket_messages_ticket_id_tickets'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ticket_messages'))
    )
    with op.batch_alter_table('ticket_messages', schema=None) as batch_op:
        batch_op.create_index('ix_ticket_messages_ticket_created', ['ticket_id', 'created_at'], unique=False)

    with op.batch_alter_table('cooks', schema=None) as batch_op:
        batch_op.add_column(sa.Column('off_duty_until', sa.DateTime(timezone=True), nullable=True))
        batch_op.add_column(sa.Column('off_duty_reason', sa.String(length=40), nullable=True))
        batch_op.add_column(sa.Column('phone', sa.String(length=20), nullable=True))
        batch_op.add_column(sa.Column('removed_at', sa.DateTime(timezone=True), nullable=True))
        batch_op.create_index(batch_op.f('ix_cooks_phone'), ['phone'], unique=False)

    with op.batch_alter_table('households', schema=None) as batch_op:
        batch_op.add_column(sa.Column('eater_defaults', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), server_default=sa.text("'{}'"), nullable=False))



def downgrade() -> None:
    with op.batch_alter_table('households', schema=None) as batch_op:
        batch_op.drop_column('eater_defaults')

    with op.batch_alter_table('cooks', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_cooks_phone'))
        batch_op.drop_column('removed_at')
        batch_op.drop_column('phone')
        batch_op.drop_column('off_duty_reason')
        batch_op.drop_column('off_duty_until')

    with op.batch_alter_table('ticket_messages', schema=None) as batch_op:
        batch_op.drop_index('ix_ticket_messages_ticket_created')

    op.drop_table('ticket_messages')
    with op.batch_alter_table('ticket_events', schema=None) as batch_op:
        batch_op.drop_index('ix_ticket_events_ticket_at')

    op.drop_table('ticket_events')
    with op.batch_alter_table('inbox_items', schema=None) as batch_op:
        batch_op.drop_index('ix_inbox_items_user_created')
        batch_op.drop_index(batch_op.f('ix_inbox_items_household_id'))

    op.drop_table('inbox_items')
    with op.batch_alter_table('tickets', schema=None) as batch_op:
        batch_op.drop_index('ix_tickets_status_due')
        batch_op.drop_index(batch_op.f('ix_tickets_menu_id'))
        batch_op.drop_index('ix_tickets_household_date')
        batch_op.drop_index(batch_op.f('ix_tickets_assignee_cook_id'))

    op.drop_table('tickets')
    with op.batch_alter_table('menu_dishes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_menu_dishes_menu_id'))

    op.drop_table('menu_dishes')
    with op.batch_alter_table('menus', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_menus_household_id'))

    op.drop_table('menus')
    with op.batch_alter_table('cook_duty_log', schema=None) as batch_op:
        batch_op.drop_index('ix_cook_duty_log_cook_at')

    op.drop_table('cook_duty_log')
