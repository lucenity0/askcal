//
//  DayPage.swift
//  Askcal
//
//  One day, written on one page.
//
//  The daily loop is triage → plan → close, and Tracks, Routine and Calendar
//  are reference material that was competing for top billing with the thing you
//  actually open the app to do. So the day is the screen, and everything else is
//  a drill-down reached from the row that summarises it — you see "3 new"
//  without going to the inbox, and you go there only when that number means
//  something.
//
//  This takes a date rather than reading `Date.now`, which is what lets the
//  pager hand it yesterday and tomorrow. Today's page is the live one: it shows
//  what needs answering now and the rows that lead elsewhere. Other days are
//  simply what is written on them — there is no "now" on a page that isn't
//  today, and an inbox count on last Tuesday would be a lie.
//

import SwiftUI

struct DayPage: View {
    let date: Date
    @Binding var showComposer: Bool
    @Binding var editingTask: AskcalTask?
    var onConnect: () -> Void
    var onStep: (Int) -> Void
    /// Where a summary row sends you. The page doesn't know whether that means
    /// a push or the facing page of a spread, and doesn't need to.
    var onOpen: (PageDestination) -> Void
    /// Whether this is the page on screen. Neighbouring pages are built ahead
    /// of being scrolled to, and without this every one of them puts its own
    /// chevrons and entries into the accessibility tree — VoiceOver reads three
    /// days at once, and "next day" stops referring to anything in particular.
    var isCurrent: Bool = true

    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @State private var loaded: AskcalStore.DayData?
    @State private var isAddingRoutine = false

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var kicker: String {
        date.formatted(.dateTime.month(.wide).day())
    }

    private var title: String {
        let day = Calendar.current.component(.day, from: date)
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        return String(format: "%02d.%@", day, weekday)
    }

    /// Today reads from the live store; other days from their fetched copy.
    private var entries: [AskcalTask] {
        isToday ? store.scheduledTasks : (loaded?.tasks ?? [])
    }

    /// Only today pulls to refresh — a past day has nothing new to fetch, and
    /// the gesture promising otherwise would be a lie.
    private var refreshAction: (() async -> Void)? {
        guard isToday else { return nil }
        return { await store.syncInbox() }
    }

    var body: some View {
        NotebookPage(onRefresh: refreshAction) {
            header
            topNotes
            entriesSection
            if isToday { destinations }
        }
        .accessibilityHidden(!isCurrent)
        .task(id: date) {
            guard !isToday else { return }
            loaded = await store.dayData(for: date)
        }
    }

