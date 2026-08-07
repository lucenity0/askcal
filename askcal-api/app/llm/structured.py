"""Turning model text into validated pydantic objects, for any provider.

Gemini's response_schema guaranteed a well-formed list; the Claude Code CLI has
no constrained decoding at all. So the shape has to be enforced above the
transport, and every provider reads from the same schema.

Generic over the model class on purpose: this module never imports
app.services.classifier, so app/llm/ gains no edge back into app/services/.
"""

import json
import logging
import re
from typing import Any, TypeVar

from pydantic import BaseModel, ValidationError

logger = logging.getLogger("askcal.llm.structured")

T = TypeVar("T", bound=BaseModel)

_FENCE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


class StructuredOutputError(ValueError):
    """No usable JSON at all. str(err) is fed back to the model on retry."""


def schema_block(model: type[BaseModel], *, as_list: bool = True) -> str:
    """The schema, rendered for the system prompt.

    Generated from the model class rather than hand-written, so prompt and
    validator cannot drift — a field added to EmailSignals appears in the prompt
    on the next call with no edit anywhere else.
    """
    schema = json.dumps(model.model_json_schema(), indent=2)
    shape = "a JSON ARRAY of objects" if as_list else "a single JSON object"
    return (
        f"Return {shape} matching this JSON Schema EXACTLY, and nothing else — "
        f"no prose, no markdown fences, no explanation.\n\n{schema}"
    )


def extract_json(raw: str) -> Any:
    """Tolerant extraction: bare JSON, fenced JSON, or JSON embedded in prose.

    Askcal's answer is a top-level ARRAY, so unlike a single-object extractor
    this has to consider ``[...]`` as well as ``{...}`` and take whichever the
    model actually emitted. Candidates are tried cleanest-first, so a model that
    narrates ("Here are the results: [...]") still parses.
    """
    for candidate in _candidates(raw):
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    raise StructuredOutputError("No JSON array or object found in model output.")


def _candidates(raw: str) -> list[str]:
    out: list[str] = []
    stripped = raw.strip()
    if stripped:
        out.append(stripped)  # the common, clean case
    for m in _FENCE.finditer(raw):  # ```json ... ```
        if m.group(1).strip():
            out.append(m.group(1).strip())
    spans: list[tuple[int, str]] = []
    for open_c, close_c in (("[", "]"), ("{", "}")):
        start, end = raw.find(open_c), raw.rfind(close_c)
        if start != -1 and end > start:
            spans.append((start, raw[start : end + 1]))
    out.extend(text for _, text in sorted(spans))  # earliest-starting first
    return out


def as_item_list(data: Any, *, key_field: str) -> list[dict]:
    """Normalise whatever came back into a list of item dicts.

    Three shapes show up in practice and all three are cheap to accept: a bare
    array; a wrapper object ({"results": [...]}, {"emails": [...]}); and — when a
    batch happens to hold one email — a single bare object. Rejecting the last
    two would discard a correct answer over packaging.
    """
    if isinstance(data, list):
        return [d for d in data if isinstance(d, dict)]
    if isinstance(data, dict):
        if key_field in data:
            return [data]
        for value in data.values():
            if isinstance(value, list):
                return [d for d in value if isinstance(d, dict)]
    return []


def validate_items(
    items: list[dict],
    model: type[T],
    *,
    key_field: str,
    known_keys: set[str],
) -> tuple[dict[str, T], list[str]]:
    """Validate item by item. → (accepted by key, human-readable errors).

    Per-item, not whole-batch, because Gemini's response_schema guaranteed a
    well-formed list and the CLI does not: under whole-batch validation, one
    email whose ``confidence`` came back as the string "high" would discard the
    other nine correctly-classified emails in the call. Partial success is the
    difference between "9 classified, 1 retried" and "0 classified".

    Items whose key is not in ``known_keys`` are dropped — a model that invents
    a gmail_id must not be able to write signals onto an unrelated row.
    """
    accepted: dict[str, T] = {}
    errors: list[str] = []
    for item in items:
        key = str(item.get(key_field, ""))
        if key not in known_keys:
            errors.append(f"unknown {key_field} {key!r} — ignored")
            logger.warning("model returned unknown %s %s", key_field, key)
            continue
        try:
            accepted[key] = model.model_validate(item)
        except ValidationError as exc:
            errors.append(f"{key_field}={key}: {exc.errors(include_url=False)}")
    return accepted, errors
