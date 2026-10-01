"""catalogue: ingredients, staples, recipes (+ derived diet flags, pgvector embedding),
recipe ingredients, substitution rules, app config

Revision ID: 0002_catalogue
Revises: 0001_initial
Create Date: 2026-09-26

Generated from app.models and adjusted: pgvector is enabled on Postgres only; on SQLite
(tests) the embedding column is a JSON list, matching the model's type variant.
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql
from sqlalchemy.types import TypeEngine

revision: str = "0002_catalogue"
down_revision: str | None = "0001_initial"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

EMBEDDING_DIM = 1024


def _is_postgres() -> bool:
    return op.get_context().dialect.name == "postgresql"


def _embedding_type() -> TypeEngine[object]:
    return Vector(EMBEDDING_DIM) if _is_postgres() else sa.JSON()


def upgrade() -> None:
    if _is_postgres():
        op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    op.create_table('app_config',
    sa.Column('key', sa.String(length=64), nullable=False),
    sa.Column('value', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.PrimaryKeyConstraint('key', name=op.f('pk_app_config'))
    )
    op.create_table('ingredients',
    sa.Column('slug', sa.String(length=80), nullable=False),
    sa.Column('name_en', sa.String(length=120), nullable=False),
    sa.Column('name_hi', sa.String(length=120), nullable=True),
    sa.Column('aliases', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('category', sa.Enum('vegetable', 'fruit', 'grain', 'pulse', 'dairy', 'egg', 'meat', 'seafood', 'spice', 'herb', 'oil_fat', 'sweetener', 'nut_seed', 'condiment', 'packaged', 'other', name='ingredient_category', native_enum=False, create_constraint=True, length=32), nullable=False),
    sa.Column('allergens', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('flags', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('scaling_rule', sa.Enum('linear', 'sublinear', 'fixed', name='scaling_rule', native_enum=False, create_constraint=True, length=32), nullable=False),
    sa.Column('trackable', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('purchase_unit', sa.String(length=16), nullable=True),
    sa.Column('pack_size', sa.Numeric(precision=10, scale=3), nullable=True),
    sa.Column('perishable', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_ingredients')),
    sa.UniqueConstraint('slug', name=op.f('uq_ingredients_slug'))
    )
    op.create_table('recipes',
    sa.Column('slug', sa.String(length=80), nullable=False),
    sa.Column('name', sa.String(length=120), nullable=False),
    sa.Column('name_hi', sa.String(length=120), nullable=True),
    sa.Column('sub', sa.String(length=200), nullable=True),
    sa.Column('dish_category', sa.Enum('dal', 'sabzi', 'rice', 'roti_paratha', 'curry', 'snack', 'sweet', 'breakfast', 'one_pot', 'salad_raita', 'other', name='dish_category', native_enum=False, create_constraint=True, length=32), nullable=False),
    sa.Column('dish_group_id', sa.Uuid(), nullable=True),
    sa.Column('cuisine', sa.String(length=40), nullable=True),
    sa.Column('meal_slots', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('mins', sa.Integer(), server_default='30', nullable=False),
    sa.Column('spice', sa.Integer(), server_default='2', nullable=False),
    sa.Column('tags', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('colour', sa.String(length=16), nullable=True),
    sa.Column('image_url', sa.String(length=512), nullable=True),
    sa.Column('video_url', sa.String(length=512), nullable=True),
    sa.Column('base_servings', sa.Integer(), server_default='4', nullable=False),
    sa.Column('steps_en', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('steps_hi', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('vrat_ok', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('status', sa.Enum('draft', 'reviewed', 'published', name='recipe_status', native_enum=False, create_constraint=True, length=32), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('published_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('editorial_jain_safe', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('editorial_diet', sa.String(length=16), nullable=True),
    sa.Column('is_veg', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('has_egg', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('has_nonveg', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('meat_types', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('jain_safe', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('no_onion_garlic', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('has_root_veg', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('dairy_free', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('gluten_free', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('allergens', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('policy_violations', sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), 'postgresql'), nullable=False),
    sa.Column('embedding', _embedding_type(), nullable=True),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.CheckConstraint('base_servings >= 1', name=op.f('ck_recipes_base_servings_positive')),
    sa.CheckConstraint('spice BETWEEN 1 AND 3', name=op.f('ck_recipes_spice_range')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_recipes')),
    sa.UniqueConstraint('slug', name=op.f('uq_recipes_slug'))
    )
    with op.batch_alter_table('recipes', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_recipes_dish_group_id'), ['dish_group_id'], unique=False)

    op.create_table('recipe_ingredients',
    sa.Column('recipe_id', sa.Uuid(), nullable=False),
    sa.Column('ingredient_id', sa.Uuid(), nullable=False),
    sa.Column('qty', sa.Numeric(precision=10, scale=3), nullable=True),
    sa.Column('unit', sa.String(length=16), nullable=True),
    sa.Column('display_text', sa.String(length=200), nullable=True),
    sa.Column('is_main', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('optional', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.ForeignKeyConstraint(['ingredient_id'], ['ingredients.id'], name=op.f('fk_recipe_ingredients_ingredient_id_ingredients'), ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['recipe_id'], ['recipes.id'], name=op.f('fk_recipe_ingredients_recipe_id_recipes'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_recipe_ingredients'))
    )
    with op.batch_alter_table('recipe_ingredients', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_recipe_ingredients_ingredient_id'), ['ingredient_id'], unique=False)
        batch_op.create_index(batch_op.f('ix_recipe_ingredients_recipe_id'), ['recipe_id'], unique=False)

    op.create_table('staples',
    sa.Column('ingredient_id', sa.Uuid(), nullable=False),
    sa.Column('low_threshold', sa.Numeric(precision=10, scale=3), nullable=True),
    sa.Column('default_pack_qty', sa.Numeric(precision=10, scale=3), nullable=True),
    sa.Column('sort_order', sa.Integer(), server_default='0', nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['ingredient_id'], ['ingredients.id'], name=op.f('fk_staples_ingredient_id_ingredients'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_staples')),
    sa.UniqueConstraint('ingredient_id', name=op.f('uq_staples_ingredient_id'))
    )
    op.create_table('substitution_rules',
    sa.Column('from_ingredient_id', sa.Uuid(), nullable=False),
    sa.Column('to_ingredient_id', sa.Uuid(), nullable=False),
    sa.Column('ratio', sa.Numeric(precision=6, scale=3), nullable=False),
    sa.Column('note_en', sa.Text(), nullable=True),
    sa.Column('note_hi', sa.Text(), nullable=True),
    sa.Column('cuisine_scope', sa.String(length=40), nullable=True),
    sa.Column('is_active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    sa.ForeignKeyConstraint(['from_ingredient_id'], ['ingredients.id'], name=op.f('fk_substitution_rules_from_ingredient_id_ingredients'), ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['to_ingredient_id'], ['ingredients.id'], name=op.f('fk_substitution_rules_to_ingredient_id_ingredients'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_substitution_rules')),
    sa.UniqueConstraint('from_ingredient_id', 'to_ingredient_id', 'cuisine_scope', name=op.f('uq_substitution_rules_from_ingredient_id'))
    )
    with op.batch_alter_table('substitution_rules', schema=None) as batch_op:
        batch_op.create_index(batch_op.f('ix_substitution_rules_from_ingredient_id'), ['from_ingredient_id'], unique=False)




def downgrade() -> None:
    with op.batch_alter_table('substitution_rules', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_substitution_rules_from_ingredient_id'))

    op.drop_table('substitution_rules')
    op.drop_table('staples')
    with op.batch_alter_table('recipe_ingredients', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_recipe_ingredients_recipe_id'))
        batch_op.drop_index(batch_op.f('ix_recipe_ingredients_ingredient_id'))

    op.drop_table('recipe_ingredients')
    with op.batch_alter_table('recipes', schema=None) as batch_op:
        batch_op.drop_index(batch_op.f('ix_recipes_dish_group_id'))

    op.drop_table('recipes')
    op.drop_table('ingredients')
    op.drop_table('app_config')
    # The vector extension is left installed: other objects may depend on it.
