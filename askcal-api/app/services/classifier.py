"""Email classification: signals in, EmailSignals out.

One LLM call classifies a BATCH of emails. The model extracts structured
signals only — the regret score itself comes from the deterministic formula in
regret.py, so scores stay reproducible and tunable.

The transport is pluggable (see app/llm/): Claude Code drives the local CLI
against a Claude subscription, Gemini uses an API key or Vertex. Everything
Askcal-specific stays here — the prompt, the schema, reconciliation by gmail_id,
the retry policy — so a new provider can never fork the classifier's judgment.

If no provider is configured, classification is skipped entirely and emails stay
unranked until a later sync.
"""

import json
import logging
from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.config import get_settings
from app.llm.registry import classifier_configured, provider_or_none
from app.llm.structured import (
    StructuredOutputError,
    as_item_list,
    extract_json,
    schema_block,
    validate_items,
)
from app.models import Email, Track, TrackKey
from app.services.scheduling import user_now

logger = logging.getLogger("askcal.classifier")

__all__ = [
    "EmailSignals",
    "classifier_configured",
    "classify_batch",
    "classify_pacing",
    "parse_deadline",
    "signals_track_key",
    "system_prompt",
]

SenderType = Literal[
    "client", "recruiter", "professor", "automated_system", "peer", "newsletter", "other"
]
Consequence = Literal[
    "opportunity_loss", "grade_loss", "client_trust", "money_loss", "social", "none"
]


class EmailSignals(BaseModel):
    """Structured signals the model extracts per email. Stored as JSONB on the
    email row — audit trail now, training labels for the ML model later."""

    gmail_id: str
    # A track slug, or "none". Deliberately not a Literal: the structured-output
    # schema is generated from this model, and a compile-time set cannot express
    # a list of tracks that differs per user. The answer is checked against the
    # user's own tracks after parsing instead, where an unknown value degrades
    # to no track rather than failing the whole batch.
    track: str
    sender_type: SenderType
    consequence: Consequence
    action_required: bool
    # ISO 8601 string (model output is more reliable as a string field)
    deadline_utc: str | None = None
    # NOTE: no ge=0 here — Gemini's structured-output schema translator 500s
    # on "optional int with a numeric constraint" (anyOf + minimum). Clamp
    # non-negative via validator instead, which runs client-side only.
    estimated_minutes: int | None = None
    confidence: float = Field(ge=0.0, le=1.0)

    @field_validator("estimated_minutes")
    @classmethod
    def _non_negative_minutes(cls, v: int | None) -> int | None:
        return None if v is None else max(v, 0)


# The rules half. Provider-independent and stable across calls — deliberately
# free of the current date, which used to live in the deadline bullet: a system
# prompt that changes daily is fine for the CLI's --system-prompt but destroys
# prompt caching for any SDK-based provider, and it is the wrong layer besides.
_RULES_HEAD = """\
You are the email classifier for Askcal, a daily scheduler.

Classify each email below into signals. Use exactly one of these track names,
or "none". The description after each name is the user's own words for what
belongs there — follow it over any assumption about what the name usually means.

{tracks}

Rules:"""

