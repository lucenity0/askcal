//
//  TimelineRow.swift
//  Askcal
//
//  One entry on the day: its time, its mark, what it is.
//
//  The mark is a plain child of this row and nothing pulls it outside the row's
//  bounds. That matters more than it sounds: the previous design hung the
//  checkbox 48pt into the page margin using negative padding, and SwiftUI draws
//  outside a parent's frame but does not *hit-test* outside it — so every
//  checkbox in the app rendered perfectly and could not be tapped. Anything
//  that reaches beyond its container here will silently stop working again.
//
//  The rail is drawn per row rather than as one line behind the list, so it
//  cannot drift out of step with rows of different heights.
//

import SwiftUI

struct TimelineRow: View {
    let task: AskcalTask
    /// When this was finished, and nothing else. A planned time belongs to a
    /// plan that keeps changing; the one moment worth recording against a row
    /// is the moment it was done.
    var time: String?
    var isFirst = false
    var isLast = false
    var toggle: () -> Void
    var edit: () -> Void
    var delete: () -> Void

    @Environment(\.book) private var book
    @Environment(AskcalStore.self) private var store

    /// The two numbers worth touching if this still looks wrong.
    ///
    /// `timeWidth` is the gutter — wide enough for "10:30 PM" at meta(11) and
    /// no wider, because every point of it is empty space on rows that are not
    /// finished yet. `railLeadIn` must match the rectangle at the top of
    /// `rail`, or the time and the mark stop centring on each other.
    private static let timeWidth: CGFloat = 52
    private static let railLeadIn: CGFloat = Space.xs

    private var done: Bool { task.status == .done }

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            // Per row, not per list. Reserving the column for a whole day put
            // an empty gutter beside everything unfinished, to buy an alignment
            // nobody asked for — an unfinished row starting at its mark and a
            // finished one stepped in behind its time is the intended look.
            if let time {
                Text(time)
                    .font(BookType.meta(11))
                    .foregroundStyle(book.inkSub)
                    .lineLimit(1)
                    .frame(width: Self.timeWidth, alignment: .trailing)
                    // The same 44pt box the check sits in, pushed down by the
                    // same lead-in — so the two centre on each other rather
                    // than the time riding `railLeadIn` points high, which is
                    // what it did when the box started at the row's top edge.
                    .frame(height: 44)
                    .padding(.top, Self.railLeadIn)
            }

            rail

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(task.title)
                    .font(BookType.entry(17))
                    .foregroundStyle(done ? book.inkSub : book.ink)
                    .strikethrough(done, color: book.inkSub)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metaLine)
                    .font(BookType.meta(11))
                    .foregroundStyle(book.inkSub)
            }
            .padding(.top, Space.lg)
            // The gap between rows is padding on the *text*, not on the row.
            // Padding the row would sit below the rail, breaking the connecting
            // line into dashes with a gap at every entry.
            .padding(.bottom, Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)

            menu
        }
        .ruled()
    }

    /// Track, deadline and estimate — the measured facts, so mono.
    private var metaLine: String {
        // Looked up rather than derived, so a renamed track reads by its new
        // name here without every task having to be refetched.
        var parts: [String] = task.track.isEmpty ? [] : [store.trackLabel(task.track)]

        // No deadline on finished work: a countdown to something already done
        // is noise, and "overdue by 3 h" beside a ticked row is actively wrong.
        // When it was finished is not repeated here either — the time column
        // beside the mark is saying it.
        if !done, let deadline = task.deadlineLabel, !deadline.isEmpty {
            parts.append(deadline)
        }

        if let hours = task.estimatedHours { parts.append("\(hours.formatted())h") }
        return parts.joined(separator: " · ")
    }

    /// The connecting line and the check circle. The line is hidden above the
    /// first row and below the last so the rail begins and ends on a mark
    /// rather than trailing off into nothing.
    private var rail: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(isFirst ? .clear : book.rule)
                .frame(width: Stroke.hair, height: Self.railLeadIn)

            CheckCircle(checked: done, action: toggle)
                .accessibilityLabel(task.title)
                .accessibilityValue(done ? "Done" : "Not done")

            Rectangle()
                .fill(isLast ? .clear : book.rule)
                .frame(width: Stroke.hair)
                .frame(maxHeight: .infinity)
        }
        // As wide as the check's own 44pt target. A narrower rail would clip
        // the button's hit area to the rail's bounds — the same mistake that
        // stopped every checkbox in the app from working.
        .frame(width: 44)
    }

    private var menu: some View {
        Menu {
            Button { edit() } label: { Label("Edit", systemImage: "pencil") }
            Button { toggle() } label: {
                Label(done ? "Mark not done" : "Mark done",
                      systemImage: done ? "arrow.uturn.backward" : "checkmark")
            }
            Button(role: .destructive) { delete() } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(BookType.icon(14))
                .foregroundStyle(book.inkSub)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Actions for \(task.title)")
    }
}

