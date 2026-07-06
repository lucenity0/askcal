# pulse-api

FastAPI backend for [Pulse](../) — context-aware daily scheduler for student freelancers.
Serves `api.lucenity.dev`.

## Stack

- FastAPI + Uvicorn, Python 3.13 via [uv](https://docs.astral.sh/uv/)
- PostgreSQL 16, SQLAlchemy 2.0 (async, asyncpg), Alembic migrations
- Auth: Google OAuth 2.0 sign-in → short-lived JWT access token (15 min) +
  DB-backed opaque refresh token (revocable via `POST /auth/revoke`)

## Quickstart

```bash
cp .env.example .env          # then set PULSE_JWT_SECRET (openssl rand -hex 32)
docker compose up -d          # local Postgres on :5432
uv sync                       # install deps into .venv
uv run alembic upgrade head   # create schema
uv run uvicorn app.main:app --reload
```

Docs at http://localhost:8000/docs. Run tests with `uv run pytest`.

## Gmail OAuth + ingestion

OAuth needs an OAuth client (Web application) from the Google Cloud console:
fill `PULSE_GOOGLE_CLIENT_ID` / `PULSE_GOOGLE_CLIENT_SECRET` in `.env`.
Scopes: `openid email profile gmail.readonly gmail.modify`. Until then
`POST /auth/google` returns `503 GMAIL_NOT_CONFIGURED`.

Ingestion pulls recent mail (batch API, 50/request), stores raw messages in
`emails`, then classifies async. It runs from an in-process loop every
`PULSE_SYNC_INTERVAL_MINUTES` (default 10) and on demand via
`POST /api/inbox/sync` (202 → background). Attachments are never fetched —
lazy download + OCR is a later phase.

## Classification + regret scoring

`app/services/classifier.py` sends batches of `PULSE_CLASSIFY_BATCH_SIZE`
emails per Gemini call (free-tier key from https://aistudio.google.com/apikey →
`PULSE_GEMINI_API_KEY`; classification is skipped while unset). Gemini
extracts structured signals only — track, sender type, consequence-of-
ignoring, deadline, effort, confidence — stored on `emails.signals` (JSONB,
future ML training data).

The 0–100 regret score comes from the deterministic formula in
`app/services/regret.py` (consequence base + deadline proximity + sender +
action-required, × track weight, low-confidence dampening). Scores are fully
reproducible from stored signals; `tests/test_regret.py` pins the behavior.

Triage: `POST /api/inbox/{gmail_id}/handle` (swipe right → creates a Task on
the classified track, best-effort Gmail mark-as-read),
`POST /api/inbox/{gmail_id}/snooze` (swipe left → hidden until tomorrow 08:00
user-local, or `until`).

## Brew engine

`app/services/brew_engine.py` is a straight port of the **source of truth**,
`pulse-frontend/scripts/brew-engine.js` (Claude skill). Thresholds, the
carry-forward penalty (4 pts/task) and task-count bumps must stay in sync —
`tests/test_brew_engine.py` encodes the JS behavior case by case.

Color palettes are deliberately not ported: colors live in `brew-engine.js`
(web) and `BrewTheme.swift` (iOS). The API ships only `name/tagline/level`.

## Layout

```
app/
├── main.py          FastAPI app, CORS, error handlers
├── config.py        pydantic-settings (env prefix PULSE_)
├── db.py            async engine + session dependency
├── deps.py          get_current_user (JWT bearer)
├── core/            security (JWT/refresh tokens), error shape
├── models/          users, tracks, tasks, emails, refresh_tokens, day_logs
├── schemas/         camelCase API models per references/api-contracts.md
├── services/        brew_engine, gmail (OAuth + ingestion), classifier (Gemini),
│                    regret (scoring formula), sync (orchestration), scheduling
└── routers/         /auth/*, /api/today, /api/inbox (+ sync/handle/snooze),
                     /api/tracks, /api/closing-time, /api/carry-forward
```

Day-plan generation in `/api/today` is a naive placeholder (sequential blocks
from 09:00) until the Claude-API schedule generation phase.
