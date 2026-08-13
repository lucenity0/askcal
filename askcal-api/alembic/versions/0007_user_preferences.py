"""Per-user preferences

Revision ID: 0007
Revises: 0006
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

from alembic import op

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # JSONB rather than a column per setting. These are a handful of small
    # knobs that will keep changing shape while the app finds its feet, and a
    # migration per knob is a bad trade for that. Anything that grows a query
    # against it earns its own column then.
    #
    # server_default so existing rows are readable immediately without a
    # backfill — a NULL here would mean every settings read needs a None check
    # forever.
    op.add_column(
        "users",
        sa.Column(
            "preferences",
            JSONB(),
            nullable=False,
            server_default=sa.text("'{}'::jsonb"),
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "preferences")
