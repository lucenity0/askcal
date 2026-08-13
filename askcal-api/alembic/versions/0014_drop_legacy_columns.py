"""Drop the columns three migrations kept for the way back

Revision ID: 0014
Revises: 0013

0008, 0009 and 0010 each added a new shape beside an old one and backfilled,
so every step could deploy on its own and be rolled back. Those old columns
have had no reader since; this removes them.

This is the one irreversible step in that series. `downgrade` puts the columns
back but cannot put the data back — `emails.track` and `tracks.key` held an
enum that no longer exists anywhere in the code, `users.google_refresh_token`
held a secret that only Google can reissue. Restore from a dump instead.

`emails.account_email` goes too. It was worth keeping only as a record of which
address a message arrived at once its account row was gone — but `account_id`
cascades, so the mail is deleted with the mailbox and there is no state where
one outlives the other.
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects.postgresql import UUID

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Superseded by `emails.track_id` (0008).
    op.drop_column("emails", "track")

    # Superseded by `emails.account_id` (0009).
    op.drop_column("emails", "account_email")

    # Superseded by `tracks.slug` (0008). The unique constraint on
    # (user_id, key) goes with it automatically — Postgres drops constraints
    # involving a dropped column — which is better than naming it here, since
    # 0001 created it unnamed and the name is Postgres's own convention rather
    # than anything this repo chose.
    op.drop_column("tracks", "key")

    # Nothing references the enum type once both columns are gone. Postgres
    # refuses to drop a type still in use, so this doubles as the check that
    # the two drops above were complete.
    op.execute("DROP TYPE IF EXISTS track_key")

    # Superseded by the `mail_account_tracks` set (0010).
    op.drop_column("mail_accounts", "default_track_id")

    # Superseded by `mail_accounts` (0009).
    op.drop_column("users", "google_refresh_token")


def downgrade() -> None:
    """Puts the shape back, not the data.

    Every one of these is either an enum that no longer exists in code or a
    secret that cannot be regenerated locally. If this is ever needed, restore
    the dump taken before 0014 and replay forward — do not rely on this to
    recover anything.
    """
    op.add_column("users", sa.Column("google_refresh_token", sa.Text()))
    op.add_column(
        "mail_accounts",
        sa.Column(
            "default_track_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tracks.id", ondelete="SET NULL"),
        ),
    )
    track_key = sa.Enum(
        "career", "design", "uni", "feed", "finance", name="track_key"
    )
    track_key.create(op.get_bind(), checkfirst=True)
    op.add_column("tracks", sa.Column("key", track_key, nullable=True))
    op.create_unique_constraint("tracks_user_id_key_key", "tracks", ["user_id", "key"])
    op.add_column("emails", sa.Column("track", track_key))
    op.add_column("emails", sa.Column("account_email", sa.String(320)))
