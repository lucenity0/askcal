"""Encrypting the secrets that sit in the database.

A Google refresh token is a long-lived key to somebody's entire mailbox and
calendar. It was stored in plain text, so anyone who ever saw the database —
a dump, a backup, a stray `psql` — had that, and multi-account made it two
tokens per user rather than one.

The key lives in the environment, the same place the JWT secret and the Google
client secret already do. That is deliberate: adding a second secret store for
one of three secrets buys very little, and the whole thing is read through
`_fernet()` here, so moving it to Secret Manager later is a change to one
function rather than to every call site.

Values carry a version prefix so encrypted and plain rows can coexist. That is
what makes the rollout survivable: the column can be backfilled while the old
plaintext is still readable, and a value written by a newer scheme is
recognisable rather than silently mangled.
"""

import logging
from functools import lru_cache

from cryptography.fernet import Fernet, InvalidToken

from app.config import get_settings

logger = logging.getLogger("askcal.crypto")

__all__ = ["decrypt_secret", "encrypt_secret", "encryption_configured", "is_encrypted"]

PREFIX = "enc:v1:"


@lru_cache(maxsize=1)
def _fernet() -> Fernet | None:
    key = get_settings().token_encryption_key
    if not key:
        return None
    try:
        return Fernet(key.encode())
    except (ValueError, TypeError):
        # A malformed key must not read as "encryption is off". Silently
        # storing plaintext because someone fat-fingered an env var is the
        # exact failure this module exists to prevent.
        raise RuntimeError(
            "ASKCAL_TOKEN_ENCRYPTION_KEY is set but is not a valid Fernet key. "
            "Generate one with: python -c "
            "'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'"
        )


def encryption_configured() -> bool:
    return _fernet() is not None


def is_encrypted(value: str | None) -> bool:
    return bool(value) and value.startswith(PREFIX)


def encrypt_secret(value: str | None) -> str | None:
    """Encrypt, or pass through when no key is configured.

    Passing through is what lets the app run locally and in tests without
    ceremony. It is loud about it in production: `/health` reports whether
    encryption is on, because a deployment that quietly stopped encrypting
    would otherwise look identical to one that never started.
    """
    if value is None or value == "":
        return value
    if is_encrypted(value):
        return value
    fernet = _fernet()
    if fernet is None:
        return value
    return PREFIX + fernet.encrypt(value.encode()).decode()


def decrypt_secret(value: str | None) -> str | None:
    """Decrypt if it looks encrypted, otherwise hand back what was stored.

    Rows written before the backfill are still plaintext and must keep working,
    so an unprefixed value is returned as-is rather than treated as corrupt.
    """
    if not is_encrypted(value):
        return value
    fernet = _fernet()
    if fernet is None:
        # Encrypted data and no key. Returning the ciphertext would send it to
        # Google as a refresh token and produce a baffling auth error, so this
        # says what actually happened instead.
        logger.error("stored value is encrypted but no encryption key is configured")
        return None
    try:
        return fernet.decrypt(value[len(PREFIX):].encode()).decode()
    except InvalidToken:
        # Wrong key, or a truncated value. Either way the token is unusable —
        # the mailbox needs reconnecting, and saying so beats a decode crash on
        # every sync.
        logger.error("could not decrypt a stored secret — wrong key, or the value is damaged")
        return None
