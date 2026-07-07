"""Classifier helper tests — no Gemini network calls."""

import asyncio
import datetime as dt
from datetime import timezone

from app.services.classifier import (
    EmailSignals,
    classify_batch,
    parse_deadline,
    signals_track_key,
)
from app.models import TrackKey


def test_parse_deadline_iso_with_z():
    parsed = parse_deadline("2026-07-06T23:59:00Z")
    assert parsed == dt.datetime(2026, 7, 6, 23, 59, tzinfo=timezone.utc)


def test_parse_deadline_naive_assumed_utc():
    parsed = parse_deadline("2026-07-06T23:59:00")
    assert parsed.tzinfo == timezone.utc


def test_parse_deadline_garbage_and_none():
    assert parse_deadline("whenever bro") is None
    assert parse_deadline(None) is None


def test_signals_track_key_mapping():
    def sig(track):
        return EmailSignals(
            gmail_id="x", track=track, sender_type="other", consequence="none",
            action_required=False, confidence=0.9,
        )

    assert signals_track_key(sig("career")) == TrackKey.career
    assert signals_track_key(sig("none")) is None


def test_classify_batch_without_api_key_returns_empty(monkeypatch):
    monkeypatch.setenv("ASKCAL_GEMINI_API_KEY", "")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        result = asyncio.run(classify_batch([]))
        assert result == {}
    finally:
        get_settings.cache_clear()
