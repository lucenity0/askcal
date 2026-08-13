//
//  FocusCard.swift
//  Askcal
//
//  What you are meant to be on, right now.
//
//  It sits above the day rather than inside it because it answers a different
//  question. The timeline is "what is today"; this is "what now", and the
//  answer to that should be readable without reading the list.
//
//  The bar is live. `TimelineView` redraws it on the minute, so a slot that is
//  half gone looks half gone without the app having to be reopened — which is
//  the whole reason it is a bar and not a printed time.
//

import SwiftUI

struct FocusCard: View {
    let focus: AskcalStore.FocusInfo
    let companion: CompanionMotif
    var open: () -> Void

    @Environment(\.book) private var book
    @Environment(AskcalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A one-minute cadence: the bar moves at a rate a person notices over
        // a work session, and a faster clock would wake the view for nothing.
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            card
        }
    }

    private var card: some View {
        // The sprite sits beside the whole card, not beside the title.
        //
        // "56 min left" used to hold the top-right corner — it measured the
        // planned slot, and a task with no estimate gets a one-hour slot by
        // default, so it counted down an hour nobody chose next to a real
        // deadline saying something else. Removing it left the corner empty
        // with the sprite stranded below, so the writing is one column now and
        // the companion is centred against all of it.
        HStack(alignment: .center, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Rubric(focus.kicker)

                Text(focus.task.title)
                    .font(BookType.entry(20))
                    .foregroundStyle(book.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let progress = liveProgress {
                    ProgressBar(value: progress)
                        .padding(.top, Space.xs)
                }

                Text(metaLine)
                    .font(BookType.meta(11))
                    .foregroundStyle(book.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            // A tap gesture is invisible to VoiceOver: without this the card
            // reads as three loose pieces of text and there is no way to open
            // the task it is about.
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens this task")

            // No check here. Completing is what the timeline row below is
            // for, and a card whose job is "what now" should not be
            // offering to make itself disappear. The space goes to the
            // companion instead, which is the only thing in the app that
            // moves when nothing is happening.
            PixelSprite(motif: companion, size: 56)
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(book.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(book.ink, lineWidth: Stroke.strong)
                )
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: focus.task.id)
    }

    /// Recomputed each redraw rather than read off `focus`, which was captured
    /// when the view was built and would freeze the bar wherever it started.
    private var liveProgress: Double? {
        guard let slot = focus.slot, let start = slot.start(on: .now) else { return nil }
        let end = start.addingTimeInterval(Double(slot.duration) * 60)
        let now = Date.now
        guard now >= start, now < end else { return nil }
        return now.timeIntervalSince(start) / end.timeIntervalSince(start)
    }

    /// Track, start time, and when the deadline actually falls.
    ///
    /// The kicker counts down — "due in 19 min" — which tells you the pressure
    /// but not the appointment. Printing that same countdown here twice made a
    /// reader hunt for a difference between two identical strings; printing the
    /// date and time instead answers the question the countdown raises.
    private var metaLine: String {
        var parts: [String] = focus.task.track.isEmpty ? [] : [store.trackLabel(focus.task.track)]
        if let slot = focus.slot { parts.append(slot.time) }
        if let stamp = deadlineStamp { parts.append(stamp) }
        return parts.joined(separator: " · ")
    }

    /// When it is due, written the shortest way that is still unambiguous:
    /// a time for today, a weekday for this week, a date beyond that. Uses the
    /// device's own clock format, so 23:59 reads as 11:59 PM where that is what
    /// people write.
    private var deadlineStamp: String? {
        guard let due = focus.task.dueAt else { return nil }
        let cal = Calendar.current
        let time = due.formatted(date: .omitted, time: .shortened)

        if cal.isDateInToday(due) { return "due \(time)" }
        if cal.isDateInTomorrow(due) { return "due tomorrow, \(time)" }
        if cal.isDateInYesterday(due) { return "was due yesterday, \(time)" }

        let days = cal.dateComponents(
            [.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: due)
        ).day ?? 0
        if (1..<7).contains(days) {
            return "due \(due.formatted(.dateTime.weekday(.abbreviated))), \(time)"
        }
        // Anything further out, and anything already past, gets a real date —
        // "Mon" is no use when the Monday in question has gone.
        return "due \(due.formatted(.dateTime.day().month(.abbreviated))), \(time)"
    }
}

/// A thin filled bar. Shape and fill only — the palette has one ink, so
/// progress cannot be signalled by going a different colour.
struct ProgressBar: View {
    let value: Double
    @Environment(\.book) private var book

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(book.recessed)
                Capsule()
                    .fill(book.fill)
                    .frame(width: max(2, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
    }
}

/// "3 of 7 done" as a ring. Sits beside the date.
struct ProgressRing: View {
    let done: Int
    let total: Int

    @Environment(\.book) private var book

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    var body: some View {
        HStack(spacing: Space.md) {
            Text("\(done) of \(total) done")
                .font(BookType.meta(11))
                .foregroundStyle(book.inkSub)
            ZStack {
                Circle()
                    .strokeBorder(book.rule, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(book.fill, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))   // start at twelve o'clock
                    .padding(1)
            }
            .frame(width: 18, height: 18)
            .animation(.easeOut(duration: 0.3), value: fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) done")
    }
}
