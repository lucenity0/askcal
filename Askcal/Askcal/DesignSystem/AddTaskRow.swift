//
//  AddTaskRow.swift
//  Askcal
//
//  Adding a task, on the page rather than behind a button.
//
//  The floating + opened a sheet with a title field, a track picker, a
//  scheduled time and a deadline — four decisions to write one line down. Most
//  entries are a line of text. So the row takes the text inline and the sheet
//  stays for when you actually want to say when.
//
//  No microphone. The reference layout had one, but the system keyboard already
//  dictates, so a second mic button would be a permission prompt and a speech
//  pipeline to do what the keyboard does.
//

import SwiftUI

struct AddTaskRow: View {
    /// Called with the typed title when the row is submitted.
    var onAdd: (String) -> Void
    /// Called when the user wants the full composer instead.
    var onExpand: () -> Void

    @Environment(\.book) private var book
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.lg) {
            Image(systemName: "plus")
                .font(BookType.icon(15))
                .foregroundStyle(book.inkSub)

            TextField("Add task", text: $title)
                .font(BookType.entry(16))
                .foregroundStyle(book.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(submit)

            // Only offered once there is something to schedule. An empty row
            // has nothing to open the composer with.
            if !title.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: onExpand) {
                    Image(systemName: "calendar.badge.plus")
                        .font(BookType.icon(15))
                        .foregroundStyle(book.inkSub)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Set a time or deadline")
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.block)
                .strokeBorder(book.rule, style: StrokeStyle(lineWidth: Stroke.hair, dash: [4, 4]))
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func submit() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onAdd(trimmed)
        title = ""
        // Stay focused: writing a day down is usually more than one line, and
        // dismissing the keyboard after each entry makes that a chore.
        focused = true
    }
}

/// The end-of-day prompt. Sits at the bottom of the day because that is when
/// it applies.
struct EndOfDayCard: View {
    let closed: Bool
    let summary: String
    var onReview: () -> Void
    var onClose: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        HStack(alignment: .center, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(closed ? "Day closed" : "End your day")
                    .font(BookType.entry(17))
                    .foregroundStyle(book.ink)
                Text(closed ? summary : "Review, reflect and close.")
                    .font(BookType.body(13))
                    .foregroundStyle(book.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.md)

            VStack(alignment: .trailing, spacing: Space.md) {
                Button("Review day", action: onReview)
                    .buttonStyle(PillButtonStyle(filled: false))
                if !closed {
                    Button(action: onClose) {
                        HStack(spacing: Space.sm) {
                            Text("Close the day")
                            Image(systemName: "arrow.right")
                        }
                        .font(BookType.meta(11))
                        .foregroundStyle(book.inkDim)
                    }
                    .buttonStyle(.plain)
                }
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
    }
}
