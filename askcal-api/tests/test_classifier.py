"""Classifier tests — no network calls, no real LLM provider."""

import asyncio
import datetime as dt
import json
from datetime import timezone

from app.services.classifier import (
    EmailSignals,
    classify_batch,
    parse_deadline,
    signals_track_key,
)
from app.models import Email, TrackKey


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


def test_classify_batch_without_a_provider_returns_empty(monkeypatch):
    monkeypatch.setenv("ASKCAL_LLM_PROVIDER", "gemini")
    monkeypatch.setenv("ASKCAL_GEMINI_API_KEY", "")
    # Cleared explicitly: without this a developer with Vertex set in .env makes
    # this "no network" test attempt a real client construction.
    monkeypatch.setenv("ASKCAL_GEMINI_USE_VERTEX", "false")
    from app.config import get_settings

    get_settings.cache_clear()
    try:
        result = asyncio.run(classify_batch([]))
        assert result == {}
    finally:
        get_settings.cache_clear()


# ── classify_batch against a fake transport ───────────────────────────────


class _FakeProvider:
    """Satisfies LLMProvider; records the prompts it was handed."""

    model_name = "fake"
    batch_size = 10
    inter_batch_delay_seconds = 0.0

    def __init__(self, *responses: str):
        self._responses = list(responses)
        self.prompts: list[str] = []

    async def complete(self, system, user, *, response_schema=None):
        from app.llm.base import LLMResponse

        self.prompts.append(user)
        return LLMResponse(text=self._responses.pop(0), tokens_used=5)


def _email(gmail_id: str) -> Email:
    return Email(
        gmail_id=gmail_id,
        sender="prof@uni.edu",
        subject=f"subject {gmail_id}",
        snippet="body",
        body_text="body",
        received_at=dt.datetime(2026, 8, 8, 9, 0, tzinfo=timezone.utc),
    )


def _payload(gmail_id: str, **over) -> dict:
    base = {
        "gmail_id": gmail_id,
        "track": "uni",
        "sender_type": "professor",
        "consequence": "grade_loss",
        "action_required": True,
        "deadline_utc": "2026-08-20T23:59:00Z",
        "estimated_minutes": 60,
        "confidence": 0.9,
    }
    base.update(over)
    return base


def _use(monkeypatch, provider):
    from app.services import classifier

    monkeypatch.setattr(classifier, "provider_or_none", lambda: provider)


def test_classify_batch_happy_path(monkeypatch):
    provider = _FakeProvider(json.dumps([_payload("a"), _payload("b")]))
    _use(monkeypatch, provider)

    result = asyncio.run(classify_batch([_email("a"), _email("b")]))

    assert set(result) == {"a", "b"}
    assert result["a"].consequence == "grade_loss"
    assert len(provider.prompts) == 1


def test_classify_batch_retries_only_the_stragglers(monkeypatch):
    """The retry must not re-send work that already validated.

    Attempt 1 mangles one email out of three; attempt 2 should carry that one
    email and nothing else — cheaper, and it cannot lose the two good results.
    """
    first = json.dumps([_payload("a"), _payload("b", confidence="high"), _payload("c")])
    second = json.dumps([_payload("b")])
    provider = _FakeProvider(first, second)
    _use(monkeypatch, provider)

    result = asyncio.run(classify_batch([_email("a"), _email("b"), _email("c")]))

    assert set(result) == {"a", "b", "c"}
    assert len(provider.prompts) == 2
    retry = provider.prompts[1]
    assert "subject b" in retry
    assert "subject a" not in retry and "subject c" not in retry
    assert "could not be used" in retry


def test_classify_batch_keeps_partial_results_when_retries_run_out(monkeypatch):
    """Two of three is a better outcome than zero of three."""
    bad = json.dumps([_payload("a"), _payload("b", confidence="high"), _payload("c")])
    provider = _FakeProvider(bad, json.dumps([_payload("b", confidence="still bad")]))
    _use(monkeypatch, provider)

    result = asyncio.run(classify_batch([_email("a"), _email("b"), _email("c")]))

    assert set(result) == {"a", "c"}


def test_classify_batch_drops_hallucinated_ids(monkeypatch):
    provider = _FakeProvider(json.dumps([_payload("a"), _payload("never-sent")]))
    _use(monkeypatch, provider)

    result = asyncio.run(classify_batch([_email("a")]))

    assert set(result) == {"a"}


def test_classify_batch_survives_prose_around_the_answer(monkeypatch):
    provider = _FakeProvider(f"Sure! Here you go:\n```json\n{json.dumps([_payload('a')])}\n```")
    _use(monkeypatch, provider)

    assert set(asyncio.run(classify_batch([_email("a")]))) == {"a"}
