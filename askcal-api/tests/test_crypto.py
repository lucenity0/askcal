"""Encrypting the secrets that sit in the database.

A Google refresh token is a long-lived key to a whole mailbox and calendar, and
it was stored in plain text. These pin the parts that decide whether the
rollout is survivable: plaintext rows keep working until they are backfilled,
and a failure to decrypt says so rather than handing back something unusable.
"""

import pytest
from cryptography.fernet import Fernet

from app.config import get_settings
from app.core import crypto


@pytest.fixture
def key(monkeypatch):
    monkeypatch.setenv("ASKCAL_TOKEN_ENCRYPTION_KEY", Fernet.generate_key().decode())
    get_settings.cache_clear()
    crypto._fernet.cache_clear()
    yield
    get_settings.cache_clear()
    crypto._fernet.cache_clear()


@pytest.fixture
def no_key(monkeypatch):
    monkeypatch.setenv("ASKCAL_TOKEN_ENCRYPTION_KEY", "")
    get_settings.cache_clear()
    crypto._fernet.cache_clear()
    yield
    get_settings.cache_clear()
    crypto._fernet.cache_clear()


def test_a_secret_survives_the_round_trip(key):
    assert crypto.decrypt_secret(crypto.encrypt_secret("1//refresh-token")) == "1//refresh-token"


def test_the_stored_form_does_not_contain_the_secret(key):
    stored = crypto.encrypt_secret("1//refresh-token")
    assert "1//refresh-token" not in stored
    assert stored.startswith(crypto.PREFIX)


def test_encrypting_twice_does_not_double_wrap(key):
    """The backfill is safe to re-run, and re-saving a row does not re-encrypt
    a value the column type already handled."""
    once = crypto.encrypt_secret("token")
    assert crypto.encrypt_secret(once) == once


# ── the rollout ───────────────────────────────────────────────────────────


def test_plaintext_written_before_the_key_still_reads(key):
    """Rows predate the key. They have to keep working until the backfill runs,
    or turning encryption on takes every connected mailbox offline."""
    assert crypto.decrypt_secret("1//old-plaintext-token") == "1//old-plaintext-token"


def test_without_a_key_values_pass_through(no_key):
    assert crypto.encrypt_secret("token") == "token"
    assert crypto.decrypt_secret("token") == "token"
    assert not crypto.encryption_configured()


def test_encrypted_data_with_no_key_is_not_handed_back_as_ciphertext(no_key):
    """Returning the stored string would send ciphertext to Google as a refresh
    token and produce an auth error nobody could trace back to here."""
    assert crypto.decrypt_secret(crypto.PREFIX + "gAAAAA-nonsense") is None


def test_the_wrong_key_fails_closed(key, monkeypatch):
    stored = crypto.encrypt_secret("token")
    monkeypatch.setenv("ASKCAL_TOKEN_ENCRYPTION_KEY", Fernet.generate_key().decode())
    get_settings.cache_clear()
    crypto._fernet.cache_clear()
    assert crypto.decrypt_secret(stored) is None


def test_a_malformed_key_raises_rather_than_silently_storing_plaintext(monkeypatch):
    """The failure this module exists to prevent is writing secrets in the
    clear, so a fat-fingered env var must not read as "encryption is off"."""
    monkeypatch.setenv("ASKCAL_TOKEN_ENCRYPTION_KEY", "not-a-fernet-key")
    get_settings.cache_clear()
    crypto._fernet.cache_clear()
    try:
        with pytest.raises(RuntimeError):
            crypto.encrypt_secret("token")
    finally:
        get_settings.cache_clear()
        crypto._fernet.cache_clear()


@pytest.mark.parametrize("empty", [None, ""])
def test_nothing_is_not_encrypted(key, empty):
    assert crypto.encrypt_secret(empty) == empty
    assert crypto.decrypt_secret(empty) == empty
