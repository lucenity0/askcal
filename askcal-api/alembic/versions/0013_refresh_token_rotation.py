"""Link a rotated refresh token to the one that replaced it

Revision ID: 0013
Revises: 0012

A refresh token lived for thirty days and was accepted every time. Anyone who
captured one — a backup, a log, a stolen device — had thirty days of silent
access, and nothing anywhere would have looked unusual.

Rotation means each use mints a new one and retires the old. `replaced_by_id`
is what makes a retired token's *reuse* meaningful: a token that was rotated
and is presented again is a copy, because the legitimate client moved on. A
token revoked by signing out was not replaced, and reads differently.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "refresh_tokens",
        sa.Column(
            "replaced_by_id",
            UUID(as_uuid=True),
            # SET NULL rather than CASCADE: losing the successor must not delete
            # the record that a token was rotated, which is the audit trail.
            sa.ForeignKey("refresh_tokens.id", ondelete="SET NULL"),
        ),
    )


def downgrade() -> None:
    op.drop_column("refresh_tokens", "replaced_by_id")
