"""A mailbox carries more than one kind of mail

Revision ID: 0010
Revises: 0009

`default_track_id` let an account say it was usually one thing. No address is
one thing — a college account carries coursework, fees and the odd recruiter,
and picking the single closest option is the same mistake the five hardcoded
tracks made.

Also gives a mailbox a name of its own. "college" is what the user calls that
address; the address itself is not something they need read back to them.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("mail_accounts", sa.Column("label", sa.String(80)))

    op.create_table(
        "mail_account_tracks",
        sa.Column(
            "account_id",
            UUID(as_uuid=True),
            sa.ForeignKey("mail_accounts.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "track_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tracks.id", ondelete="CASCADE"),
            primary_key=True,
        ),
    )

    # Whatever single track each account was set to becomes its first one.
    op.execute(
        """
        INSERT INTO mail_account_tracks (account_id, track_id)
        SELECT id, default_track_id
          FROM mail_accounts
         WHERE default_track_id IS NOT NULL
        """
    )

    # `default_track_id` stays for one release, same as every other column this
    # migration series has replaced.


def downgrade() -> None:
    op.drop_table("mail_account_tracks")
    op.drop_column("mail_accounts", "label")
