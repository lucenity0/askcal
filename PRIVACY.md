# Privacy

Askcal reads a Gmail mailbox and a Google Calendar in order to build a day out
of them. That is a lot of access, so this document says exactly what is asked
for, exactly what is kept, and exactly what leaves the machine.

Every statement here is checkable against the code, and the file paths are
given so you can check it.

Askcal is a personal project, not a company and not a service you sign up for.
There is no shared instance: whoever runs the backend holds the data.

---

## What Google is asked for

`askcal-api/app/services/gmail.py`

| scope | why |
|---|---|
| `userinfo.email`, `userinfo.profile` | to know which account you connected |
| `gmail.readonly` | to read mail so it can be ranked |
| `gmail.modify` | to mark a message read when you triage it |
| `calendar.readonly` | to see which hours are already taken |

There is no send scope, no delete scope, and no write access to your calendar.
Askcal cannot email anyone as you, and cannot create, move or cancel an event.

You approve these on Google's own consent screen. Askcal never sees your Google
password.

---

## What is stored

**Your mail.** For each message: the Gmail id and thread id, the subject, the
sender, Gmail's snippet, and up to 20,000 characters of extracted plain-text
body (`BODY_TEXT_MAX_CHARS`, `gmail.py`). Attachments are not downloaded. The
body is kept because it is what the classifier reads and what a future model
would be trained on.

**What the classifier concluded.** Seven fields per message — track, sender
type, consequence, whether action is required, any deadline, an estimate in
minutes, and a confidence — stored as JSON beside the message
(`app/models/email.py`). This is an audit trail: it is what makes every score
reproducible.

**Your day.** Tasks, the tracks you named and the sentences you wrote for them,
per-day notes, and the busy blocks read from your calendar.

**Your Google refresh token**, encrypted at rest. Encryption is a property of
the database column rather than something each write remembers to do
(`app/models/types.py`, `app/core/crypto.py`), and `/health` reports whether it
is switched on. Anyone holding a refresh token holds the mailbox, which is why
it is treated differently from everything else here.

---

## What leaves the machine

**To the model provider.** Mail is classified in batches. What is sent is the
subject, the sender, the snippet and the body text, together with the names and
descriptions of your tracks. Which provider that is depends on how the instance
is configured — Claude via the Claude Code CLI, or Gemini. Their terms apply to
what they receive.

**To Google.** The ordinary API calls needed to read mail, mark a message read,
and read calendar busy times.

**Nowhere else.** No analytics, no error reporting service, no advertising, no
third-party embeds. The landing page loads no external resources at all: no
framework, no webfont from a CDN, no tracking pixel.

Nothing is ever sold, and there is no other party to sell it to.

---

## Removing it

Revoke Askcal from your Google account at
[myaccount.google.com/permissions](https://myaccount.google.com/permissions).
That stops all further access immediately.

Rows already stored stay in that instance's database until they are deleted
there. Deleting a connected mailbox deletes its mail with it — that cascade is
declared in the schema (`ondelete="CASCADE"`, `app/models/email.py`) rather than
left to application code to remember.

**There is not yet a one-tap "delete my account and everything in it" button in
the app.** It is the honest gap in this document, and it is the right thing to
add next.

---

## Changes

This file describes the code as it stands. If the scopes, the stored fields or
the outbound calls change, this changes with them — and the commit that changes
one should change the other.
