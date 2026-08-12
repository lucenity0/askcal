//
//  ReviewView.swift
//  Askcal
//
//  The evening ritual, 30 seconds max: done, or moved to tomorrow.
//  Tomorrow's "Uncompleted tasks" card is born here.
//

import SwiftUI

struct ReviewView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        PageScaffold {
            PageHeader(kicker: "End of day", title: "Review") {
                StreakDots(count: store.streak)
            }
            SectionUnderline()
        } content: {
                if store.dayClosed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("day closed. see you tomorrow.")
                            .font(BookType.entry())
                            .foregroundStyle(book.textPrimary)
                        Text(store.reviewSummary)
                            .font(BookType.meta())
                            .foregroundStyle(book.textSecondary)
                        if store.streak > 1 {
                            Text("\(store.streak) days in a row.")
                                .font(BookType.meta())
                                .foregroundStyle(book.textSecondary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(book.surface)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(book.border, lineWidth: 1))
                    )
                } else if store.openTasks.isEmpty {
                    Text("clean slate. nothing to review.")
                        .font(BookType.body(14))
                        .foregroundStyle(book.textSecondary)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.openTasks) { task in
                            ReviewRow(task: task)
                            Divider().overlay(book.border)
                        }
                    }

                    Text(store.reviewSummary)
                        .font(BookType.meta())
                        .foregroundStyle(book.textSecondary)
                        .padding(.top, 4)

                    Button("Close the day") {
                        withAnimation(.easeOut(duration: 0.3)) { store.closeDay() }
                    }
                    .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
                }
        }
    }
}

private struct ReviewRow: View {
    let task: AskcalTask
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    private var isCarried: Bool { task.status == .carried }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(BookType.entry())
                    .foregroundStyle(book.textPrimary)
                Text(task.track.title.lowercased())
                    .font(BookType.meta(10))
                    .foregroundStyle(book.textSecondary)
            }
            Spacer()
            // done — circle; tomorrow — outlined chip
            StatusCircle(done: task.status == .done) {
                withAnimation(.easeOut(duration: 0.2)) { store.review(task, done: true) }
            }
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.review(task, done: false) }
            } label: {
                Text("→ tmrw")
                    .font(BookType.meta(11))
                    .foregroundStyle(isCarried ? book.fillText : book.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(isCarried ? book.fill : .clear))
                    .overlay(Capsule().strokeBorder(isCarried ? .clear : book.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
}

/// Quiet streak indicator — up to 7 dots, then just the number.
struct StreakDots: View {
    let count: Int
    @Environment(\.book) private var book

    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                ForEach(0..<min(count, 7), id: \.self) { _ in
                    Circle().fill(book.fill).frame(width: 5, height: 5)
                }
                Text("×\(count)")
                    .font(BookType.meta(10))
                    .foregroundStyle(book.textSecondary)
            }
        }
    }
}
