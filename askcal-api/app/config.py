from functools import lru_cache

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

    # Gemini classifier — free-tier API key from https://aistudio.google.com/apikey.
    # Classification is skipped (emails stay unranked) until this is set.
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.5-flash-lite"
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
