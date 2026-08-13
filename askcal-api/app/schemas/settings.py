import datetime as dt

from pydantic import Field

from app.schemas.base import CamelModel


class ClassifierStatus(CamelModel):
    """What is actually classifying your mail, and whether it works.

    Read-only. The provider, the model and the credential are deployment
    concerns living in the environment on the server — a subscription token
    travelling from a phone through the API into a database is a far worse
    place for it than an env var on the box. This reports; it does not set.
    """

    provider: str
    model: str
    configured: bool
    # Only present when something is wrong, and then it says what.
    detail: str | None = None


class SyncStatus(CamelModel):
    interval_minutes: int
    window_days: int
    # When mail last actually arrived.
    last_synced_at: dt.datetime | None = None
    # When a pass last ran, and why it failed if it did. "Last run" used to show
    # last_synced_at, so a sync running on time and failing was indistinguishable
    # from one that had stopped running an hour ago.
    last_attempt_at: dt.datetime | None = None
    last_error: str | None = None
    enabled: bool


class AutoTaskPrefs(CamelModel):
    """How eager Askcal is to turn mail into work by itself.

    Both gates compound deliberately: the score is already damped by
    confidence, so raising either makes it markedly more conservative.
    """

    min_confidence: float = Field(ge=0.0, le=1.0)
    min_regret: int = Field(ge=0, le=100)
    # How hard work you keep pushing to tomorrow argues for a place in the day.
    # Stored and read by nothing for months; it decides plan order now.
    carry_forward_sensitivity: float = Field(ge=0.0, le=3.0)


class ReminderPrefs(CamelModel):
    morning_digest: bool
    morning_hour: int = Field(ge=0, le=23)
    evening_nudge: bool
    evening_hour: int = Field(ge=0, le=23)


class SettingsResponse(CamelModel):
    classifier: ClassifierStatus
    sync: SyncStatus
    auto_task: AutoTaskPrefs
    reminders: ReminderPrefs
    timezone: str


class SettingsPatch(CamelModel):
    """Every field optional — a patch changes only what it carries.

    Nothing here can alter the classifier credential or provider. Those are not
    absent by oversight.
    """

    auto_task_min_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    auto_task_min_regret: int | None = Field(default=None, ge=0, le=100)
    # 0 leaves the classifier's score untouched; higher makes the day insist
    # harder about work you keep pushing.
    carry_forward_sensitivity: float | None = Field(default=None, ge=0.0, le=3.0)
    morning_digest: bool | None = None
    morning_hour: int | None = Field(default=None, ge=0, le=23)
    evening_nudge: bool | None = None
    evening_hour: int | None = Field(default=None, ge=0, le=23)
    inbox_window_days: int | None = Field(default=None, ge=1, le=90)
    timezone: str | None = None
