<div align="center">

# Askcal

**A context-aware daily scheduler that ranks your inbox by regret, not urgency.**

Built for the student freelancer juggling classes, client work, and job hunting at once —
one inbox, three lives, zero patience for another to-do app that just lists things.

[![backend tests](https://img.shields.io/badge/backend%20tests-79%20passing-000000?style=flat-square)](askcal-api)
[![stack](https://img.shields.io/badge/stack-FastAPI%20%C2%B7%20Postgres%20%C2%B7%20SwiftUI-000000?style=flat-square)]()
[![python](https://img.shields.io/badge/python-3.13-000000?style=flat-square)]()
[![license](https://img.shields.io/badge/license-unreleased-000000?style=flat-square)]()

</div>

---

## What it actually does

Every email doesn't deserve the same amount of your attention. Askcal reads your inbox with
Gemini, scores each message by **regret** — what it actually costs you to ignore it, not how
loud it shouts — and turns the ones that matter into tasks on your day, already slotted
around your calendar.

- **Regret-ranked inbox** — swipe an email into today, or push it to tomorrow. No manual triage.
- **Auto-task pipeline** — actionable mail (a due invoice, an OA link, a client brief) becomes
  a task the moment it's classified. Newsletters stay newsletters.
- **A day that plans itself** — tasks flow around your real Google Calendar busy blocks;
  pin one to an exact time and everything else routes around it, never landing in the past.
- **Deadline countdowns that actually count down** — "due in 25 min," "due in 6 h," "due in
  3 days" — computed live, not frozen at whatever it said when the page loaded.
- **Tracks, not folders** — Uni, Career, Design, Finance, Feed — each weighted to *your*
  actual life (a freelance designer and a full-time student get different regret scores for
  the identical email).
- **Routines + a closing ritual** — daily habits that reset at midnight, and an evening
  review that carries unfinished work into tomorrow instead of guilt-tripping you about it.

No accent colors, no gradients, no cute mascot pretending to be your friend. Strictly
off-white and black, switchable, quiet by design.

<br>

## The stack

```
┌──────────────────────┐      ┌───────────────────────────┐      ┌───────────────────┐
│   Askcal (iOS)         │◄────►│   askcal-api                │◄────►│  Google APIs        │
│   SwiftUI, monochrome  │ JWT  │   FastAPI + Postgres         │      │  Gmail · Calendar    │
│   @Observable state    │      │   Alembic · async SQLAlchemy │      │  Gemini classifier   │
└──────────────────────┘      └───────────────────────────┘      └───────────────────┘
```

| Layer | Tech |
|---|---|
| **Backend** | FastAPI, Python 3.13, SQLAlchemy 2.0 (async, asyncpg), Alembic, PostgreSQL 16 |
| **Auth** | Google OAuth 2.0 → short-lived JWT (15 min) + DB-backed opaque refresh tokens |
| **Classification** | Gemini (structured output) extracts signals; a deterministic formula turns them into a 0–100 regret score — reproducible, tunable, never a black box |
| **iOS** | SwiftUI, `@Observable`, Dynamic Type–aware monochrome design system |
| **Landing** | Three.js + GSAP scroll experience *(currently mid-rebrand — see [Status](#status))* |

<br>

## Repo layout

```
Askcal/
├── askcal-api/          FastAPI backend — the brain
│   ├── app/
│   │   ├── models/       users, tasks, tracks, emails, routines, refresh_tokens
│   │   ├── routers/      auth · today · tasks · inbox · calendar · tracks · routines · me
│   │   ├── services/     gmail ingestion · Gemini classifier · regret scoring ·
│   │   │                 day-plan scheduling · sync orchestration + auto-tasking
│   │   └── schemas/      camelCase API contracts
│   ├── alembic/versions/  5 migrations, schema history
│   └── tests/             79 tests — regret formula, scheduler, classifier, auth
│
├── Askcal/               SwiftUI iOS app — the face
│   └── Askcal/
│       ├── Views/         Today · Inbox · Calendar · Routine · Tracks · Review · More
│       ├── DesignSystem/  MonoTheme, MonoType, shared components
│       ├── State/         AskcalStore — single source of truth, offline-first
│       └── Services/      APIClient, Keychain, notifications
│
└── askcal-landing/       Scroll-driven marketing site (WebGL)
```

<br>

## Getting started

### Backend

```bash
cd askcal-api
cp .env.example .env              # then set ASKCAL_JWT_SECRET (openssl rand -hex 32)
docker compose up -d               # Postgres 16 on :5432
uv sync                            # deps into .venv
uv run alembic upgrade head        # schema
uv run uvicorn app.main:app --reload --host 0.0.0.0
```

API docs at `http://localhost:8000/docs`. Run the suite with `uv run pytest`.

Gmail ingestion and Gemini classification are both optional at boot — the API degrades
gracefully (`503`/skipped) until you drop in `ASKCAL_GOOGLE_CLIENT_ID` /
`ASKCAL_GEMINI_API_KEY`. Full walkthrough in [`askcal-api/README.md`](askcal-api/README.md).

### iOS

Open `Askcal/Askcal.xcodeproj` in Xcode 26. Point `APIClient.defaultBaseURL` at your running
backend (a tunnel like ngrok if you're testing on a physical device — localhost won't resolve
from a phone), build, run.

<br>

## Status

Actively built in daily sessions, backend-first. Current state:

- ✅ Auth, Gmail ingestion, Gemini classification, regret scoring — all live and tested
- ✅ Auto-scheduling around real Google Calendar events, with user-pinnable task times and
  live deadline countdowns
- ✅ Full monochrome iOS app: Today, Inbox, Calendar (interactive, per-date drill-down),
  Routines, Tracks, Review, onboarding on every launch
- ✅ 79 backend tests passing
- 🚧 `askcal-landing` still reflects an earlier coffee-themed concept from before the product
  pivoted to the monochrome design language above; the landing page rebuild is queued
- 🚧 Web dashboard, deploy pipeline, and adaptive scheduling (chronotype, weight nudging)
  are deliberately not built yet
- 🚧 Pre-open-source hardening in progress: refresh-token encryption at rest, PKCE on the
  OAuth flow, CI, and a LICENSE are the current blockers — not yet safe to treat as
  production-ready for public self-hosting

<br>

---

<div align="center">
<sub>Built solo, one honest bug report at a time.</sub>
</div>