_RULES_TAIL = """\
- action_required = TRUE only when the user must personally DO a concrete task
  with a real consequence. TRUE examples: an assignment or report due,
  "complete your online assessment", an interview slot to confirm, an
  invoice/fees payable, a client requesting a revision, a professor requesting
  a submission. FALSE examples: job-board digests/alerts that list openings
  ("50 new jobs for you"), social notifications ("X wants to connect",
  "someone viewed your profile", "add X"), newsletters and product marketing,
  order/payment receipts and confirmations, and "discover"/"check out"/"your
  points" nudges.
- A no-reply or automated sender does NOT lower action_required — an LMS
  assignment, an ATS assessment link, or a bank due-date is a real task even
  though it arrives from a system address.
- Completed money movement is a notification, not a task: money debited or
  credited, a payment "successful", receipts, and account/balance/statement
  updates are action_required=FALSE — they report what happened. A bill,
  invoice, fee, or EMI that is DUE — an unpaid amount to actively pay — is
  action_required=TRUE. (A failed/declined payment may also be TRUE when it
  implies the user must retry or update a payment method.)
- A DIGEST or ALERT that merely lists opportunities ("50 new jobs for you") is
  reading material: action_required=FALSE, and it belongs in whichever track
  covers things worth reading. Only a specific opportunity addressed to the user
  — an OA or interview invite, a recruiter writing to them directly — is real
  work. (Track names are the user's, so match on the descriptions above rather
  than on any name you expect to see.)
- sender_type: use `newsletter` for bulk/marketing mail and `automated_system`
  for platform/no-reply notifications; reserve `client`/`recruiter`/`professor`
  for a real person writing to the user.
- consequence = what the user loses by IGNORING the email, not how urgent it feels
- deadline_utc: only when the email states or clearly implies a date something
  is DUE. Resolve it in the user's LOCAL timezone (given below), then express
  the result in UTC as ISO 8601. Never emit a deadline earlier than that
  email's received_at.
  A stated START is not a deadline. "begins next week", "available from Monday",
  "you can start once X" -> deadline_utc is null unless a separate due date is
  also given.
  Vague wording resolves in LOCAL time as:
    "by morning" / "first thing"        -> 09:00 on the NEXT local day
    "EOD" / "end of day" / "by close"   -> 17:00 that local day, i.e. close of
                                           business, NOT midnight
    "by tonight" / "today"              -> 21:00 that local day
    "end of the week"                   -> Friday 17:00 of the CURRENT local week
    "end of the month"                  -> the LAST day of the CURRENT local
                                           month at 17:00
    "ASAP" / "urgent" with no date      -> null; urgency is consequence, not a
                                           deadline
- `arrived_at`, when present, is which of the user's mailboxes the email landed
  in, and `mailbox_usually` lists the tracks that mailbox normally carries.
  Treat it as a leaning, not a rule — a bill arriving at a college address is
  still about money, and a personal note to a work address is still personal.
  Use it to choose between tracks the email could plausibly belong to, never to
  override what it plainly says. An email may well belong to a track that is not
  on that list.
- estimated_minutes: rough effort to fully handle the email's ask, null if no ask
- confidence: how sure you are about the track + consequence overall
- Return one result object per input email, echoing its gmail_id exactly.
"""


def system_prompt(tracks: list[Track] | None = None) -> str:
    """The system prompt for one user's tracks.

    Still free of the current date, so it stays identical call after call for a
    given user and prompt caching keeps working — it changes only when they
    actually edit a track.

    With no tracks supplied it falls back to the built-in set, which keeps the
    classifier callable from tests and from any path that has no user in hand.
    """
    from app.services.tracks import BUILTIN_TRACKS, track_rules_block

    if tracks:
        rules = track_rules_block(tracks)
    else:
        rules = "\n".join(
            f"- {spec['slug']}: {spec['description']}" for spec in BUILTIN_TRACKS
        ) + "\n- none: everything else (spam, paid receipts, promotions, notifications)"

    # Schema rendered from the model itself, so prompt and validator cannot drift.
    return (
        _RULES_HEAD.format(tracks=rules)
        + "\n"
        + _RULES_TAIL
        + "\n"
        + schema_block(EmailSignals, as_list=True)
    )

USER_TEMPLATE = """\
Right now it is {now_local} in the user's timezone, {timezone}.
Resolve every relative date against that, not against UTC — "by morning" means
morning where they are, which can be a different calendar day in UTC.

Emails:
{emails_json}
"""

RETRY_SUFFIX = """

Your previous answer could not be used. Fix these problems and return ONLY the
corrected JSON array, one object per email listed above:
{errors}
"""

EXCERPT_CHARS = 1500


def _email_payload(e: Email) -> dict:
    body = (e.body_text or e.snippet or "")[:EXCERPT_CHARS]
    payload = {
        "gmail_id": e.gmail_id,
        "from": e.sender,
        "subject": e.subject,
        "received_at": e.received_at.isoformat(),
        "body_excerpt": body,
    }
    # Which of the user's mailboxes it landed in, and what that mailbox usually
    # carries. With one account this said nothing; with a college address and a
    # personal one it is often the strongest signal in the whole message.
    account = getattr(e, "account", None)
    if account is not None:
        payload["arrived_at"] = account.label or account.email
        if account.tracks:
            # Plural: no address is one thing. A college account carries
            # coursework, fees and the odd recruiter, and naming only the
            # closest one would push the other two into it.
            payload["mailbox_usually"] = [t.slug for t in account.tracks]
    return payload


