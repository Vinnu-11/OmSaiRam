"""Add start_chapter to groups table.

Revision ID: 001_add_start_chapter
Revises:
Create Date: 2026-07-23

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '001_add_start_chapter'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        'groups',
        sa.Column('start_chapter', sa.Integer(), nullable=True, server_default='1'),
    )


def downgrade() -> None:
    op.drop_column('groups', 'start_chapter')
