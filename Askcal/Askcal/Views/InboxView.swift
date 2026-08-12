//
//  InboxView.swift
//  Askcal
//
//  Regret-ranked triage. Swipe right = becomes a task, swipe left = tomorrow.
//  Urgency is a dot: solid high, hollow medium, none low.
//
//  Rows are ruled like everything else, and the swipe actions come from a
//  `List` — the one place in the app that still needs one, because
//  `.swipeActions` exists nowhere else. The list is made transparent so the
//  paper underneath shows through it.
//

import SwiftUI

struct InboxView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        NotebookPage(scrollable: false) {
            PageTitle(kicker: "Needs you", title: "Inbox") {
                Text("\(store.inboxEmails.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.inkSub)
            }

            if store.inboxEmails.isEmpty {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("inbox quiet. enjoy it.")
                        .font(BookType.body(15))
                        .foregroundStyle(book.inkSub)
                    RuledFiller()
                }
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.inboxEmails) { email in
                EmailRow(email: email)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(book.rule)
                    .listRowInsets(EdgeInsets(top: Space.lg, leading: 0,
                                              bottom: Space.lg, trailing: 0))
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            withAnimation { store.handleEmail(email) }
                        } label: {
                            Label("to today", systemImage: "checkmark")
                        }
                        .tint(book.swipeConfirm)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            withAnimation { store.snoozeEmail(email) }
                        } label: {
                            Label("tomorrow", systemImage: "arrow.uturn.right")
                        }
                        .tint(book.swipeSnooze)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await store.syncInbox() }
    }
}

private struct EmailRow: View {
    let email: EmailItem
    @Environment(\.book) private var book

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(email.subject ?? "(no subject)")
                    .font(BookType.entry(16))
                    .foregroundStyle(book.ink)
                    .lineLimit(2)
                if let snippet = email.snippet {
                    Text(snippet)
                        .font(BookType.body(13))
                        .foregroundStyle(book.inkSub)
                        .lineLimit(2)
                }
                HStack(spacing: Space.md) {
                    if let sender = email.sender { Text(sender) }
                    if let mins = email.estimatedMinutes { Text("~\(mins)m") }
                }
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
            }
            Spacer(minLength: Space.md)
            PriorityDot(band: email.priority)
                .padding(.top, Space.sm)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right to make a task, left to snooze until tomorrow")
    }
}