    @ViewBuilder
    private var topNotes: some View {
        if isToday {
            if !store.isLive { connectCard }
            if let error = store.actionError { actionNote(error) }
            if let error = store.syncError, !store.isBootstrapping { syncNote(error) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            PageTitle(kicker: kicker, title: title) {
                HStack(spacing: Space.md) {
                    headerButton("calendar", destination: .calendar)
                    headerButton("ellipsis", destination: .settings)
                }
            }

            // Swiping pages the day, but a swipe is unreachable under VoiceOver
            // and unwelcome under Reduce Motion, so these are always here rather
            // than being a fallback that only some people get.
            HStack(spacing: Space.lg) {
                stepButton("chevron.left", label: "Previous day", step: -1)
                stepButton("chevron.right", label: "Next day", step: 1)
                if !isToday {
                    Button("Today") { onStep(0) }
                        .font(BookType.meta(11))
                        .foregroundStyle(book.inkDim)
                        .padding(.leading, Space.xs)
                }
                Spacer()
            }
        }
    }

    private func headerButton(_ symbol: String, destination: PageDestination) -> some View {
        Button { onOpen(destination) } label: {
            Image(systemName: symbol)
                .font(BookType.icon(17))
                .foregroundStyle(book.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
    }

    private func stepButton(_ symbol: String, label: String, step: Int) -> some View {
        Button { onStep(step) } label: {
            Image(systemName: symbol)
                .font(BookType.icon(12))
                .foregroundStyle(book.inkDim)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Notes at the top of the page

    /// Shown until Gmail is connected. Signed out, Askcal stores tasks locally
    /// and nothing else works — no ranking, no auto-tasking — so this is the
    /// only honest thing to put at the top of the page.
    private var connectCard: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Rubric("not connected")
            Text("tasks live on this device only. connect gmail and askcal starts ranking what actually matters.")
                .font(BookType.body(14))
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

    /// A read that failed — there is something to retry.
    private func syncNote(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(message)
                .font(BookType.body(13))
                .foregroundStyle(book.inkDim)
            Button("Try again") { Task { await store.refreshAll() } }
                .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    /// A write that failed. Nothing to retry — the change has already been
    /// rolled back, so the only useful thing is to say what happened and then
    /// get out of the way.
    private func actionNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Space.lg) {
            Text(message)
                .font(BookType.body(13))
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
    }

    // MARK: - What's written on the day

    @ViewBuilder
    private var entriesSection: some View {
        if isToday && store.isBootstrapping {
            // The empty copy is good and it is true only once the fetch is
            // done. Rendering it mid-flight told the user their day was clear
            // before we had looked.
            SkeletonRows(rows: 4)
        } else if entries.isEmpty {
            VStack(alignment: .leading, spacing: Space.lg) {
                Text(emptyLine)
                    .font(BookType.body(15))
                    .foregroundStyle(book.inkSub)
                RuledFiller()
            }
        } else {
            VStack(alignment: .leading, spacing: Space.lg) {
                ForEach(groups, id: \.part) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        if groups.count > 1 {
                            Rubric(group.part.rawValue)
                                .padding(.bottom, Space.md)
                        }
                        ForEach(group.tasks) { task in
                            EntryRow(
                                task: task,
                                toggle: { withAnimation(.easeOut(duration: 0.2)) { store.toggleDone(task) } },
                                tap: { editingTask = task }
                            )
                            .contextMenu { entryActions(for: task) }
                        }
                    }
                }
                RuledFiller()
            }
        }
    }

    private var emptyLine: String {
        if !isToday { return "nothing written on this day." }
        return store.isLive ? "nothing on. rare — enjoy it." : "nothing here yet. the + adds your first."
    }

    /// Today groups by time of day because the plan has slots; other days are
    /// just a list, so grouping them would invent a structure that isn't there.
    private var groups: [(part: DayPart, tasks: [AskcalTask])] {
        isToday ? store.groupedSchedule : [(.anytime, entries)]
    }

    /// Edit and delete, on long press. These rows aren't in a `List`, so
    /// `.swipeActions` isn't available — a context menu is what works in a
    /// plain stack.
    @ViewBuilder
    private func entryActions(for task: AskcalTask) -> some View {
        Button { editingTask = task } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button(role: .destructive) {
            withAnimation(.easeOut(duration: 0.2)) { store.deleteTask(task) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Rows that lead elsewhere

    private var destinations: some View {
        VStack(spacing: 0) {
            summaryRow(.inbox, title: "Inbox",
                       value: store.inboxEmails.isEmpty
                           ? "clear" : "\(store.inboxEmails.count) new")

            summaryRow(.routine, title: "Routine",
                       value: store.routines.isEmpty
                           ? "none set"
                           : "\(store.routinesDone.count) of \(store.routines.count)")

            summaryRow(.tracks, title: "Tracks", value: "\(store.openTasks.count) open")

            summaryRow(.review,
                       title: store.dayClosed ? "Day closed" : "Close the day",
                       value: store.dayClosed ? "done" : "")
        }
    }

    private func summaryRow(
        _ destination: PageDestination, title: String, value: String
    ) -> some View {
        Button { onOpen(destination) } label: {
            SummaryRow(title: title, value: value)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared pieces

/// "Inbox    3 new ›" — a section that lives elsewhere, summarised here so the
/// count is visible without the trip.
struct SummaryRow: View {
    let title: String
    let value: String
    @Environment(\.book) private var book

    var body: some View {
        HStack {
            Text(title)
                .font(BookType.entry(16))
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
        .contentShape(Rectangle())
        .ruled()
        // `.combine` glued the title and its count into one label — "Tracks 0
        // open" — so the row could not be identified by what it is. Title and
        // count are a label and a value, which is also how VoiceOver wants them.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Opens \(title)")
    }
}
