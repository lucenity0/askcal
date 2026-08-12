//
//  InboxView.swift
//  Askcal
//
//  Regret-ranked triage, in bands.
//
//  A flat list sorted by score is technically ordered and reads as scattered:
//  the ranking is real but invisible, so every row asks for the same attention
//  and you end up reading all of them. Three bands make the ranking the shape
//  of the page — the top one is short and worth your time, the bottom one you
//  can ignore in one glance.
//
//  The bands come from the score the classifier already produces. Nothing new
//  is computed here, it is just no longer hidden inside a single dot.
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
                ForEach(InboxBand.allCases) { band in
                    band.section(in: store.inboxEmails, opened: $opened)
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

/// How the inbox is divided.
///
/// The thresholds are the same ones the auto-tasker uses (`auto_task_min_regret`
/// is 25), so "worth your time" here means the same thing it means when the
/// backend decides something is a task. Two places disagreeing about what
/// counts as consequential would be worse than either threshold being wrong.
enum InboxBand: String, CaseIterable, Identifiable {
    case needsYou, worthALook, noise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsYou: return "needs you"
        case .worthALook: return "worth a look"
        case .noise: return "probably noise"
        }
    }

    var note: String {
        switch self {
        case .needsYou: return "consequences if you don't"
        case .worthALook: return "real, but not urgent"
        case .noise: return "receipts, digests, promotions"
        }
    }

    func contains(_ email: EmailItem) -> Bool {
        // An unclassified mail is not noise — nobody has looked at it yet. It
        // sits in the middle band rather than being buried, which matters most
        // when the classifier is off and *everything* is unranked.
        guard let score = email.regretScore else { return self == .worthALook }
        switch self {
        case .needsYou: return score >= 65
        case .worthALook: return score >= 25
        case .noise: return score < 25
        }
    }

    @ViewBuilder
    func section(in emails: [EmailItem], opened: Binding<EmailItem?>) -> some View {
        let mine = emails.filter(contains)
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: Space.lg) {
                HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                    Rubric(title)
                    Text(note)
                        .font(BookType.meta(9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(mine.count)")
                        .font(BookType.meta(10))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(mine) { email in
                        EmailRow(email: email, dimmed: self == .noise) {
                            opened.wrappedValue = email
                        }
                    }
                }
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

    private var bandTitle: String {
        InboxBand.allCases.first { $0.contains(email) }?.title ?? "mail"
    }

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
