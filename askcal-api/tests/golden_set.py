"""A corpus of mail with the classification it ought to get.

Every prompt change until now has been validated by waiting for real mail and
seeing whether it looked right — which finds a regression days later, in
production, on the one message that mattered.

Each case is here because something got it wrong, or because the prompt has a
rule that exists only to handle it. The `why` field is the rule being tested;
if a case ever stops earning that sentence, delete it rather than keeping a
corpus that grows without saying anything.

Used two ways:

- offline, by `test_golden_set.py`, which asserts what a *correct* classification
  then does — whether it becomes a task, which inbox band it lands in. No model
  runs, so this is part of the normal suite.
- against the real classifier, by `app/scripts/classify_golden.py`, which reports
  what the model actually said and where it disagreed.
"""

from dataclasses import dataclass, field


@dataclass(frozen=True)
class GoldenCase:
    id: str
    subject: str
    sender: str
    body: str
    # What the classifier should say.
    track: str
    action_required: bool
    consequence: str
    has_deadline: bool
    # The rule this case exists to pin.
    why: str
    # Tracks the mailbox usually carries, when that is part of the test.
    mailbox_tracks: list[str] = field(default_factory=list)
    # Some mail genuinely could sit in two tracks and the choice does not change
    # what happens to it. Those cases still pin the part they exist for — a
    # deadline, a gate — without asserting a filing decision nobody would defend.
    assert_track: bool = True


GOLDEN: list[GoldenCase] = [
    # ── real work, from senders that look like noise ───────────────────────
    GoldenCase(
        id="lms-assignment",
        subject="Week 3 Assignment — submission closes Friday 5pm",
        sender="noreply@lms.bmsce.ac.in",
        body="Your Week 3 assignment must be submitted through the portal by "
             "Friday 17:00. Late submissions are not accepted.",
        track="uni",
        action_required=True,
        consequence="grade_loss",
        has_deadline=True,
        why="A no-reply LMS address is still real work. Filtering automated "
            "senders once dropped every assignment on the floor.",
    ),
    GoldenCase(
        id="online-assessment",
        subject="Complete your online assessment",
        sender="no-reply@hackerrank.com",
        body="You have been invited to complete an online assessment for the "
             "Software Engineer role. The link expires in 72 hours.",
        track="career",
        action_required=True,
        consequence="opportunity_loss",
        has_deadline=True,
        why="Same trap as the LMS: an ATS link is a real task from a machine.",
    ),
    GoldenCase(
        id="fees-due",
        subject="Semester fee payment due",
        sender="accounts@bmsce.ac.in",
        body="The semester fee of Rs 84,000 is payable by 30 August. A late fee "
             "applies after that date.",
        track="finance",
        action_required=True,
        consequence="money_loss",
        has_deadline=True,
        why="Money that is DUE is work. It arrives at a college address, so it "
            "also checks that a mailbox's usual track does not override content.",
        mailbox_tracks=["uni"],
    ),
    GoldenCase(
        id="client-revision",
        subject="Re: brand deck — a couple of changes",
        sender="priya@studio.example",
        body="Loved the second option. Could you swap the cover type and send "
             "it back before the client call on Thursday?",
        track="design",
        action_required=True,
        consequence="client_trust",
        has_deadline=True,
        why="A person asking for a change is the clearest possible task.",
    ),

    # ── things that look like work and are not ────────────────────────────
    GoldenCase(
        id="job-digest",
        subject="50 new jobs for you this week",
        sender="jobs-noreply@linkedin.com",
        body="Software Engineer at Acme. Backend Developer at Globex. "
             "12 more roles matching your profile.",
        track="feed",
        action_required=False,
        consequence="none",
        has_deadline=False,
        why="A digest listing openings must not become a task — the single "
            "noisiest false positive there is. Where it gets FILED is arguable: "
            "the model reads it as career, which is defensible for a mail about "
            "jobs, and it leads to the same outcome either way. Three attempts "
            "to move it (the digest rule, a track-by-what-it-asks principle, a "
            "Feed description naming digests outright) did not, and stuffing a "
            "fourth in would cost the rules that do work.",
        assert_track=False,
    ),
    GoldenCase(
        id="payment-receipt",
        subject="Payment successful — Rs 84,000",
        sender="noreply@razorpay.com",
        body="Your payment of Rs 84,000 to BMS College has been received. "
             "This is your receipt.",
        track="none",
        action_required=False,
        consequence="none",
        has_deadline=False,
        why="Completed money movement reports what happened. Nearly identical "
            "wording to the fee that IS due, which is why both are here — and "
            "the prompt files paid receipts under `none`, not under money.",
    ),
    GoldenCase(
        id="social-nudge",
        subject="Aarav wants to connect on LinkedIn",
        sender="invitations@linkedin.com",
        body="Aarav Sharma would like to connect with you.",
        track="none",
        action_required=False,
        consequence="social",
        has_deadline=False,
        why="Social notifications have a consequence the gates refuse outright, "
            "so this pins the floor as well as the classification. The prompt "
            "puts notifications in `none`.",
    ),
    GoldenCase(
        id="newsletter",
        subject="This week in Swift",
        sender="hello@swiftweekly.example",
        body="Observation macros, the new Foundation formatting APIs, and a "
             "deep dive on SwiftData migrations.",
        track="feed",
        action_required=False,
        consequence="none",
        has_deadline=False,
        why="The ordinary case. If this ever becomes a task the gates are broken.",
    ),

    # ── deadlines, which is where the model has been wrong most ───────────
    GoldenCase(
        id="by-morning",
        subject="Need the figures by morning",
        sender="ravi@studio.example",
        body="Can you send the updated figures by morning? I present at noon.",
        track="design",
        action_required=True,
        consequence="client_trust",
        has_deadline=True,
        why='"By morning" once resolved nineteen hours out, because the prompt '
            "gave the model a UTC date and no timezone.",
    ),
    GoldenCase(
        id="eod",
        subject="Invoice approval needed EOD",
        sender="finance@studio.example",
        body="Please approve the March invoice by EOD today.",
        track="design",
        action_required=True,
        consequence="client_trust",
        has_deadline=True,
        why='"EOD" means close of business, not midnight — a five-hour gap on '
            "something due the same day.",
        # An invoice is money and it is also client work. The case exists for
        # the EOD rule, and both filings lead to the same task on the same day.
        assert_track=False,
    ),
    GoldenCase(
        id="start-not-deadline",
        subject="Your course begins next Monday",
        sender="noreply@coursera.example",
        body="Enrolment is confirmed. The course begins on Monday and you can "
             "start any time after that.",
        track="uni",
        action_required=False,
        consequence="none",
        has_deadline=False,
        why="A stated START is not a deadline. Reading it as one puts a "
            "countdown on something with no due date at all.",
        # A course-start confirmation is arguably coursework and arguably
        # reading. It changes nothing about what happens to it, so this case
        # asserts the deadline rule it was written for and lets the filing go.
        assert_track=False,
    ),
    GoldenCase(
        id="urgent-no-date",
        subject="URGENT: action required on your account",
        sender="security@bank.example",
        body="We need you to review recent activity on your account as soon as "
             "possible.",
        track="finance",
        action_required=True,
        consequence="money_loss",
        has_deadline=False,
        why='"ASAP" is urgency, not a date. Inventing a deadline here would '
            "outrank things that genuinely have one.",
    ),
]
