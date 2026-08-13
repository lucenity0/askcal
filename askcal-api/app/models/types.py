"""Column types that carry their own handling.

`EncryptedText` keeps the encryption at the column rather than at the call
sites. Every place that touches a refresh token — the OAuth callback, the sync
loop, the calendar fetch, a script — would otherwise have to remember to
encrypt on the way in and decrypt on the way out, and the one that forgot would
write plaintext into a column everything else assumed was safe.
"""

from sqlalchemy import Text
from sqlalchemy.types import TypeDecorator

from app.core.crypto import decrypt_secret, encrypt_secret


class EncryptedText(TypeDecorator):
    """Text that is encrypted in the database and plain in Python.

    `cache_ok` is True because the type has no per-instance configuration — the
    key comes from settings, not from the column — so SQLAlchemy may safely
    reuse compiled statements built with it.
    """

    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        return encrypt_secret(value)

    def process_result_value(self, value, dialect):
        return decrypt_secret(value)
