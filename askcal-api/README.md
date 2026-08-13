# askcal-api

FastAPI backend for [Askcal](../) — context-aware daily scheduler for student freelancers.
Serves `api.askcal.lucenity.dev`.

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

Tracks are rows the user names, not a fixed set. Each has a slug (stable), a
label (whatever they called it), and a **description that goes into the
classifier prompt verbatim** — that description is the only thing that can move
a piece of mail out of a track it never belonged in.

A new account starts with five — `career`, `uni`, `design`, `finance`, `feed` —
and every field on them is editable afterwards. Built-ins can be renamed and
switched off but not deleted, which covers every reason to want one gone without
stranding the mail already filed under it.

Two flags decide what a track does: `active` (mail here may become work) and
`auto_tasks` (this track makes work at all — off for read-later). Adding or
editing a track re-runs the auto-task gates over mail already classified, so a
change reaches the inbox you already have rather than only future mail.

Weights still come from onboarding (`app/services/profile.py`), which only has
an opinion about the five it shipped with — a track the user invented is left
exactly as they set it.

`app/services/tracks.py` owns the starting set, the slug rules and the prompt
block.

## Mailboxes

`mail_accounts` holds every connected Google account; `users.google_refresh_token`
is the superseded single-account column. One is `is_primary` — it owns the
sign-in and the calendar — and the rest are mailboxes only.

Each carries the set of tracks its mail is usually about, passed to the
classifier as a leaning and never a rule. A sync pulls every active mailbox and
isolates failures: a revoked token on one address costs that inbox, not the
whole pass.

Linking goes through `POST /api/accounts/link`, which is authenticated and
returns a URL rather than redirecting, so no access token travels in a browser
redirect. The callback issues no tokens on that path.

## Secrets at rest

Google refresh tokens are encrypted with Fernet (`app/core/crypto.py`), applied
as a column type so no call site can forget it. Values carry an `enc:v1:`
prefix, so plaintext rows written before the key keep working until
`app/scripts/encrypt_tokens.py` rewrites them — turning encryption on does not
take a mailbox offline.

Set `ASKCAL_TOKEN_ENCRYPTION_KEY` in `.env.prod`:

```bash
python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
```

`/health` reports `tokens_encrypted`. A malformed key raises at startup rather
than falling back to plaintext.

## Deployment

```bash
# lean image — use when ASKCAL_LLM_PROVIDER=gemini
docker compose -f docker-compose.prod.yml up -d --build

# with the Claude Code CLI — required when ASKCAL_LLM_PROVIDER=claude_code
docker compose -f docker-compose.prod.yml -f docker-compose.subscription.yml up -d --build
```

The subscription overlay is separate because Node plus the CLI takes the image
from 556MB to 1.26GB, and that is only worth carrying when the CLI is the
transport.
It needs `ASKCAL_CLAUDE_CODE_OAUTH_TOKEN` in `.env.prod` — a container has no
home directory holding CLI credentials, so `claude setup-token` on your own
machine is the only way in. Without it the provider refuses to construct at
startup with a message naming the fix.

Confirm a deploy with `curl https://api.askcal.lucenity.dev/health`, which
reports `llm_provider`, `classifier_configured` and `tokens_encrypted`.

Migrations run from the container's entrypoint on start. That entrypoint
**ignores any command it is given**, so one-off scripts need `exec`, not `run`:

```bash
docker compose -f docker-compose.prod.yml -f docker-compose.subscription.yml \
    exec api uv run python -m app.scripts.<name>
```

## Layout

```
app/
├── main.py          FastAPI app, CORS, error handlers
├── config.py        pydantic-settings (env prefix ASKCAL_)
├── db.py            async engine + session dependency
├── deps.py          get_current_user (JWT bearer)
├── core/             security (JWT/refresh tokens), crypto (secrets at rest),
│                      error shape (AskcalError)
├── models/           users, mail_accounts, tracks, tasks, emails, day_notes,
│                      routines, refresh_tokens, day_logs; types.py holds the
│                      encrypted column type
├── schemas/          camelCase API models
├── llm/              provider protocol + transports (claude_code, gemini),
│                      structured-output parsing, provider registry
├── services/          gmail (OAuth + ingestion), gcal (calendar read), classifier
│                      (prompt + schema + retry policy), regret (scoring formula),
│                      sync (orchestration + auto-tasking), scheduling (day-plan,
│                      local-day resolution, humanized deadlines), tracks (the
│                      user's taxonomy), accounts (which mailbox answers what),
│                      triage (what a mail wants), digest (morning + evening)
├── scripts/          one-off maintenance, dry-run unless --apply
└── routers/          /auth/*, /api/today, /api/tasks, /api/inbox (+ sync/handle/
                       snooze), /api/calendar, /api/tracks, /api/accounts,
                       /api/notes, /api/routines, /api/me, /api/settings,
                       /api/digest/*, /api/closing-time, /api/carry-forward
```

`app/services/brew_engine.py` is a leftover from an earlier coffee-themed
concept the product has since moved away from — `/api/today` still returns
its `brew`/`brewData` fields for backward compatibility, but the current iOS
app ignores them entirely. Slated for removal.
