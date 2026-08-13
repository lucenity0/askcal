"""Record that a sync ran, not only that one worked

Revision ID: 0012
Revises: 0011

`users.last_synced_at` was written only when a mailbox fetch succeeded, and the
settings screen showed it under "Last run". So a sync that ran on time and
failed — a revoked token, a Gmail hiccup — left an hour-old timestamp beside
"every 10 min", which reads as the sync being broken rather than as one attempt
having failed, and gives no clue which.

Two columns: when a pass last ran, and what went wrong if anything.
`last_synced_at` keeps its old meaning — the last time mail actually arrived.
"""

import sqlalchemy as sa

from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users", sa.Column("last_sync_attempt_at", sa.DateTime(timezone=True))
    )
    op.add_column("users", sa.Column("last_sync_error", sa.Text()))


def downgrade() -> None:
    op.drop_column("users", "last_sync_error")
    op.drop_column("users", "last_sync_attempt_at")
