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
        VStack(alignment: .leading, spacing: Space.lg) {
            HStack(spacing: Space.md) {
                Rubric(focus.kicker)
                Spacer(minLength: Space.md)
                if let remaining = remainingLabel {
                    Text(remaining)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
            }

            HStack(alignment: .center, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text(focus.task.title)
                        .font(BookType.entry(20))
                        .foregroundStyle(book.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let progress = liveProgress {
                        ProgressBar(value: progress)
                    }

                    Text(metaLine)
                        .font(BookType.meta(11))
                        .foregroundStyle(book.inkSub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)

                // No check here. Completing is what the timeline row below is
                // for, and a card whose job is "what now" should not be
                // offering to make itself disappear. The space goes to the
                // companion instead, which is the only thing in the app that
                // moves when nothing is happening.
                PixelSprite(motif: companion, size: 56)
            }
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

    private var remainingLabel: String? {
        guard let slot = focus.slot, let start = slot.start(on: .now) else { return nil }
        let end = start.addingTimeInterval(Double(slot.duration) * 60)
        let left = Int(end.timeIntervalSinceNow / 60)
        guard left > 0 else { return nil }
        return left >= 60 ? "\(left / 60)h \(left % 60)m left" : "\(left) min left"
    }

    private var metaLine: String {
        var parts: [String] = focus.task.track.isEmpty ? [] : [store.trackLabel(focus.task.track)]
        if let slot = focus.slot { parts.append(slot.time) }
        if let deadline = focus.task.deadlineLabel, !deadline.isEmpty {
            parts.append(deadline)
        }
        return parts.joined(separator: " · ")
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
