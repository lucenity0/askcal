"""Gmail OAuth 2.0 flow + email ingestion.

OAuth activates once ASKCAL_GOOGLE_CLIENT_ID / ASKCAL_GOOGLE_CLIENT_SECRET are
set. Ingestion follows the API-contract notes: batch-fetch up to 50 messages
per request via the Gmail batch endpoint, store raw payloads, classify async.
Attachments are never downloaded here — lazy, on demand, in a later phase.
"""

import base64
import email as email_stdlib
import json
import logging
import re
import secrets
from dataclasses import dataclass
from datetime import datetime, timezone
from urllib.parse import urlencode

import httpx
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app.config import get_settings
from app.core.errors import AskcalError

logger = logging.getLogger("askcal.gmail")

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GMAIL_API = "https://gmail.googleapis.com/gmail/v1"
GMAIL_BATCH_URL = "https://gmail.googleapis.com/batch/gmail/v1"

BODY_TEXT_MAX_CHARS = 20_000

GMAIL_SCOPES = [
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.modify",  # mark-as-read on triage
    # one consent flow covers mail + calendar — never two connect buttons
    # for the same provider. Existing users must re-consent to add this.
    "https://www.googleapis.com/auth/calendar.readonly",
]


@dataclass
class GoogleProfile:
    sub: str
    email: str
    name: str | None
    access_token: str
    refresh_token: str | None


@dataclass
class GmailMessage:
    """One parsed Gmail message, ready to upsert into the emails table."""

    gmail_id: str
    thread_id: str | None
    subject: str | None
    sender: str | None
    snippet: str | None
    body_text: str
    received_at: datetime
    raw: dict


def _require_credentials() -> None:
    s = get_settings()
    if not s.google_client_id or not s.google_client_secret:
        raise AskcalError(
            503,
            "GMAIL_NOT_CONFIGURED",
            "Google OAuth credentials missing — set ASKCAL_GOOGLE_CLIENT_ID and "
            "ASKCAL_GOOGLE_CLIENT_SECRET in .env",
        )


# ─── OAuth flow ───────────────────────────────────────────────────────────────


def authorization_url(state: str, redirect_uri: str | None = None) -> str:
    """URL the client sends the user to for the Google consent screen."""
    _require_credentials()
    s = get_settings()
    params = {
        "client_id": s.google_client_id,
        "redirect_uri": redirect_uri or s.google_redirect_uri,
        "response_type": "code",
        "scope": " ".join(GMAIL_SCOPES),
        "access_type": "offline",  # get a refresh token for background ingestion
        "prompt": "consent",
        "state": state,
    }
    return f"{GOOGLE_AUTH_URL}?{urlencode(params)}"


async def exchange_google_code(code: str, redirect_uri: str | None = None) -> GoogleProfile:
    """Exchange the OAuth authorization code for tokens + verified identity.
    redirect_uri must match the one used in the authorization request."""
    _require_credentials()
    s = get_settings()

    async with httpx.AsyncClient() as client:
        resp = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "code": code,
                "client_id": s.google_client_id,
                "client_secret": s.google_client_secret,
                "redirect_uri": redirect_uri or s.google_redirect_uri,
                "grant_type": "authorization_code",
            },
        )
    if resp.status_code != 200:
        raise AskcalError(401, "GMAIL_DISCONNECTED", "Google code exchange failed")
    data = resp.json()

    claims = google_id_token.verify_oauth2_token(
        data["id_token"], google_requests.Request(), s.google_client_id
    )
    return GoogleProfile(
        sub=claims["sub"],
        email=claims["email"],
        name=claims.get("name"),
        access_token=data["access_token"],
        refresh_token=data.get("refresh_token"),
    )


# Google access tokens live ~1h; refreshing on every request added a full
# Google round-trip (~0.5s) to every /api/today and /api/calendar call.
_access_token_cache: dict[str, tuple[str, float]] = {}


async def refresh_google_access_token(google_refresh_token: str) -> str:
    """Trade the stored Google refresh token for a short-lived access token.
    Cached in-process until ~1 min before expiry."""
    import time

    cached = _access_token_cache.get(google_refresh_token)
    if cached and cached[1] > time.time():
        return cached[0]

    _require_credentials()
    s = get_settings()
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            GOOGLE_TOKEN_URL,
            data={
                "refresh_token": google_refresh_token,
                "client_id": s.google_client_id,
                "client_secret": s.google_client_secret,
                "grant_type": "refresh_token",
            },
        )
    if resp.status_code != 200:
        # invalid_grant = user revoked access or token expired → reconnect
        _access_token_cache.pop(google_refresh_token, None)
        raise AskcalError(401, "GMAIL_DISCONNECTED", "Gmail auth expired")
    data = resp.json()
    token = data["access_token"]
    ttl = int(data.get("expires_in", 3600))
    _access_token_cache[google_refresh_token] = (token, time.time() + ttl - 60)
    return token


# ─── Message fetching ─────────────────────────────────────────────────────────


async def list_message_ids(access_token: str, query: str, max_results: int) -> list[str]:
    async with httpx.AsyncClient() as client:
        resp = await client.get(
            f"{GMAIL_API}/users/me/messages",
            params={"q": query, "maxResults": max_results},
            headers={"Authorization": f"Bearer {access_token}"},
        )
    if resp.status_code == 401:
        raise AskcalError(401, "GMAIL_DISCONNECTED", "Gmail auth expired")
    resp.raise_for_status()
    return [m["id"] for m in resp.json().get("messages", [])]


