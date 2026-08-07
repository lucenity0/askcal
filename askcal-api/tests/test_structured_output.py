"""Structured-output layer — pure, provider-free.

These cover the shapes a model actually returns when nothing constrains its
decoding, which is the situation the Claude Code provider is always in.
"""

import json

import pytest

from app.llm.structured import (
    StructuredOutputError,
    as_item_list,
    extract_json,
    schema_block,
    validate_items,
)
from app.services.classifier import EmailSignals


def _sig(gmail_id: str, **over) -> dict:
    base = {
        "gmail_id": gmail_id,
        "track": "uni",
        "sender_type": "professor",
        "consequence": "grade_loss",
        "action_required": True,
        "deadline_utc": "2026-08-20T23:59:00Z",
        "estimated_minutes": 90,
        "confidence": 0.9,
    }
    base.update(over)
    return base


# ── extraction ────────────────────────────────────────────────────────────


def test_extracts_a_bare_array():
    assert extract_json('[{"gmail_id": "a"}]') == [{"gmail_id": "a"}]


def test_extracts_a_fenced_array():
    raw = '```json\n[{"gmail_id": "a"}]\n```'
    assert extract_json(raw) == [{"gmail_id": "a"}]


def test_extracts_an_array_embedded_in_prose():
    """The model narrating around its answer must not cost us the answer."""
    raw = 'Here are the results:\n[{"gmail_id": "a"}]\nHope that helps!'
    assert extract_json(raw) == [{"gmail_id": "a"}]


def test_extracts_a_bare_object():
    assert extract_json('{"gmail_id": "a"}') == {"gmail_id": "a"}


def test_no_json_at_all_raises():
    with pytest.raises(StructuredOutputError):
        extract_json("I'm sorry, I can't help with that.")


# ── normalisation ─────────────────────────────────────────────────────────


def test_as_item_list_accepts_a_bare_array():
    assert as_item_list([{"gmail_id": "a"}], key_field="gmail_id") == [{"gmail_id": "a"}]


@pytest.mark.parametrize("wrapper", ["results", "emails", "classifications"])
def test_as_item_list_unwraps_a_wrapper_object(wrapper):
    data = {wrapper: [{"gmail_id": "a"}]}
    assert as_item_list(data, key_field="gmail_id") == [{"gmail_id": "a"}]


def test_as_item_list_accepts_a_single_bare_object():
    """A batch of one invites the model to skip the array."""
    assert as_item_list({"gmail_id": "a"}, key_field="gmail_id") == [{"gmail_id": "a"}]


def test_as_item_list_rejects_nonsense():
    assert as_item_list(42, key_field="gmail_id") == []


# ── validation ────────────────────────────────────────────────────────────


def test_validate_items_happy_path():
    items = [_sig("a"), _sig("b")]
    accepted, errors = validate_items(
        items, EmailSignals, key_field="gmail_id", known_keys={"a", "b"}
    )
    assert set(accepted) == {"a", "b"}
    assert errors == []
    assert accepted["a"].consequence == "grade_loss"


def test_one_bad_item_does_not_discard_the_batch():
    """The whole reason validation is per-item rather than per-batch.

    Under whole-batch validation this single bad `confidence` would throw away
    nine correctly-classified emails and re-send them all next sync.
    """
    items = [_sig(f"e{i}") for i in range(10)]
    items[4]["confidence"] = "high"  # not a float

    accepted, errors = validate_items(
        items,
        EmailSignals,
        key_field="gmail_id",
        known_keys={f"e{i}" for i in range(10)},
    )

    assert len(accepted) == 9
    assert "e4" not in accepted
    assert len(errors) == 1
    assert "e4" in errors[0]


def test_unknown_gmail_id_is_dropped_and_known_ones_kept():
    """A model that invents an id must not write signals onto an unrelated row."""
    items = [_sig("real"), _sig("hallucinated")]
    accepted, errors = validate_items(
        items, EmailSignals, key_field="gmail_id", known_keys={"real"}
    )
    assert set(accepted) == {"real"}
    assert len(errors) == 1
    assert "hallucinated" in errors[0]


def test_estimated_minutes_is_clamped_non_negative():
    accepted, _ = validate_items(
        [_sig("a", estimated_minutes=-30)],
        EmailSignals,
        key_field="gmail_id",
        known_keys={"a"},
    )
    assert accepted["a"].estimated_minutes == 0


# ── schema rendering ──────────────────────────────────────────────────────


def test_schema_block_is_generated_from_the_model():
    """Drift guard: the prompt's schema and the validator share one source."""
    block = schema_block(EmailSignals, as_list=True)
    assert "JSON ARRAY" in block
    for field in ("gmail_id", "track", "sender_type", "consequence", "confidence"):
        assert field in block
    # It must contain real, parseable schema — not a prose description of one.
    start = block.index("{")
    json.loads(block[start:])
