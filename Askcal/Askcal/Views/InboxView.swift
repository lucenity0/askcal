//
//  InboxView.swift
//  Askcal
//
//  Regret-ranked triage.
//
//  Rows open in place. The list used to be swipe-only, which meant deciding
//  what to do with a mail from a two-line snippet and a dot — and the dot is
//  the classifier's whole opinion compressed to one mark. Tapping unfolds what
//  it actually thought: the track it filed the mail under, how consequential it
//  scored it, how long it reckons it takes. That is the part worth seeing
//  before you turn something into a task.
//
//  The swipes stay. They are faster once you trust the ranking, and opening a
//  row is for when you don't.
//

import SwiftUI

struct InboxView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @State private var opened: String?

    var body: some View {
        NotebookPage(scrollable: false) {
            PageTitle(kicker: "Needs you", title: "Inbox") {
                Text("\(store.inboxEmails.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.inkSub)
            }

            if store.inboxEmails.isEmpty {
                empty
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(store.isLive
                 ? "inbox quiet. enjoy it."
                 : "connect gmail and your mail lands here, ranked.")
                .font(BookType.body(15))
                .foregroundStyle(book.inkSub)
            if store.isLive {
                Button("Sync now") { Task { await store.syncInbox() } }
                    .buttonStyle(PillButtonStyle(filled: false))
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.inboxEmails) { email in
                EmailRow(
                    email: email,
                    isOpen: opened == email.id,
                    toggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            opened = opened == email.id ? nil : email.id
                        }
                    },
                    makeTask: { withAnimation { store.handleEmail(email) } },
                    snooze: { withAnimation { store.snoozeEmail(email) } }
                )
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
    let isOpen: Bool
    var toggle: () -> Void
    var makeTask: () -> Void
    var snooze: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            summary
            if isOpen { detail }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .accessibilityElement(children: .contain)
        .accessibilityHint(isOpen ? "Collapses this mail" : "Opens this mail")
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(email.subject ?? "(no subject)")
                    .font(BookType.entry(16))
                    .foregroundStyle(book.ink)
                    .lineLimit(isOpen ? nil : 2)
                    .multilineTextAlignment(.leading)
                if let sender = email.sender {
                    Text(sender)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.md)
            PriorityDot(band: email.priority)
                .padding(.top, Space.sm)
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            if let snippet = email.snippet {
                Text(snippet)
                    .font(BookType.body(14))
                    .foregroundStyle(book.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // What the classifier actually concluded. The dot is this, reduced
            // to one mark — worth being able to see in full before acting on it.
            HStack(spacing: Space.lg) {
                ForEach(facts, id: \.0) { label, value in
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(label.uppercased())
                            .font(BookType.meta(9))
                            .tracking(1)
                            .foregroundStyle(book.inkSub)
                        Text(value)
                            .font(BookType.meta(11))
                            .foregroundStyle(book.inkDim)
                    }
                }
            }

            HStack(spacing: Space.lg) {
                Button("Make a task", action: makeTask)
                    .buttonStyle(PillButtonStyle(filled: true))
                Button("Tomorrow", action: snooze)
                    .buttonStyle(PillButtonStyle(filled: false))
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    /// Only what the API actually returns. An unranked mail says so rather than
    /// showing a fabricated zero — with the classifier off, everything is
    /// unranked, and that is worth being able to see from the inbox.
    private var facts: [(String, String)] {
        var out: [(String, String)] = [
            ("when", email.receivedAt.formatted(.relative(presentation: .named))),
        ]
        if let track = email.track { out.append(("track", track.title)) }
        out.append(("ranked", email.regretScore.map(String.init) ?? "not yet"))
        if let minutes = email.estimatedMinutes { out.append(("takes", "~\(minutes)m")) }
        return out
    }
}
