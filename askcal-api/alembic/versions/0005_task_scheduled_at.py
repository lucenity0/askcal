"""tasks.scheduled_at — user-pinned start time

Revision ID: 0005
Revises: 0004
Create Date: 2026-07-07

"""
import sqlalchemy as sa

from alembic import op

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "tasks", sa.Column("scheduled_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("tasks", "scheduled_at")
