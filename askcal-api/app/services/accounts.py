"""Which mailbox answers which question.

With one Google account every call could read the same token and be right. With
several, "whose calendar?" and "which inbox do I mark this read in?" have
different answers, and getting them from one column would mean marking mail read
in the wrong mailbox.
"""

from app.models import Email, MailAccount, User

__all__ = ["calendar_token", "has_connected_mailbox", "token_for_email"]


def calendar_token(user: User) -> str | None:
    """The token for calendar and busy-block reads.

    The primary account's, because that is the one the user signed in with and
    the only one whose calendar Askcal was ever asked about.
    """
    for account in user.mail_accounts:
        if account.is_primary and account.google_refresh_token:
            return account.google_refresh_token
    return None


def has_connected_mailbox(user: User) -> bool:
    """Whether anything at all can be pulled.

    Any live mailbox counts. A user whose primary token was revoked but whose
    second inbox still works is connected — telling them otherwise would hide
    mail that is arriving perfectly well.
    """
    return any(a.google_refresh_token and a.active for a in user.mail_accounts)


def token_for_email(user: User, email: Email) -> str | None:
    """The token for acting on one message — marking it read, mostly.

    It has to be the mailbox the mail actually arrived at. Using the primary
    account's token for a message from a second inbox marks nothing read and
    fails silently, since the id simply does not exist over there.
    """
    account: MailAccount | None = getattr(email, "account", None)
    if account is not None and account.google_refresh_token:
        return account.google_refresh_token
    return calendar_token(user)
