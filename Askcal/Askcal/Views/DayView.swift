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
    @Environment(\.book) private var book

    @Binding var showComposer: Bool
    /// Set to edit an existing entry. Distinct from `showComposer`, which opens
    /// a blank one — tapping a task used to raise the blank sheet, offering to
    /// create an unrelated task instead of editing the one you touched.
    @Binding var editingTask: AskcalTask?
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
            VStack(alignment: .leading, spacing: Space.section) {
                header

                if !store.isLive {
                    connectCard
                }

                if let error = store.actionError {
                    actionNote(error)
                }

                if store.isBootstrapping {
                    // Only the entries wait on the fetch. Gating the whole
                    // surface meant a slow cold start (20s timeout) showed
                    // nothing but grey bars — and a task added in that window
                    // was invisible even when it had saved.
                    MonoSkeletonRows(rows: 4)
                } else {
                    if let error = store.syncError {
                        errorNote(error)
                    }
                    nowSection
                    scheduleSection
                }

                inboxRow
                routineRow
                tracksRow
                closeRow
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.md)
            .padding(.bottom, Space.fabClearance)
        }
        .background(book.paper)
        .refreshable { await store.syncInbox() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(dateKicker)
                    .font(BookType.kicker())
                    .foregroundStyle(book.inkSub)
                Text(dateTitle)
                    .font(BookType.display(34))
                    .foregroundStyle(book.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            HStack(spacing: Space.lg) {
                NavigationLink { CalendarView() } label: {
                    Image(systemName: "calendar")
                        .font(BookType.icon(17))
                        .foregroundStyle(book.ink)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .accessibilityLabel("Calendar")

                NavigationLink { MoreView() } label: {
                    Image(systemName: "ellipsis")
                        .font(BookType.icon(17))
                        .foregroundStyle(book.ink)
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
        VStack(alignment: .leading, spacing: Space.md) {
            Text("not connected")
                .font(BookType.kicker(11))
                .foregroundStyle(book.inkSub)
            Text("tasks live on this device only. connect gmail and askcal starts ranking what actually matters.")
                .font(BookType.body(13))
                .foregroundStyle(book.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect Gmail") { onConnect() }
                .buttonStyle(PillButtonStyle(filled: true))
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

    private func errorNote(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(message)
                .font(BookType.body(12))
                .foregroundStyle(book.inkDim)
            Button("Try again") {
                Task { await store.refreshAll() }
            }
            .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    /// A write that failed. Separate from `errorNote` because there is nothing
    /// to retry — the change has already been rolled back, and the only useful
    /// thing is to say what went wrong and get out of the way.
    private func actionNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Text(message)
                .font(BookType.body(12))
                .foregroundStyle(book.inkDim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { store.dismissActionError() }
            } label: {
                Image(systemName: "xmark")
                    .font(BookType.icon(11))
                    .foregroundStyle(book.inkSub)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.block)
                .fill(book.recessed)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.block)
                        .strokeBorder(book.rule, lineWidth: Stroke.hair)
                )
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Now

    @ViewBuilder
    private var nowSection: some View {
        if let focus = store.focus {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel(focus.kicker)
                Button {
                    editingTask = focus.task
                } label: {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        Text(focus.task.title)
                            .font(BookType.entry(17))
                            .foregroundStyle(book.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: Space.sm) {
                            PriorityDot(band: focus.task.priority)
                            Text(metaLine(for: focus.task))
                                .font(BookType.meta())
                                .foregroundStyle(book.inkSub)
                        }
                    }
                    .padding(Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(book.ink, lineWidth: Stroke.strong)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu { entryActions(for: focus.task) }
                .accessibilityHint("Opens this task for editing")
            }
        } else if store.openTasks.isEmpty {
            VStack(alignment: .leading, spacing: Space.md) {
                SectionLabel("now")
                Text(store.isLive
                     ? "nothing on. rare — enjoy it."
                     : "nothing here yet. the + adds your first.")
                    .font(BookType.body(13))
                    .foregroundStyle(book.inkSub)
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
        // The focus task already has the card above; listing it again here made
        // the same item appear twice on one screen.
        let focusId = store.focus?.task.id
        let groups = store.groupedSchedule
            .map { (part: $0.part, tasks: $0.tasks.filter { $0.id != focusId }) }
            .filter { !$0.tasks.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: Space.lg) {
                SectionLabel("schedule")
                ForEach(groups, id: \.part) { group in
                    VStack(alignment: .leading, spacing: Space.md) {
                        Text(group.part.rawValue.lowercased())
                            .font(BookType.meta(10))
                            .foregroundStyle(book.inkSub)
                        ForEach(group.tasks) { task in
                            TaskRow(task: task) { store.toggleDone(task) }
                                .contentShape(Rectangle())
                                .onTapGesture { editingTask = task }
                                .contextMenu { entryActions(for: task) }
                        }
                    }
                }
            }
        }
    }

    /// Edit and delete, on long-press. These rows aren't in a `List`, so
    /// `.swipeActions` isn't available — a context menu is the affordance that
    /// works in a plain stack.
    @ViewBuilder
    private func entryActions(for task: AskcalTask) -> some View {
        Button {
            editingTask = task
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            withAnimation(.easeOut(duration: 0.2)) { store.deleteTask(task) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Shared pieces

/// A small caps label that opens a section.
struct SectionLabel: View {
    let text: String
    @Environment(\.book) private var book

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(BookType.meta(10))
            .tracking(1.2)
            .foregroundStyle(book.inkSub)
    }
}

/// "Inbox    3 new ›" — a section that lives elsewhere, summarised here so the
/// count is visible without the trip.
struct SummaryRow: View {
    let title: String
    let value: String
    @Environment(\.book) private var book

    var body: some View {
        HStack {
            Text(title)
                .font(BookType.entry())
                .foregroundStyle(book.ink)
            Spacer()
            Text(value)
                .font(BookType.meta())
                .foregroundStyle(book.inkSub)
            Image(systemName: "chevron.right")
                .font(BookType.icon(11))
                .foregroundStyle(book.inkSub)
        }
        .padding(.vertical, Space.lg)
        .overlay(alignment: .top) {
            Rectangle().fill(book.rule).frame(height: Stroke.hair)
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
    @Environment(\.book) private var book

    var body: some View {
        HStack(alignment: .top, spacing: Space.lg) {
            SquareCheckbox(checked: task.status == .done, action: toggle)
            .accessibilityLabel(task.title)
            .accessibilityValue(task.status == .done ? "Done" : "Not done")
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: Space.hair) {
                Text(task.title)
                    .font(BookType.entry(14))
                    .foregroundStyle(task.status == .done ? book.inkSub : book.ink)
                    .strikethrough(task.status == .done, color: book.inkSub)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = task.deadlineLabel, !label.isEmpty {
                    Text(label)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
            }
            Spacer(minLength: 0)
            PriorityDot(band: task.priority)
                .padding(.top, Space.xs)
        }
        .padding(.vertical, Space.md)
    }
}
