"""Gmail payload + batch-response parsing tests (no network)."""

import base64
import json

from app.services.gmail import (
    _build_batch_body,
    _parse_batch_response,
    extract_body_text,
    parse_message,
)


def b64url(text: str) -> str:
    return base64.urlsafe_b64encode(text.encode()).decode().rstrip("=")


def test_extract_prefers_text_plain():
    payload = {
        "mimeType": "multipart/alternative",
        "parts": [
            {"mimeType": "text/plain", "body": {"data": b64url("plain body")}},
            {"mimeType": "text/html", "body": {"data": b64url("<p>html body</p>")}},
        ],
    }
    assert extract_body_text(payload) == "plain body"


def test_extract_falls_back_to_stripped_html():
    payload = {
        "mimeType": "text/html",
        "body": {"data": b64url("<div><b>Your OA link</b> is <a href='#'>here</a></div>")},
    }
    text = extract_body_text(payload)
    assert "Your OA link" in text and "<" not in text


def test_extract_handles_nested_parts_and_missing_data():
    payload = {
        "mimeType": "multipart/mixed",
        "parts": [
            {"mimeType": "multipart/alternative", "parts": [
                {"mimeType": "text/plain", "body": {"data": b64url("nested text")}},
            ]},
            {"mimeType": "application/pdf", "body": {"attachmentId": "abc"}},
        ],
    }
    assert extract_body_text(payload) == "nested text"


def test_parse_message_extracts_headers_and_time():
    msg = {
        "id": "18f2a",
        "threadId": "t1",
        "snippet": "Your online assessment...",
        "internalDate": "1751629710000",
        "payload": {
            "headers": [
                {"name": "Subject", "value": "OA Link"},
                {"name": "From", "value": "noreply@amazon.com"},
            ],
            "mimeType": "text/plain",
            "body": {"data": b64url("body here")},
        },
    }
    parsed = parse_message(msg)
    assert parsed.gmail_id == "18f2a"
    assert parsed.subject == "OA Link"
    assert parsed.sender == "noreply@amazon.com"
    assert parsed.body_text == "body here"
    assert parsed.received_at.year == 2025
    assert "payload" not in parsed.raw  # bulky MIME tree not duplicated in raw


def test_batch_body_contains_all_ids():
    body = _build_batch_body(["a1", "b2"], boundary="XYZ")
    assert body.count("--XYZ") == 3  # two parts + terminator
    assert "/gmail/v1/users/me/messages/a1?format=full" in body
    assert "/gmail/v1/users/me/messages/b2?format=full" in body


def _batch_part(boundary: str, status: str, payload: dict | None) -> str:
    body = json.dumps(payload) if payload is not None else "{}"
    return (
        f"--{boundary}\r\n"
        "Content-Type: application/http\r\n"
        "\r\n"
        f"HTTP/1.1 {status}\r\n"
        "Content-Type: application/json; charset=UTF-8\r\n"
        "\r\n"
        f"{body}\r\n"
    )


def test_parse_batch_response_happy_and_failed_parts():
    boundary = "batch_abc"
    raw = (
        _batch_part(boundary, "200 OK", {"id": "m1", "snippet": "hi"})
        + _batch_part(boundary, "404 Not Found", {"error": {"code": 404}})
        + _batch_part(boundary, "200 OK", {"id": "m2", "snippet": "yo"})
        + f"--{boundary}--\r\n"
    )
    messages = _parse_batch_response(
        f"multipart/mixed; boundary={boundary}", raw.encode()
    )
    assert [m["id"] for m in messages] == ["m1", "m2"]