/// The check mark on the rail.
///
/// A circle rather than the square the app used elsewhere, because there was a
/// square checkbox on one screen and a round one on another for the same idea.
/// One shape, everywhere.
struct CheckCircle: View {
    let checked: Bool
    var size: CGFloat = 24
    let action: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(checked ? book.fill : book.ruleStrong,
                                  lineWidth: Stroke.strong)
                    .background(Circle().fill(checked ? book.fill : .clear))
                    .frame(width: size, height: size)
                if checked {
                    Image(systemName: "checkmark")
                        .font(BookType.icon(size * 0.46, weight: .semibold))
                        .foregroundStyle(book.fillText)
                }
            }
            // The whole 44pt square is tappable, but it is drawn inside the
            // row rather than reaching out of it.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

// The row is the fiddliest thing in the app to get right — a gutter, a rail, a
// tap target and wrapping text all lining up — and rebuilding onto a phone to
// look at four pixels is a terrible loop. These cover the states that actually
// disagree with each other: finished with a time, unfinished with none, and a
// title long enough to wrap past the mark.
//
// Xcode canvas: ⌥⌘↩ to show it, ⌥⌘P to refresh. Edit `timeWidth` or
// `railLeadIn` above and it redraws without a build.

private func previewTask(
    _ title: String,
    done: Bool = false,
    finishedAt: Date? = nil,
    hours: Double? = nil,
    due: Date? = nil
) -> AskcalTask {
    AskcalTask(
        id: UUID(),
        track: "uni",
        title: title,
        regretScore: 60,
        estimatedHours: hours,
        status: done ? .done : .pending,
        dueAt: due,
        completedAt: finishedAt
    )
}

private struct TimelineRowPreview: View {
    let mode: ThemeMode

    private var rows: [(AskcalTask, String?)] {
        let eight = Calendar.current.date(bySettingHour: 20, minute: 20, second: 0, of: .now)
        let nine = Calendar.current.date(bySettingHour: 21, minute: 5, second: 0, of: .now)
        return [
            (previewTask("note db error", done: true, finishedAt: eight), "8:20 PM"),
            (previewTask(
                "Week 3 Assignment Deadline Extended — One-Time Exception!",
                done: true, finishedAt: nine, hours: 0.5
            ), "9:05 PM"),
            // The row that shows the empty gutter: not finished, in a list that
            // reserves the column so every mark stays on one line.
            (previewTask(
                "Design Overdue", hours: 1,
                due: Date.now.addingTimeInterval(-3200)
            ), nil),
        ]
    }

    var body: some View {
        let book = PaperPalette.palette(for: mode)
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                TimelineRow(
                    task: row.0,
                    time: row.1,
                    isFirst: index == 0,
                    isLast: index == rows.count - 1,
                    toggle: {}, edit: {}, delete: {}
                )
            }
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(book.paper)
        .environment(\.book, book)
        .environment(AskcalStore())
    }
}

#Preview("Rows · day") { TimelineRowPreview(mode: .day) }
#Preview("Rows · night") { TimelineRowPreview(mode: .night) }
