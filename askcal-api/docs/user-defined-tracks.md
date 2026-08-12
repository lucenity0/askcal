# User-defined tracks

## Why

The five tracks — `career`, `design`, `uni`, `feed`, `finance` — are a hardcoded
enum. They are baked into a Postgres enum type, the classifier prompt, the
auto-task rules and the client's model layer.

They do not describe the owner's life. A PR review is work; it was filed as
`design`, because the model was asked to choose from five categories and that
was the closest one available. No amount of prompt tuning fixes a taxonomy that
is wrong, and the owner cannot change it without a rebuild.

The goal: the user names their own tracks — work, personal, college, whatever —
and the classifier files mail into those.

This should land **before** multi-account (#43). Most of what multi-account is
for is "college mail is college work, personal mail usually isn't", which is a
statement about tracks. Doing accounts first means doing that mapping twice.

## Blast radius

Measured, not estimated:

- 29 references to `TrackKey` across 10 backend files
- **Two Postgres enum columns holding live data**: `tracks.key` and
  `emails.track`, both `Enum(TrackKey, name="track_key")`
- 17 references in Swift
- Classifier prompt: `_RULES` in `app/services/classifier.py` describes each
  track in prose, and `EmailSignals.track` is a `Literal` of the five names —
  the structured-output schema is generated from that model, so the enum is
  currently what constrains the model's answer
- `AUTO_TASK_TRACKS` and `DEFAULT_ACTIVE_TRACKS` are sets of enum members
- `app/services/profile.py` maps onboarding answers to per-track weights

## Shape of the change

`Track` is already a per-user table with `weight` and `active`. Only `key` being
an enum is the problem. So this is smaller than it first looks.

### 1. Schema

- Add to `tracks`: `slug` (str, unique per user), `label` (str, what the user
  typed), `description` (str, nullable — fed to the classifier so the user can
  say what belongs in a track), `is_builtin` (bool), `sort_order` (int).
- Backfill `slug`/`label` from the existing `key` for every row.
- `emails.track` becomes `emails.track_id`, a nullable FK to `tracks.id`.
  Backfill by joining on `(user_id, key)`. **Keep the old column** for one
  release rather than dropping it in the same migration — a rollback that
  cannot recover its own data is not a rollback.
- Leave `tracks.key` in place, nullable, marking the built-ins. Drop the
  Postgres enum type only once nothing reads it.

`tasks.track_id` is already an FK. It needs no change, which is most of why
this is tractable.

### 2. Classifier

- `EmailSignals.track` becomes a plain `str`, validated against the user's slugs
  at parse time rather than by the schema. The structured-output schema is
  generated from the model class, so a `Literal` cannot express a per-user set.
- Build the track section of the prompt from the user's own tracks — label plus
  their description — instead of the hardcoded prose in `_RULES`.
- An unrecognised slug degrades to no track, exactly as `"none"` does now.
  Never invent a track from a model answer.

### 3. Auto-tasking

- `AUTO_TASK_TRACKS` disappears. Whether a track can auto-task becomes a column
  on the track (`auto_tasks`, default true), because with user-defined tracks
  there is no fixed list to hardcode. `feed` is the current exception and
  becomes a track with that flag off.
- `reconsider_auto_tasks` already exists and re-runs the gates over classified
  mail with no model call. Call it after any track edit, not just activation.

### 4. API

- `GET /api/tracks` returns all tracks with their flags, not only active ones.
  The current behaviour — returning only active tracks — is why the client
  cannot show a toggle in its real state without a second call.
- `POST /api/tracks`, `PATCH /api/tracks/{id}`, `DELETE /api/tracks/{id}`.
  Deleting needs a decision: reassign its tasks to another track, or leave them
  untracked. Untracked is probably right; a forced reassignment is a lie about
  where the work belonged.

### 5. Client

- `TrackKey` enum becomes a `Track` struct decoded from the API. It is used for
  display, for the composer's picker, and for grouping in `TracksView`; none of
  those need a compile-time set.
- Tracks screen gains add/rename/delete and a description field, since the
  description is what actually steers the classifier.

## Order

1. Migration with both columns present, backfilled, old ones still readable.
2. Backend reads the new columns, still writing both.
3. Client moves to the new shape.
4. A later migration drops `emails.track` and the enum type.

Steps 1–2 are deployable on their own and change nothing the user sees, which
is what makes this safe to do in pieces.

## Watch for

Every bug in this area so far has been the same shape: **state that decides
whether work reaches you, applied once, invisibly, with no way to see or change
it.** Four so far — the classifier silently unconfigured, an inactive track
blocking auto-tasking, carried tasks losing their day, and auto-task gates never
re-running on classified mail.

A per-user taxonomy adds more such state, not less. Anything added here needs a
way to see its current value and a way to change it, and changing it must reach
mail that has already arrived.
