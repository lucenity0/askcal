//
//  ReviewSheet.swift
//  Askcal
//
//  The evening ritual, 30 seconds max: done, or moved to tomorrow.
//
//  A popup rather than a full page. Closing the day is a handful of decisions
//  about a handful of tasks; as a sheet it was a whole screen with three lines
//  at the top and a foot of blank paper underneath, which made a 30-second
//  ritual look like a chore. Same glass as the composer and an opened mail, so
//  every modal in the app behaves the same way.
//

import SwiftUI

struct ReviewSheet: View {
    var onClose: () -> Void

    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        PopupHeader(kicker: "End of day",
                    title: store.dayClosed ? "Day closed" : "Review",
                    onClose: onClose)

        if store.dayClosed {
            closed
        } else if store.openTasks.isEmpty {
            Text("clean slate. nothing to review.")
                .font(BookType.body(15))
                .foregroundStyle(book.inkSub)
        } else {
            rollCall
        }
    }

    private var closed: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text(store.reviewSummary)
                .font(BookType.body(15))
                .foregroundStyle(book.inkDim)
            if store.streak > 1 {
                HStack(spacing: Space.md) {
                    StreakDots(count: store.streak)
                    Text("days in a row")
                        .font(BookType.meta(11))
                        .foregroundStyle(book.inkSub)
                }
            }
            Button("Done", action: onClose)
                .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
        }
    }

    private var rollCall: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(spacing: 0) {
                ForEach(store.openTasks) { task in
                    ReviewRow(task: task)
                }
            }

            VStack(alignment: .leading, spacing: Space.md) {
                Text(store.reviewSummary)
                    .font(BookType.meta(11))
                    .foregroundStyle(book.inkSub)
                Button("Close the day") {
                    withAnimation(.easeOut(duration: 0.3)) { store.closeDay() }
                }
                .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
            }
        }
    }
}

/// One task, and the only two things you can say about it tonight.
///
/// Both answers sit together under the title rather than a check floating in
/// the middle of the row with a pill beyond it — they are a pair of choices
/// about the same task, and they should look like one.
private struct ReviewRow: View {
    let task: AskcalTask
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(task.title)
                    .font(BookType.entry(16))
                    .foregroundStyle(book.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.trackLabel(task.track).lowercased())
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }

            HStack(spacing: Space.md) {
                choice("Done", filled: task.status == .done) {
                    withAnimation(.easeOut(duration: 0.2)) { store.review(task, done: true) }
                }
                choice("Tomorrow", filled: task.status == .carried) {
                    withAnimation(.easeOut(duration: 0.2)) { store.review(task, done: false) }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Space.lg)
        .ruled()
    }

    private func choice(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(BookType.meta(11))
                .foregroundStyle(filled ? book.fillText : book.inkDim)
                .padding(.horizontal, Space.lg)
                .padding(.vertical, Space.sm)
                .background(Capsule().fill(filled ? book.fill : .clear))
                .overlay(Capsule().strokeBorder(filled ? .clear : book.rule,
                                                lineWidth: Stroke.hair))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title), \(label)")
        .accessibilityAddTraits(filled ? [.isButton, .isSelected] : .isButton)
    }
}

/// Quiet streak indicator — up to 7 dots, then the number.
struct StreakDots: View {
    let count: Int
    @Environment(\.book) private var book

    var body: some View {
        if count > 0 {
            HStack(spacing: Space.xs) {
                ForEach(0..<min(count, 7), id: \.self) { _ in
                    Circle().fill(book.fill).frame(width: 5, height: 5)
                }
                if count > 7 {
                    Text("×\(count)")
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) day streak")
        }
    }
}
