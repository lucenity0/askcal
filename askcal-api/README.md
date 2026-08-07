# askcal-api

FastAPI backend for [Askcal](../) — context-aware daily scheduler for student freelancers.
Serves `api.lucenity.dev`.

## Stack

- FastAPI + Uvicorn, Python 3.13 via [uv](https://docs.astral.sh/uv/)
- PostgreSQL 16, SQLAlchemy 2.0 (async, asyncpg), Alembic migrations
- Auth: Google OAuth 2.0 sign-in → short-lived JWT access token (15 min) +
  DB-backed opaque refresh token (revocable via `POST /auth/revoke`)

## Quickstart

```bash
cp .env.example .env          # then set ASKCAL_JWT_SECRET (openssl rand -hex 32)
docker compose up -d          # local Postgres on :5432
uv sync                       # install deps into .venv
uv run alembic upgrade head   # create schema
uv run uvicorn app.main:app --reload --host 0.0.0.0
```

Docs at http://localhost:8000/docs. Run tests with `uv run pytest`.

`--host 0.0.0.0` matters if you're testing the iOS app on a physical device —
uvicorn's default `127.0.0.1` only accepts connections from the same machine.

## Gmail + Calendar OAuth, ingestion

OAuth needs an OAuth client (Web application) from the Google Cloud console:
fill `ASKCAL_GOOGLE_CLIENT_ID` / `ASKCAL_GOOGLE_CLIENT_SECRET` in `.env`.
One consent flow covers both mail and calendar — scopes:
`openid email profile gmail.readonly gmail.modify calendar.readonly`. Make
sure all five are added under **Data Access** in the console, not just
requested in the auth URL, or the grant silently omits Calendar and
`/api/calendar` returns `403 CALENDAR_NOT_AUTHORIZED`. Until credentials are
set, `POST /auth/google` returns `503 GMAIL_NOT_CONFIGURED`.

Ingestion pulls the current day's mail (batch API, 50/request), stores raw
messages in `emails`, then classifies async. It runs from an in-process loop
every `ASKCAL_SYNC_INTERVAL_MINUTES` (default 10) and on demand via
`POST /api/inbox/sync` (202 → background). Attachments are never fetched —
lazy download + OCR is a later phase.

## Classification, regret scoring, auto-tasking

`app/services/classifier.py` sends batches of emails to whichever transport
`ASKCAL_LLM_PROVIDER` selects. The model extracts structured signals only —
track, sender type, consequence-of-ignoring, deadline, effort, confidence —
stored on `emails.signals` (JSONB, future ML training data).

Two providers, both behind the one `LLMProvider` protocol in `app/llm/base.py`,
so switching is config rather than code:

| | Setup | Notes |
|---|---|---|
| `claude_code` (default) | `npm i -g @anthropic-ai/claude-code && claude` | No API key — drives the local CLI against your own Claude subscription. In Docker, also needs `ASKCAL_CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`. |
| `gemini` | `ASKCAL_GEMINI_API_KEY`, or Vertex via the VM service account | Constrained decoding via `response_schema`, so its output is shape-guaranteed. |

The prompt, the JSON schema, gmail_id reconciliation and the retry policy all
live in `classifier.py`, above the transport — a provider is a dumb
`complete(system, user) -> text`, so adding one can never fork the classifier's
judgment. Because the CLI has no constrained decoding, `app/llm/structured.py`
renders the schema into the prompt from `EmailSignals.model_json_schema()` and
validates **per item**, so one malformed entry in a batch of 25 costs one email
rather than all of them; only the stragglers are retried.

Classification is skipped entirely (mail is still ingested) when no provider is
usable. `GET /health` reports `llm_provider` and `classifier_configured`, and a
bad setup is logged as an error at startup.

Note: the Claude Code CLI writes session transcripts under `~/.claude/projects/`,
so email excerpts touch local disk — a difference from Gemini, which only sends
them over TLS.

The 0–100 regret score comes from the deterministic formula in
`app/services/regret.py` (consequence base + deadline proximity + sender +
action-required, × track weight, low-confidence dampening). Scores are fully
reproducible from stored signals; `tests/test_regret.py` pins the behavior.

An actionable, classified email (`action_required` + a real, active track —
uni/career/design/finance, never `feed`) becomes a Task automatically during
sync — no swipe needed. Everything else waits in the inbox for manual triage:
`POST /api/inbox/{gmail_id}/handle` (swipe right → creates a Task),
`POST /api/inbox/{gmail_id}/snooze` (swipe left → hidden until tomorrow 08:00
user-local, or `until`).

## Scheduling

`app/services/scheduling.py` builds each day's plan around real Google
Calendar busy blocks. Two kinds of tasks:

- **Pinned** (`scheduled_at` set) — the user chose an exact time; the planner
  treats it as a fixed anchor and never moves it.
- **Auto-placed** — first-fit, highest-regret-first, into whatever's left
  after pinned tasks and calendar events are blocked out. Never scheduled in
  the past — the window starts at `max(day_start, now)`.

Overflow is explicit: anything that doesn't fit is returned in
`unscheduled`, never silently dropped or double-booked
(`tests/test_scheduling_engine.py`).

## Tracks

Four life-areas plus Finance: `uni`, `career`, `design`, `feed`, `finance`.
Each carries a per-user weight (`app/services/profile.py` maps onboarding
answers — student type, work type — to weights), so the same email scores
differently for two different users. Finance is always active at neutral
weight; urgency comes from the regret formula's `money_loss` consequence, not
the profile.

## Layout

```
app/
├── main.py          FastAPI app, CORS, error handlers
├── config.py        pydantic-settings (env prefix ASKCAL_)
├── db.py            async engine + session dependency
├── deps.py          get_current_user (JWT bearer)
├── core/             security (JWT/refresh tokens), error shape (AskcalError)
├── models/           users, tracks, tasks, emails, routines, refresh_tokens, day_logs
├── schemas/          camelCase API models
├── services/          gmail (OAuth + ingestion), gcal (calendar read), classifier
│                      (Gemini), regret (scoring formula), sync (orchestration +
│                      auto-tasking), scheduling (day-plan + humanized deadlines)
└── routers/          /auth/*, /api/today, /api/tasks, /api/inbox (+ sync/handle/
                       snooze), /api/calendar, /api/tracks, /api/routines, /api/me,
                       /api/closing-time, /api/carry-forward
```

`app/services/brew_engine.py` is a leftover from an earlier coffee-themed
concept the product has since moved away from — `/api/today` still returns
its `brew`/`brewData` fields for backward compatibility, but the current iOS
app ignores them entirely. Slated for removal.
