//
//  DayView.swift
//  Askcal
//
//  The app, on one surface.
//
//  This replaces a seven-destination rail. The daily loop is triage → plan →
//  close, and Tracks, Routine and Calendar are reference material that was
//  competing for top billing with the thing you actually open the app to do.
//  So the day is the screen, and everything else is a drill-down reached from
//  the row that summarises it — you see "3 new" without going to the inbox,
//  and you go there only when that number means something.
//
//  Sections read top to bottom in the order the day is answered: what now,
//  what's waiting, what's scheduled, what's habitual, and then closing it.
//

import SwiftUI

struct DayView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.mono) private var mono

    @Binding var showComposer: Bool
    var onConnect: () -> Void

    @State private var isAddingRoutine = false

    private var dateKicker: String {
        Date.now.formatted(.dateTime.month(.wide).day())
    }

    private var dateTitle: String {
        let day = Calendar.current.component(.day, from: .now)
        let weekday = Date.now.formatted(.dateTime.weekday(.abbreviated))
        return String(format: "%02d.%@", day, weekday)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MonoSpace.section) {
                header

                if !store.isLive {
                    connectCard
                }

                if store.isBootstrapping {
                    // The empty states are good copy and they are true only
                    // once the fetch is done. Rendering them mid-flight told
                    // the user their inbox was quiet before we had looked.
                    MonoSkeletonRows(rows: 4)
                } else {
                    if let error = store.syncError {
                        errorNote(error)
                    }
                    nowSection
                    inboxRow
                    scheduleSection
                    routineRow
                    tracksRow
                    closeRow
                }
            }
            .padding(.horizontal, MonoSpace.gutter)
            .padding(.top, MonoSpace.md)
            .padding(.bottom, MonoSpace.fabClearance)
        }
        .background(mono.paper)
        .refreshable { await store.syncInbox() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: MonoSpace.hair) {
                Text(dateKicker)
                    .font(MonoType.kicker())
                    .foregroundStyle(mono.inkSub)
                Text(dateTitle)
                    .font(MonoType.title(34))
                    .foregroundStyle(mono.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            HStack(spacing: MonoSpace.lg) {
                NavigationLink { CalendarView() } label: {
                    Image(systemName: "calendar")
                        .font(MonoType.icon(17))
                        .foregroundStyle(mono.ink)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .accessibilityLabel("Calendar")

                NavigationLink { MoreView() } label: {
                    Image(systemName: "ellipsis")
                        .font(MonoType.icon(17))
                        .foregroundStyle(mono.ink)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .accessibilityLabel("Settings")
            }
        }
    }

    // MARK: - Connect

    /// Shown until Gmail is connected. Signed out, Askcal stores tasks locally
    /// and nothing else works — no ranking, no auto-tasking — so this is the
    /// only honest thing to put at the top of the screen.
    private var connectCard: some View {
        VStack(alignment: .leading, spacing: MonoSpace.md) {
            Text("not connected")
                .font(MonoType.kicker(11))
                .foregroundStyle(mono.inkSub)
            Text("tasks live on this device only. connect gmail and askcal starts ranking what actually matters.")
                .font(MonoType.body(13))
                .foregroundStyle(mono.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect Gmail") { onConnect() }
                .buttonStyle(PillButtonStyle(filled: true))
        }
        .padding(MonoSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: MonoRadius.card)
                .fill(mono.card)
                .overlay(
                    RoundedRectangle(cornerRadius: MonoRadius.card)
                        .strokeBorder(mono.rule, lineWidth: MonoStroke.hair)
                )
        )
    }

    private func errorNote(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: MonoSpace.sm) {
            Text(message)
                .font(MonoType.body(12))
                .foregroundStyle(mono.inkDim)
            Button("Try again") {
                Task { await store.refreshAll() }
            }
            .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    // MARK: - Now

    @ViewBuilder
    private var nowSection: some View {
        if let focus = store.focus {
            VStack(alignment: .leading, spacing: MonoSpace.md) {
                SectionLabel(focus.kicker)
                Button {
                    showComposer = true
                } label: {
                    VStack(alignment: .leading, spacing: MonoSpace.sm) {
                        Text(focus.task.title)
                            .font(MonoType.item(17))
                            .foregroundStyle(mono.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: MonoSpace.sm) {
                            PriorityDot(band: focus.task.priority)
                            Text(metaLine(for: focus.task))
                                .font(MonoType.meta())
                                .foregroundStyle(mono.inkSub)
                        }
                    }
                    .padding(MonoSpace.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: MonoRadius.card)
                            .strokeBorder(mono.ink, lineWidth: MonoStroke.strong)
                    )
                }
                .buttonStyle(.plain)
            }
        } else if store.openTasks.isEmpty {
            VStack(alignment: .leading, spacing: MonoSpace.md) {
                SectionLabel("now")
                Text(store.isLive
                     ? "nothing on. rare — enjoy it."
                     : "nothing here yet. the + adds your first.")
                    .font(MonoType.body(13))
                    .foregroundStyle(mono.inkSub)
            }
        }
    }

    private func metaLine(for task: AskcalTask) -> String {
        var parts: [String] = [task.track.rawValue]
        if let d = task.deadlineLabel, !d.isEmpty { parts.append(d) }
        if let h = task.estimatedHours { parts.append("\(h.formatted())h") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Rows that summarise a drill-down

    private var inboxRow: some View {
        NavigationLink { InboxView() } label: {
            SummaryRow(
                title: "Inbox",
                value: store.inboxEmails.isEmpty
                    ? "clear"
                    : "\(store.inboxEmails.count) new"
            )
        }
        .buttonStyle(.plain)
    }

    private var routineRow: some View {
        NavigationLink { RoutineView(isAdding: $isAddingRoutine) } label: {
            SummaryRow(
                title: "Routine",
                value: store.routines.isEmpty
                    ? "none set"
                    : "\(store.routinesDone.count) of \(store.routines.count)"
            )
        }
        .buttonStyle(.plain)
    }

    private var tracksRow: some View {
        NavigationLink { TracksView() } label: {
            SummaryRow(title: "Tracks", value: "\(store.openTasks.count) open")
        }
        .buttonStyle(.plain)
    }

    private var closeRow: some View {
        NavigationLink { ReviewView() } label: {
            SummaryRow(
                title: store.dayClosed ? "Day closed" : "Close the day",
                value: store.dayClosed ? "done" : ""
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule

    @ViewBuilder
    private var scheduleSection: some View {
        let groups = store.groupedSchedule.filter { !$0.tasks.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: MonoSpace.lg) {
                SectionLabel("schedule")
                ForEach(groups, id: \.part) { group in
                    VStack(alignment: .leading, spacing: MonoSpace.md) {
                        Text(group.part.rawValue.lowercased())
                            .font(MonoType.meta(10))
                            .foregroundStyle(mono.inkSub)
                        ForEach(group.tasks) { task in
                            TaskRow(task: task) { store.toggleDone(task) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Shared pieces

/// A small caps label that opens a section.
struct SectionLabel: View {
    let text: String
    @Environment(\.mono) private var mono

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(MonoType.meta(10))
            .tracking(1.2)
            .foregroundStyle(mono.inkSub)
    }
}

/// "Inbox    3 new ›" — a section that lives elsewhere, summarised here so the
/// count is visible without the trip.
struct SummaryRow: View {
    let title: String
    let value: String
    @Environment(\.mono) private var mono

    var body: some View {
        HStack {
            Text(title)
                .font(MonoType.item())
                .foregroundStyle(mono.ink)
            Spacer()
            Text(value)
                .font(MonoType.meta())
                .foregroundStyle(mono.inkSub)
            Image(systemName: "chevron.right")
                .font(MonoType.icon(11))
                .foregroundStyle(mono.inkSub)
        }
        .padding(.vertical, MonoSpace.lg)
        .overlay(alignment: .top) {
            Rectangle().fill(mono.rule).frame(height: MonoStroke.hair)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }
}

/// One scheduled task: checkbox, title, meta.
struct TaskRow: View {
    let task: AskcalTask
    let toggle: () -> Void
    @Environment(\.mono) private var mono

    var body: some View {
        HStack(alignment: .top, spacing: MonoSpace.lg) {
            SquareCheckbox(checked: task.status == .done, action: toggle)
            .accessibilityLabel(task.title)
            .accessibilityValue(task.status == .done ? "Done" : "Not done")
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: MonoSpace.hair) {
                Text(task.title)
                    .font(MonoType.item(14))
                    .foregroundStyle(task.status == .done ? mono.inkSub : mono.ink)
                    .strikethrough(task.status == .done, color: mono.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = task.deadlineLabel, !label.isEmpty {
                    Text(label)
                        .font(MonoType.meta(10))
                        .foregroundStyle(mono.inkSub)
                }
            }
            Spacer(minLength: 0)
            PriorityDot(band: task.priority)
                .padding(.top, MonoSpace.xs)
        }
        .padding(.vertical, MonoSpace.md)
    }
}
