from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_prefix="ASKCAL_", extra="ignore")

    database_url: str = "postgresql+asyncpg://askcal:askcal@localhost:5432/askcal"
    debug: bool = False

    jwt_secret: str = "change-me"
    jwt_algorithm: str = "HS256"
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 30

    # Google OAuth 2.0 — the flow is wired but inert until these are filled in .env
    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = "http://localhost:5173/auth/callback"
    # Where this API is reachable — used to build the mobile OAuth callback
    # (add {api_base_url}/auth/google/callback to the Google console client)
    api_base_url: str = "http://localhost:8000"

    # Which transport classifies mail. A Literal, not a str, so a typo is a
    # startup ValidationError rather than a silent fall-through to the wrong
    # provider.
    # claude_code is the default because it needs no API key at all: it rides
    # the operator's own Claude subscription through the locally-installed CLI,
    # so a fresh clone classifies mail with zero credential setup.
    llm_provider: Literal["claude_code", "gemini"] = "claude_code"

    # Claude Code CLI provider — no API key at all: it rides the operator's own
    # Claude subscription via the locally-installed `claude` binary. On a dev
    # machine the CLI reads its own login and nothing here needs setting; inside
    # a container there is no home directory to read from, so the OAuth token
    # below is mandatory (mint it with `claude setup-token` on the host).
    claude_code_binary: str = "claude"
    # A CLI alias rather than a pinned id, so this survives model releases.
    # "haiku" is the cheaper switch once there's a golden set to justify it.
    claude_code_model: str = "sonnet"
    # Classification is extraction against an explicit rubric, not reasoning,
    # and effort is the quota lever — higher effort mostly buys deliberation the
    # rubric already supplies.
    claude_code_effort: Literal["low", "medium", "high", "xhigh", "max"] = "low"
    # Ceiling for one batch. A low-effort run on 25 emails lands well inside
    # this; the value exists so a wedged CLI cannot stall the sync loop past the
    # sync interval.
    claude_code_timeout_seconds: float = 240.0
    claude_code_oauth_token: str = ""
    # Bigger batches than Gemini and no inter-batch sleep: every invocation
    # re-pays the CLI's own multi-thousand-token preamble against subscription
    # quota, so one call of 25 beats three of 10, and there is no per-minute
    # request limit to pace against.
    claude_code_batch_size: int = 25
    claude_code_delay_seconds: float = 0.0

    # Extra attempts when the model's JSON does not validate. Only the emails
    # that actually failed are re-sent, so this is cheap. 1 is enough — a second
    # failure on the same email is a prompt problem, not a flake.
    classify_max_retries: int = 1

    # Gemini classifier. Two backends:
    #  1. AI Studio — set gemini_api_key (free-tier key from
    #     https://aistudio.google.com/apikey). Billed on AI Studio's own system.
    #  2. Vertex AI — set gemini_use_vertex=true + gemini_vertex_project. Uses
    #     GCP application-default credentials (the VM's service account), billed
    #     to the GCP project so it draws on Cloud billing/credits. No API key.
    # Classification is skipped (emails stay unranked) until one is configured.
    gemini_api_key: str = ""
    gemini_use_vertex: bool = False
    gemini_vertex_project: str = ""
    gemini_vertex_location: str = "us-central1"
    gemini_model: str = "gemini-2.5-flash-lite"
    # Gemini pacing (free-tier RPM). The Claude Code provider uses
    # claude_code_batch_size/_delay_seconds instead — but setting either of
    # these explicitly overrides the active provider's own defaults.
    classify_batch_size: int = 10  # emails per Gemini call
    classify_delay_seconds: float = 5.0  # between calls, respects free-tier RPM

    # Background sync loop (in-process; POST /api/inbox/sync triggers on demand)
    sync_enabled: bool = True
    sync_interval_minutes: int = 10
    gmail_lookback_days: int = 7
    gmail_max_results: int = 50

    cors_origins: list[str] = [
        "https://askcal.lucenity.dev",
        "http://localhost:5173",
    ]


@lru_cache
def get_settings() -> Settings:
    return Settings()
