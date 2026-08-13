"""What the settings screen reads and writes.

Split deliberately into two halves. Deployment facts — which model classifies
your mail, whether it is working, how often sync runs — are reported and cannot
be set from a phone. Preferences that are genuinely yours are stored per user
and patchable.

The classifier credential appears nowhere in either half. It lives in the
environment on the server, and moving it onto a settings screen would mean a
subscription token travelling from a device through the API into a database.
"""

from fastapi import APIRouter
from sqlalchemy.orm.attributes import flag_modified

from app.config import get_settings
from app.deps import CurrentUser, DbSession
from app.llm.registry import classifier_unavailable_reason
from app.schemas.settings import (
    AutoTaskPrefs,
    ClassifierStatus,
    ReminderPrefs,
    SettingsPatch,
    SettingsResponse,
    SyncStatus,
)

router = APIRouter(prefix="/api/settings", tags=["settings"])

# Falls back to the deployment default when the user has never set one, so a
# fresh account behaves exactly as the server was configured to.
_PREF_KEYS = {
    "auto_task_min_confidence",
    "auto_task_min_regret",
    "morning_digest",
    "morning_hour",
    "evening_nudge",
    "evening_hour",
    "inbox_window_days",
}

_DEFAULTS = {
    "morning_digest": True,
    "morning_hour": 8,
    "evening_nudge": True,
    "evening_hour": 21,
}


def _pref(user, key: str, fallback):
    return (user.preferences or {}).get(key, fallback)


def _build(user) -> SettingsResponse:
    s = get_settings()
    reason = classifier_unavailable_reason()
    return SettingsResponse(
        classifier=ClassifierStatus(
            provider=s.llm_provider,
            model=(
                s.claude_code_model
                if s.llm_provider == "claude_code"
                else s.gemini_model
            ),
            configured=reason is None,
            detail=reason,
        ),
        sync=SyncStatus(
            interval_minutes=s.sync_interval_minutes,
            window_days=_pref(user, "inbox_window_days", s.inbox_window_days),
            last_synced_at=user.last_synced_at,
            last_attempt_at=user.last_sync_attempt_at,
            last_error=user.last_sync_error,
            enabled=s.sync_enabled,
        ),
        auto_task=AutoTaskPrefs(
            min_confidence=_pref(
                user, "auto_task_min_confidence", s.auto_task_min_confidence
            ),
            min_regret=_pref(user, "auto_task_min_regret", s.auto_task_min_regret),
        ),
        reminders=ReminderPrefs(
            morning_digest=_pref(user, "morning_digest", _DEFAULTS["morning_digest"]),
            morning_hour=_pref(user, "morning_hour", _DEFAULTS["morning_hour"]),
            evening_nudge=_pref(user, "evening_nudge", _DEFAULTS["evening_nudge"]),
            evening_hour=_pref(user, "evening_hour", _DEFAULTS["evening_hour"]),
        ),
        timezone=user.timezone,
    )


@router.get("", response_model=SettingsResponse)
async def get_settings_for_user(user: CurrentUser) -> SettingsResponse:
    return _build(user)


@router.patch("", response_model=SettingsResponse)
async def patch_settings(
    body: SettingsPatch, user: CurrentUser, db: DbSession
) -> SettingsResponse:
    sent = body.model_fields_set  # only touch what the client actually sent
    prefs = dict(user.preferences or {})

    for key in _PREF_KEYS & sent:
        prefs[key] = getattr(body, key)

    if prefs != (user.preferences or {}):
        user.preferences = prefs
        # SQLAlchemy does not see in-place mutation of a JSONB dict, and
        # reassignment alone is not always enough to mark it dirty — without
        # this the write silently does nothing.
        flag_modified(user, "preferences")

    if "timezone" in sent and body.timezone:
        user.timezone = body.timezone

    await db.commit()
    return _build(user)