def _build_user_prompt(emails: list[Email], tz_name: str = "UTC") -> str:
    """The prompt, anchored to the user's own clock.

    It used to say only "Today is <UTC date>", which is why "by morning" came
    back nineteen hours out: the model was resolving a local phrase against a
    calendar day that had already rolled over somewhere else.
    """
    return USER_TEMPLATE.format(
        now_local=user_now(tz_name).strftime("%Y-%m-%d %H:%M (%A)"),
        timezone=tz_name,
        emails_json=json.dumps([_email_payload(e) for e in emails], indent=2),
    )


def parse_deadline(value: str | None) -> datetime | None:
    """Lenient ISO parse; naive values are assumed UTC.

    Deliberately does no plausibility checking. A deadline earlier than the mail
    that mentions it is perfectly ordinary — you get told about things that are
    already late — so rejecting those here would throw away exactly the work
    that most needs surfacing. `sanitize_deadline` in autotask.py owns the
    plausibility window.
    """
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def signals_track_key(signals: EmailSignals) -> TrackKey | None:
    """The old enum answer, for the columns that still hold one.

    Only meaningful for the five built-in slugs; a track the user invented has
    no enum member and resolves to None. Use `track_by_slug` against the user's
    own tracks for anything that matters.
    """
    try:
        return TrackKey(signals.track)
    except ValueError:
        return None


def classify_pacing() -> tuple[int, float]:
    """(emails per call, seconds between calls) for the active provider.

    An explicitly-set ASKCAL_CLASSIFY_BATCH_SIZE / _DELAY_SECONDS always wins:
    model_fields_set holds only fields that actually came from the environment
    or .env, so a deployment that tuned these keeps its tuning across a provider
    change, while an untouched install gets the provider's own economics.
    """
    s = get_settings()
    provider = provider_or_none()
    size = (
        s.classify_batch_size
        if "classify_batch_size" in s.model_fields_set or provider is None
        else provider.batch_size
    )
    delay = (
        s.classify_delay_seconds
        if "classify_delay_seconds" in s.model_fields_set or provider is None
        else provider.inter_batch_delay_seconds
    )
    return size, delay


async def classify_batch(
    emails: list[Email],
    tz_name: str = "UTC",
    tracks: list[Track] | None = None,
) -> dict[str, EmailSignals]:
    """One LLM call (plus up to classify_max_retries follow-ups) for a batch.

    Returns signals keyed by gmail_id. Emails missing from the response stay
    unclassified and get retried on the next sync pass.

    `tracks` are the user's own; without them the built-in five are described
    instead, so this stays callable from tests and from any path with no user.
    """
    if not emails:
        return {}
    provider = provider_or_none()
    if provider is None:
        return {}

    system = system_prompt(tracks)
    retries = get_settings().classify_max_retries
    out: dict[str, EmailSignals] = {}
    pending = list(emails)
    tokens: int | None = 0
    errors: list[str] = []

    for attempt in range(retries + 1):
        user = _build_user_prompt(pending, tz_name)
        if attempt:
            user += RETRY_SUFFIX.format(errors="\n".join(f"- {e}" for e in errors))

        response = await provider.complete(
            system, user, response_schema=list[EmailSignals]
        )
        # A single unknown poisons the sum to unknown — a partial total would
        # read as a real number and quietly understate usage.
        tokens = (
            None
            if tokens is None or response.tokens_used is None
            else tokens + response.tokens_used
        )

        try:
            items = as_item_list(extract_json(response.text), key_field="gmail_id")
        except StructuredOutputError as exc:
            errors = [str(exc)]
            continue

        accepted, errors = validate_items(
            items,
            EmailSignals,
            key_field="gmail_id",
            known_keys={e.gmail_id for e in pending},
        )
        out.update(accepted)
        # Retry only the stragglers: the follow-up prompt is smaller than the
        # original, already-accepted work is never put at risk, and the second
        # call is cheap in exactly the currency the default provider is metered in.
        pending = [e for e in pending if e.gmail_id not in out]
        if not pending:
            break

    if pending:
        logger.warning(
            "%s omitted or mangled %d/%d email(s) after %d attempt(s); will retry next sync",
            provider.model_name,
            len(pending),
            len(emails),
            retries + 1,
        )
    logger.info(
        "classified %d/%d via %s (%s tokens)",
        len(out),
        len(emails),
        provider.model_name,
        tokens if tokens is not None else "unknown",
    )
    return out
