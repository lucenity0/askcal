//
//  InboxView.swift
//  Pulse
//
//  Regret-ranked triage. Swipe right = becomes a task, swipe left = tomorrow.
//  Urgency is a dot: solid high, hollow medium, none low.
//

import SwiftUI

struct InboxView: View {
    @Environment(PulseStore.self) private var store
    @Environment(\.mono) private var mono

    var body: some View {
        PageScaffold(scrollable: false) {
            PageHeader(kicker: "Needs you", title: "Inbox", icon: "tray") {
                Text("\(store.inboxEmails.count)")
                    .font(MonoType.meta(13))
                    .foregroundStyle(mono.textSecondary)
            }
            SectionUnderline()
        } content: {
            if store.inboxEmails.isEmpty {
                Spacer()
                Text("inbox quiet. enjoy it.")
                    .font(MonoType.body(14))
                    .foregroundStyle(mono.textSecondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(store.inboxEmails) { email in
                        EmailRow(email: email)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(mono.border)
                            .listRowInsets(EdgeInsets(top: 10, leading: 22, bottom: 10, trailing: 22))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { store.handleEmail(email) }
                                } label: {
                                    Label("to today", systemImage: "checkmark")
                                }
                                .tint(mono.swipeConfirm)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { store.snoozeEmail(email) }
                                } label: {
                                    Label("tomorrow", systemImage: "arrow.uturn.right")
                                }
                                .tint(mono.swipeSnooze)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await store.syncInbox() }
            }
        }
    }
}

private struct EmailRow: View {
    let email: EmailItem
    @Environment(\.mono) private var mono

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(email.subject ?? "(no subject)")
                    .font(MonoType.item())
                    .foregroundStyle(mono.textPrimary)
                    .lineLimit(2)
                if let snippet = email.snippet {
                    Text(snippet)
                        .font(MonoType.body())
                        .foregroundStyle(mono.textSecondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let sender = email.sender {
                        Text(sender)
                    }
                    if let mins = email.estimatedMinutes {
                        Text("~\(mins)m")
                    }
                }
                .font(MonoType.meta(10))
                .foregroundStyle(mono.textSecondary.opacity(0.8))
            }
            Spacer()
            PriorityDot(band: email.priority)
                .padding(.top, 6)
        }
    }
}