def _build_batch_body(message_ids: list[str], boundary: str) -> str:
    parts = []
    for i, mid in enumerate(message_ids):
        parts.append(
            f"--{boundary}\r\n"
            "Content-Type: application/http\r\n"
            f"Content-ID: <item{i}>\r\n"
            "\r\n"
            f"GET /gmail/v1/users/me/messages/{mid}?format=full\r\n"
            "\r\n"
        )
    parts.append(f"--{boundary}--\r\n")
    return "".join(parts)


def _parse_batch_response(content_type: str, body: bytes) -> list[dict]:
    """Parse a multipart/mixed batch response into message JSON dicts."""
    envelope = b"Content-Type: " + content_type.encode() + b"\r\n\r\n" + body
    parsed = email_stdlib.message_from_bytes(envelope)
    messages: list[dict] = []
    for part in parsed.get_payload():
        payload = part.get_payload(decode=True)
        if payload is None:
            payload_str = part.get_payload()
            payload = (
                payload_str.encode() if isinstance(payload_str, str) else b""
            )
        # payload = "HTTP/1.1 200 OK\r\n<headers>\r\n\r\n<json body>"
        head, _, json_body = payload.partition(b"\r\n\r\n")
        status_line = head.split(b"\r\n", 1)[0]
        if b"200" not in status_line:
            logger.warning("batch part failed: %s", status_line.decode(errors="replace"))
            continue
        try:
            messages.append(json.loads(json_body))
        except json.JSONDecodeError:
            logger.warning("batch part had unparseable JSON body")
    return messages


async def batch_fetch_messages(access_token: str, message_ids: list[str]) -> list[dict]:
    """Fetch full messages via the Gmail batch API — up to 50 per request."""
    results: list[dict] = []
    for start in range(0, len(message_ids), 50):
        chunk = message_ids[start : start + 50]
        boundary = f"askcal_batch_{secrets.token_hex(8)}"
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                GMAIL_BATCH_URL,
                content=_build_batch_body(chunk, boundary),
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Content-Type": f"multipart/mixed; boundary={boundary}",
                },
            )
        if resp.status_code == 401:
            raise AskcalError(401, "GMAIL_DISCONNECTED", "Gmail auth expired")
        resp.raise_for_status()
        results.extend(_parse_batch_response(resp.headers["content-type"], resp.content))
    return results


# ─── Message parsing ──────────────────────────────────────────────────────────


def _decode_b64url(data: str) -> str:
    padded = data + "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(padded).decode("utf-8", errors="replace")


def extract_body_text(payload: dict) -> str:
    """Walk MIME parts; prefer text/plain, fall back to tag-stripped text/html."""
    plain: list[str] = []
    html: list[str] = []
    stack = [payload]
    while stack:
        part = stack.pop()
        data = (part.get("body") or {}).get("data")
        if data:
            mime = part.get("mimeType", "")
            if mime == "text/plain":
                plain.append(_decode_b64url(data))
            elif mime == "text/html":
                html.append(_decode_b64url(data))
        stack.extend(part.get("parts") or [])
    if plain:
        text = "\n".join(plain)
    elif html:
        text = re.sub(r"<[^>]+>", " ", "\n".join(html))
        text = re.sub(r"\s{2,}", " ", text)
    else:
        text = ""
    return text.strip()[:BODY_TEXT_MAX_CHARS]


def parse_message(msg: dict) -> GmailMessage:
    payload = msg.get("payload") or {}
    headers = {h["name"].lower(): h["value"] for h in payload.get("headers", [])}
    received_ms = int(msg.get("internalDate", 0))
    return GmailMessage(
        gmail_id=msg["id"],
        thread_id=msg.get("threadId"),
        subject=headers.get("subject"),
        sender=headers.get("from"),
        snippet=msg.get("snippet"),
        body_text=extract_body_text(payload),
        received_at=datetime.fromtimestamp(received_ms / 1000, tz=timezone.utc),
        # Keep the raw envelope minus bulky part data — body_text already holds
        # the extracted text; full re-fetch by id is always possible.
        raw={k: v for k, v in msg.items() if k != "payload"},
    )


async def fetch_recent_messages(
    google_refresh_token: str, since: datetime | None = None
) -> list[GmailMessage]:
    """List + batch-fetch + parse recent inbox messages for one mailbox.

    `since` scopes the pull (Gmail `after:` takes epoch seconds) — the sync
    passes the user's local midnight so a re-check only touches today's mail.
    Without it, falls back to the configured lookback window.
    """
    s = get_settings()
    access_token = await refresh_google_access_token(google_refresh_token)
    if since is not None:
        query = f"after:{int(since.timestamp())} -in:spam -in:trash"
    else:
        query = f"newer_than:{s.gmail_lookback_days}d -in:spam -in:trash"
    ids = await list_message_ids(access_token, query, s.gmail_max_results)
    if not ids:
        return []
    raw_messages = await batch_fetch_messages(access_token, ids)
    return [parse_message(m) for m in raw_messages]


async def mark_as_read(google_refresh_token: str, gmail_id: str) -> None:
    """Best-effort UNREAD label removal (gmail.modify). Never raises."""
    try:
        access_token = await refresh_google_access_token(google_refresh_token)
        async with httpx.AsyncClient(timeout=15) as client:
            await client.post(
                f"{GMAIL_API}/users/me/messages/{gmail_id}/modify",
                json={"removeLabelIds": ["UNREAD"]},
                headers={"Authorization": f"Bearer {access_token}"},
            )
    except Exception:
        logger.warning("mark_as_read failed for %s", gmail_id, exc_info=True)
