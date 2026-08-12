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
from app.models import Email, TrackKey
from app.services.scheduling import user_now

logger = logging.getLogger("askcal.classifier")

__all__ = [
    "EmailSignals",
    "classifier_configured",
    "classify_batch",
    "classify_pacing",
    "parse_deadline",
    "signals_track_key",
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
    track: Literal["career", "design", "uni", "feed", "finance", "none"]
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
_RULES = """\
You are the email classifier for Askcal, a daily scheduler for a student
freelancer who is simultaneously: a university student, a freelance designer,
and a job/placement candidate.

Classify each email below into signals. Track meanings:
- career: job applications, online assessments (OA), interviews, recruiters, placements
- design: freelance client work, briefs, deliverables, client communication
- uni: coursework, exams, assignments, professor/university emails
- feed: newsletters/content worth reading but with no obligation
- finance: invoices, payments due, banking alerts, fees — money matters that
  are important only when urgent (a payment reminder yes, a paid receipt no)
- none: everything else (spam, paid receipts, promotions, notifications)

Rules:
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
- A job-board DIGEST or ALERT that lists openings is `feed`, not `career`. Only
  a specific opportunity addressed to the user (an OA/interview invite, a
  recruiter contacting them directly) is `career` with action_required.
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
- estimated_minutes: rough effort to fully handle the email's ask, null if no ask
- confidence: how sure you are about the track + consequence overall
- Return one result object per input email, echoing its gmail_id exactly.
"""

# Schema rendered from the model itself, so prompt and validator cannot drift.
SYSTEM_PROMPT = _RULES + "\n" + schema_block(EmailSignals, as_list=True)

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
    return {
        "gmail_id": e.gmail_id,
        "from": e.sender,
        "subject": e.subject,
        "received_at": e.received_at.isoformat(),
        "body_excerpt": body,
    }


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
    return None if signals.track == "none" else TrackKey(signals.track)


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
    emails: list[Email], tz_name: str = "UTC"
) -> dict[str, EmailSignals]:
    """One LLM call (plus up to classify_max_retries follow-ups) for a batch.

    Returns signals keyed by gmail_id. Emails missing from the response stay
    unclassified and get retried on the next sync pass.
    """
    if not emails:
        return {}
    provider = provider_or_none()
    if provider is None:
        return {}

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
            SYSTEM_PROMPT, user, response_schema=list[EmailSignals]
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
