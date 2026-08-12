//
//  ReviewView.swift
//  Askcal
//
//  The evening ritual, 30 seconds max: done, or moved to tomorrow.
//  Tomorrow's carried-forward work is born here.
//

import SwiftUI

struct ReviewView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        NotebookPage {
            PageTitle(kicker: "End of day", title: "Review") {
                StreakDots(count: store.streak)
            }

            if store.dayClosed {
                closedNote
            } else if store.openTasks.isEmpty {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("clean slate. nothing to review.")
                        .font(BookType.body(15))
                        .foregroundStyle(book.inkSub)
                    RuledFiller()
                }
            } else {
                rollCall
            }
        }
    }

    private var closedNote: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("day closed. see you tomorrow.")
                .font(BookType.entry())
                .foregroundStyle(book.ink)
            Text(store.reviewSummary)
                .font(BookType.meta())
                .foregroundStyle(book.inkSub)
            if store.streak > 1 {
                Text("\(store.streak) days in a row.")
                    .font(BookType.meta())
                    .foregroundStyle(book.inkSub)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card)
                .fill(book.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .strokeBorder(book.rule, lineWidth: Stroke.hair)
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var rollCall: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(spacing: 0) {
                ForEach(store.openTasks) { task in
                    ReviewRow(task: task)
                }
            }

            Text(store.reviewSummary)
                .font(BookType.meta())
                .foregroundStyle(book.inkSub)

            Button("Close the day") {
                withAnimation(.easeOut(duration: 0.3)) { store.closeDay() }
            }
            .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
        }
    }
}

private struct ReviewRow: View {
    let task: AskcalTask
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    private var isCarried: Bool { task.status == .carried }
    private var isDone: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(task.title)
                    .font(BookType.entry(16))
                    .foregroundStyle(book.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(task.track.title.lowercased())
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }
            Spacer(minLength: Space.md)

            // Done is the same square used everywhere else — the round
            // StatusCircle that used to live here was a second check-off shape
            // for the same idea on a different screen.
            CheckCircle(checked: isDone) {
                withAnimation(.easeOut(duration: 0.2)) { store.review(task, done: true) }
            }
            .accessibilityLabel("\(task.title), done")

            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.review(task, done: false) }
            } label: {
                Text("→ tmrw")
                    .font(BookType.meta(11))
                    .foregroundStyle(isCarried ? book.fillText : book.inkSub)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .background(Capsule().fill(isCarried ? book.fill : .clear))
                    .overlay(Capsule().strokeBorder(
                        isCarried ? .clear : book.rule, lineWidth: Stroke.hair))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title), move to tomorrow")
        }
        .padding(.vertical, Space.lg)
        .ruled()
    }
}

/// Quiet streak indicator — up to 7 dots, then just the number.
struct StreakDots: View {
    let count: Int
    @Environment(\.book) private var book

    var body: some View {
        if count > 0 {
            HStack(spacing: Space.xs) {
                ForEach(0..<min(count, 7), id: \.self) { _ in
                    Circle().fill(book.fill).frame(width: 5, height: 5)
                }
                Text("×\(count)")
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(count) day streak")
        }
    }
}
