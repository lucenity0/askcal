//
//  EntryRow.swift
//  Askcal
//
//  One line written on the page.
//
//  The tick sits in the margin, left of the rule, because that is what a
//  notebook margin is for: marks that belong to an entry without belonging to
//  its text. The entry itself starts where the writing starts, so a column of
//  titles shares one left edge whether or not it has been ticked.
//

import SwiftUI

/// The check mark, sized for the margin.
///
/// Separate from `SquareCheckbox`, whose 44×44 frame is wider than the margin
/// band and would push every entry's text out of alignment.
///
/// The drawn box is small, but the *hit area* is the whole margin band — the
/// full reach from the spine to where the writing starts. That space is dead
/// otherwise, and spending it here is what keeps the target close to 44×44
/// without a 26pt checkbox shoving the text off its left edge.
struct EntryMark: View {
    let checked: Bool
    let action: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.mark)
                    .strokeBorder(checked ? book.fill : book.inkSub,
                                  lineWidth: Stroke.strong)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.mark)
                            .fill(checked ? book.fill : .clear)
                    )
                    .frame(width: 19, height: 19)
                if checked {
                    Image(systemName: "checkmark")
                        .font(BookType.icon(10, weight: .semibold))
                        .foregroundStyle(book.fillText)
                }
            }
            .frame(width: Space.markColumn, height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EntryRow: View {
    let task: AskcalTask
    var toggle: () -> Void
    var tap: () -> Void

    @Environment(\.book) private var book

    private var done: Bool { task.status == .done }

    /// Track, deadline and estimate, in that order — the measured facts, so
    /// mono, so they line up down the column.
    private var metaLine: String {
        var parts: [String] = [task.track.rawValue]
        if let deadline = task.deadlineLabel, !deadline.isEmpty { parts.append(deadline) }
        if let hours = task.estimatedHours { parts.append("\(hours.formatted())h") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // The frame is the full reach back into the margin, with the box
            // itself at its leading edge. That way the mark sits clear to the
            // left of the rule and the text resumes exactly on the text inset,
            // sharing its left edge with every other line on the page.
            EntryMark(checked: done, action: toggle)
                .frame(width: Space.markReach, alignment: .leading)
                .accessibilityLabel(task.title)
                .accessibilityValue(done ? "Done" : "Not done")
                .accessibilityHint("Marks this entry done")

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(task.title)
                    .font(BookType.entry())
                    .foregroundStyle(done ? book.inkSub : book.ink)
                    .strikethrough(done, color: book.inkSub)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metaLine)
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }
            .padding(.top, Space.lg)

            Spacer(minLength: Space.md)

            PriorityDot(band: task.priority)
                .padding(.top, Space.xl)
        }
        .padding(.bottom, Space.md)
        // reach back past the text inset so the mark lands in the margin
        .padding(.leading, -Space.markReach)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .ruled()
    }
}
