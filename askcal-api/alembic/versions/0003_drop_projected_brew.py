"""drop day_logs.projected_brew — brew model retired

Revision ID: 0003
Revises: 0002
Create Date: 2026-07-08

"""
from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("day_logs", "projected_brew")


def downgrade() -> None:
    op.add_column("day_logs", sa.Column("projected_brew", sa.String(20), nullable=True))
