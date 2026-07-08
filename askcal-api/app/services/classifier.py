"""Email classification via Gemini (free tier).

One Gemini call classifies a BATCH of emails (classify_batch_size, default 10)
to stay inside free-tier rate limits. The model extracts structured signals
only — the regret score itself comes from the deterministic formula in
regret.py, so scores stay reproducible and tunable.

If ASKCAL_GEMINI_API_KEY is unset, classification is skipped entirely and
emails stay unranked until a later sync.
"""

import logging
from datetime import datetime, timezone
from typing import Literal

from pydantic import BaseModel, Field, field_validator

from app.config import get_settings
from app.models import Email, TrackKey

logger = logging.getLogger("askcal.classifier")

SenderType = Literal[
    "client", "recruiter", "professor", "automated_system", "peer", "newsletter", "other"
]
Consequence = Literal[
    "opportunity_loss", "grade_loss", "client_trust", "money_loss", "social", "none"
]


class EmailSignals(BaseModel):
    """Structured signals Gemini extracts per email. Stored as JSONB on the
    email row — audit trail now, training labels for the ML model later."""

    gmail_id: str
    track: Literal["career", "design", "uni", "feed", "finance", "none"]
    sender_type: SenderType
    consequence: Consequence
    action_required: bool
    # ISO 8601 string (Gemini output is more reliable as a string field)
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


PROMPT_TEMPLATE = """\
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
- deadline_utc: only if a concrete deadline is stated or strongly implied
  (ISO 8601, UTC). Today is {today_utc}.
- estimated_minutes: rough effort to fully handle the email's ask, null if no ask
- confidence: how sure you are about the track + consequence overall
- Return one result object per input email, echoing its gmail_id exactly.

Emails:
{emails_json}
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


def parse_deadline(value: str | None) -> datetime | None:
    """Lenient ISO parse; naive values are assumed UTC."""
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


async def classify_batch(emails: list[Email]) -> dict[str, EmailSignals]:
    """One Gemini call for up to classify_batch_size emails.

    Returns signals keyed by gmail_id. Emails missing from the response stay
    unclassified and get retried on the next sync pass.
    """
    s = get_settings()
    if not s.gemini_api_key and not s.gemini_use_vertex:
        logger.info("no Gemini backend configured — skipping classification")
        return {}

    from google import genai  # deferred: import cost + optional dependency at runtime

    import json

    prompt = PROMPT_TEMPLATE.format(
        today_utc=datetime.now(timezone.utc).date().isoformat(),
        emails_json=json.dumps([_email_payload(e) for e in emails], indent=2),
    )

    if s.gemini_use_vertex:
        client = genai.Client(
            vertexai=True,
            project=s.gemini_vertex_project,
            location=s.gemini_vertex_location,
        )
    else:
        client = genai.Client(api_key=s.gemini_api_key)
    response = await client.aio.models.generate_content(
        model=s.gemini_model,
        contents=prompt,
        config={
            "response_mime_type": "application/json",
            "response_schema": list[EmailSignals],
        },
    )
    parsed: list[EmailSignals] = response.parsed or []

    known_ids = {e.gmail_id for e in emails}
    out: dict[str, EmailSignals] = {}
    for sig in parsed:
        if sig.gmail_id in known_ids:
            out[sig.gmail_id] = sig
        else:
            logger.warning("Gemini returned unknown gmail_id %s", sig.gmail_id)
    missing = known_ids - out.keys()
    if missing:
        logger.warning("Gemini omitted %d email(s); will retry next sync", len(missing))
    return out
