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
    /// Whether the list this row belongs to reserves the time column. Decided
    /// by the list, not the row, so every mark in it lines up.
    var showsTime = false
    var isFirst = false
    var isLast = false
    var toggle: () -> Void
    var edit: () -> Void
    var delete: () -> Void

    @Environment(\.book) private var book
    @Environment(AskcalStore.self) private var store

    private var done: Bool { task.status == .done }

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            // The column is reserved for the whole list or for none of it, so
            // every mark sits at the same x. Dropping it per row let some rows
            // start at the checkbox and others 66pt further in, which is what
            // made a list of mixed rows look ragged.
            if showsTime {
                Text(time ?? "")
                    .font(BookType.meta(11))
                    .foregroundStyle(book.inkSub)
                    .lineLimit(1)
                    .frame(width: 56, alignment: .trailing)
                    // Centred against the check rather than pushed down by a
                    // guessed padding: same height as the mark's own target,
                    // so the two line up whatever the row's height turns out
                    // to be.
                    .frame(height: 44)
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
                .frame(width: Stroke.hair, height: Space.xs)

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
