"""More than one mailbox

Revision ID: 0009
Revises: 0008

`users.google_refresh_token` held exactly one Google account, so college mail
and personal mail could not both reach Askcal — and the two want completely
different treatment, which is most of why tracks had to land first.

Same shape as 0008: the new table is filled from the old column, the old column
keeps its value and is still written, and nothing is dropped here. A rollback
that cannot recover its own data is not a rollback.
"""

import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID

from alembic import op

revision = "0009"
down_revision = "0008"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "mail_accounts",
        sa.Column("id", UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("email", sa.String(320), nullable=False),
        sa.Column("google_sub", sa.String(64)),
        # Nullable: an account row exists so mail has something to belong to
        # even before, or after, it can actually be read.
        sa.Column("google_refresh_token", sa.Text()),
        # What mail at this address usually is. The missing link between an
        # inbox and a track — "college mail is college work, personal mail
        # usually isn't" is a statement about tracks, which is why this could
        # not be built before they were the user's to name.
        sa.Column(
            "default_track_id",
            UUID(as_uuid=True),
            sa.ForeignKey("tracks.id", ondelete="SET NULL"),
        ),
        # The account that owns the calendar and the sign-in. Exactly one per
        # user; the others are mailboxes only.
        sa.Column("is_primary", sa.Boolean(), nullable=False, server_default=sa.false()),
        # Pause an inbox without unlinking it — the difference between "not
        # this term" and "forget this address".
        sa.Column("active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("last_synced_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.UniqueConstraint("user_id", "email", name="uq_mail_accounts_user_email"),
    )

    # Every existing user becomes their own primary account, token and all.
    op.execute(
        """
        INSERT INTO mail_accounts
            (id, user_id, email, google_sub, google_refresh_token, is_primary, active,
             last_synced_at, created_at, updated_at)
        SELECT gen_random_uuid(), u.id, u.email, u.google_sub, u.google_refresh_token,
               true, true, u.last_synced_at, now(), now()
          FROM users u
        """
    )

    op.add_column(
        "emails",
        sa.Column(
            "account_id",
            UUID(as_uuid=True),
            sa.ForeignKey("mail_accounts.id", ondelete="CASCADE"),
            nullable=True,
        ),
    )
    op.create_index("ix_emails_account_id", "emails", ["account_id"])

    # All existing mail arrived at the one account they had.
    op.execute(
        """
        UPDATE emails e
           SET account_id = a.id
          FROM mail_accounts a
         WHERE a.user_id = e.user_id
           AND a.is_primary
        """
    )

    # One primary per user, enforced rather than assumed — "which account owns
    # the calendar" has to have exactly one answer.
    op.create_index(
        "uq_mail_accounts_one_primary",
        "mail_accounts",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("is_primary"),
    )


def downgrade() -> None:
    op.drop_index("ix_emails_account_id", table_name="emails")
    op.drop_column("emails", "account_id")
    op.drop_index("uq_mail_accounts_one_primary", table_name="mail_accounts")
    op.drop_table("mail_accounts")
