//
//  InboxView.swift
//  Askcal
//
//  Triage, grouped by what each mail wants from you.
//
//  A flat list sorted by consequence is technically ordered and reads as
//  scattered: the ranking is real but invisible, so every row asks for the same
//  attention and you read all of them. Reply needed, has a deadline, read when
//  free, nothing to do — that is the only question you are actually asking, and
//  it makes the page scannable in one glance.
//
//  The band is decided server-side from signals the classifier already
//  produces, so the app and the auto-tasker cannot end up disagreeing about
//  what a piece of mail is.
//

import SwiftUI

struct InboxView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @Binding var opened: EmailItem?

    var body: some View {
        NotebookPage(onRefresh: { await store.syncInbox() }) {
            PageTitle(kicker: "Needs you", title: "Inbox") {
                Text("\(store.inboxEmails.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.inkSub)
            }

            if store.inboxEmails.isEmpty {
                empty
            } else {
                ForEach(MailNeed.allCases) { band in
                    section(band)
                }
            }
        }
    }

    /// One band. Empty ones are omitted entirely rather than shown with a zero
    /// — a heading over nothing is noise on a page whose job is to be scannable.
    @ViewBuilder
    private func section(_ band: MailNeed) -> some View {
        let mine = store.inboxEmails.filter { $0.needs == band }
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Rubric(band.title)
                    Text(band.note)
                        .font(BookType.meta(9))
                        .foregroundStyle(book.inkSub)
                    Spacer()
                    Text("\(mine.count)")
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
                VStack(spacing: 0) {
                    ForEach(mine) { email in
                        EmailRow(email: email, dimmed: band == .none) {
                            opened = email
                        }
                    }
                }
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
}

private struct EmailRow: View {
    let email: EmailItem
    var dimmed: Bool
    var open: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: Space.lg) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(email.subject ?? "(no subject)")
                        .font(BookType.entry(16))
                        .foregroundStyle(dimmed ? book.inkSub : book.ink)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    Text(senderLine)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.md)
                PriorityDot(band: email.priority)
                    .padding(.top, Space.sm)
            }
            .padding(.vertical, Space.lg)
            .contentShape(Rectangle())
            .ruled()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(email.subject ?? "No subject")
        .accessibilityHint("Opens this mail")
    }

    private var senderLine: String {
        let who = email.sender ?? "unknown"
        let when = email.receivedAt.formatted(.relative(presentation: .named))
        return "\(who) · \(when)"
    }
}

/// The opened mail, over a blurred inbox.
struct EmailDetail: View {
    let email: EmailItem
    var makeTask: () -> Void
    var snooze: () -> Void
    var onClose: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        PopupHeader(kicker: bandTitle,
                    title: email.subject ?? "(no subject)",
                    onClose: onClose)

        if let snippet = email.snippet {
            Text(snippet)
                .font(BookType.body(15))
                .foregroundStyle(book.inkDim)
                .fixedSize(horizontal: false, vertical: true)
        }

        // What the classifier actually concluded. The dot in the list is this,
        // reduced to one mark — worth seeing in full before acting on it.
        VStack(spacing: 0) {
            ForEach(facts, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                    Spacer()
                    Text(value)
                        .font(BookType.meta(11))
                        .foregroundStyle(book.inkDim)
                }
                .padding(.vertical, Space.md)
                .ruled()
            }
        }

        HStack(spacing: Space.lg) {
            Button("Make a task", action: makeTask)
                .buttonStyle(PillButtonStyle(filled: true))
            Button("Tomorrow", action: snooze)
                .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    private var bandTitle: String { email.needs.title }

    /// Only what the API actually returns. An unranked mail says so rather than
    /// showing a fabricated zero — with the classifier off everything is
    /// unranked, and that is worth being able to see from here.
    private var facts: [(String, String)] {
        var out: [(String, String)] = [
            ("from", email.sender ?? "unknown"),
            ("arrived", email.receivedAt.formatted(date: .abbreviated, time: .shortened)),
        ]
        if let track = email.track { out.append(("track", track.title)) }
        out.append(("ranked", email.regretScore.map { "\($0) / 100" } ?? "not yet"))
        if let minutes = email.estimatedMinutes { out.append(("takes", "about \(minutes) min")) }
        return out
    }
}
