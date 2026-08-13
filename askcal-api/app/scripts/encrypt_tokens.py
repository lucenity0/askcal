"""Encrypt the refresh tokens already sitting in plain text.

New writes are encrypted by the column type as soon as a key is configured.
Rows written before that are still plaintext, and stay readable — `EncryptedText`
hands back anything without the version prefix untouched — so nothing breaks
while they wait. This rewrites them.

Safe to run more than once: an already-encrypted value is skipped, not
double-wrapped.

    docker compose -f docker-compose.prod.yml -f docker-compose.subscription.yml \
        exec api uv run python -m app.scripts.encrypt_tokens
    ... check the counts ...
        exec api uv run python -m app.scripts.encrypt_tokens --apply
"""

import asyncio
import sys

from sqlalchemy import select
from sqlalchemy.orm.attributes import flag_modified

from app.core.crypto import encryption_configured, is_encrypted
from app.db import SessionLocal
from app.models import MailAccount, User


async def main(apply: bool) -> int:
    if not encryption_configured():
        print(
            "No encryption key configured. Set ASKCAL_TOKEN_ENCRYPTION_KEY and\n"
            "restart the API first, or this would rewrite the rows unchanged.\n\n"
            "Generate one with:\n"
            "  python -c 'from cryptography.fernet import Fernet; "
            "print(Fernet.generate_key().decode())'"
        )
        return 1

    plain = 0
    async with SessionLocal() as db:
        # Read the raw column, not the mapped attribute: the type decorator
        # would have already decrypted it, and then everything would look like
        # plaintext that needs rewriting.
        accounts = (
            await db.execute(
                select(MailAccount.id, MailAccount.email, MailAccount.__table__.c.google_refresh_token)
            )
        ).all()
        users = (
            await db.execute(
                select(User.id, User.email, User.__table__.c.google_refresh_token)
            )
        ).all()

        for label, rows in (("mailbox", accounts), ("user", users)):
            for _id, email, token in rows:
                if not token or is_encrypted(token):
                    continue
                plain += 1
                print(f"  {label}: {email}")

        if not plain:
            print("Every stored token is already encrypted.")
            return 0

        if not apply:
            print(
                f"\n{plain} token(s) still in plain text. Nothing changed — "
                "re-run with --apply."
            )
            return plain

        # Loaded through the ORM so the column type encrypts on the way back
        # down. Writing the ciphertext by hand here would mean two places that
        # know the format.
        #
        # `flag_modified` because the value does not change in Python — it is
        # already the decrypted string — so SQLAlchemy would see a clean
        # attribute and issue no UPDATE at all.
        for account in (await db.scalars(select(MailAccount))).all():
            if account.google_refresh_token:
                flag_modified(account, "google_refresh_token")
        for user in (await db.scalars(select(User))).all():
            if user.google_refresh_token:
                flag_modified(user, "google_refresh_token")
        await db.commit()
        print(f"\nEncrypted {plain} token(s).")
    return plain


if __name__ == "__main__":
    asyncio.run(main("--apply" in sys.argv))
