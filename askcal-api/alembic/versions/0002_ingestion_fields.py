"""ingestion fields — email body/signals, user last_synced_at

Revision ID: 0002
Revises: 0001
Create Date: 2026-07-04

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("emails", sa.Column("body_text", sa.Text(), nullable=True))
    op.add_column("emails", sa.Column("signals", postgresql.JSONB(), nullable=True))
    op.add_column(
        "users", sa.Column("last_synced_at", sa.DateTime(timezone=True), nullable=True)
    )


def downgrade() -> None:
    op.drop_column("users", "last_synced_at")
    op.drop_column("emails", "signals")
    op.drop_column("emails", "body_text")
