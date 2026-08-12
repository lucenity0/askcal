//
//  TodayPage.swift
//  Askcal
//
//  The day: which day, what now, what's on it, and closing it.
//
//  Reads top to bottom in the order the day gets answered — pick the day, see
//  what you're meant to be on, work the list, close it. Inbox, Tracks and
//  Calendar are not on this page at all: they used to sit underneath the
//  entries, which meant adding a task pushed them further down the screen and
//  the day never had a settled shape. They are tabs now.
//

import SwiftUI

struct TodayPage: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var composing: ComposerIntent?
    var onConnect: () -> Void
    var onOpenReview: () -> Void
    var onOpenDigest: (DigestKind) -> Void

    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var loaded: AskcalStore.DayData?
    /// Which day `loaded` actually holds. Without it the page cannot tell
    /// "yesterday, still loading" from "yesterday, genuinely empty", and shows
    /// the empty copy for a beat before the real entries arrive — the flash.
    @State private var loadedDay: String?
    /// What is actually on screen. The single source of truth for the list, so
    /// it can be left alone while the next day loads.
    @State private var displayed: [AskcalTask] = []
    @State private var marked: Set<String> = []

    private var isLoadingDay: Bool {
        !isToday && loadedDay != AskcalStore.dayString(selected)
    }

    /// Changes only when the visible week does. Marks used to reload on every
    /// change to the task count, so writing a task down fired a network request
    /// and re-laid out the strip underneath you.
    private var weekKey: Date {
        cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
    }

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(selected) }

    /// Today reads live from the store so a tick lands immediately; other days
    /// come from their fetched copy. Both include completed work — a task that
    /// vanishes the moment you tick it looks like the checkbox deleted it.
    ///
    /// While a different day is loading, today's entries stay on screen. This is
    /// the case the first flicker fix missed: leaving today swapped a populated
    /// list for an empty one in the same frame, so the page emptied and refilled
    /// even though the previous content was still perfectly good to look at.
    private var entries: [AskcalTask] { displayed }

    private var doneCount: Int {
        entries.filter { $0.status == .done }.count
    }

    /// Only today pulls to refresh — a past day has nothing new to fetch, and
    /// the gesture promising otherwise would be a lie.
    private var refreshAction: (() async -> Void)? {
        guard isToday else { return nil }
        return { await store.syncInbox() }
    }

    var body: some View {
        NotebookPage(onRefresh: refreshAction) {
            WeekStrip(selected: $selected, marked: marked)
            header
            todayOnlyTop
            timeline
            addRow
            endOfDay
        }
        // The blocks that only exist on today — the connect card, the
        // now-working card, the end-of-day card — appear and disappear as
        // `isToday` flips. Without this they pop in and out in a single frame
        // and the whole page jumps under your thumb, which is the blink that
        // survived two attempts at fixing the *list*: the list was never the
        // part that was flashing.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: isToday)
        .task(id: selected) { await load() }
        .task(id: weekKey) { await loadMarks() }
        // Today is live: a tick has to land immediately. This is also what
        // keeps today's list in `displayed` at the moment you leave it, which
        // is what the previous fix got wrong — it captured inside load(), by
        // which point isToday was already false and today's entries were gone.
        .onChange(of: store.dayEntries) { _, latest in
            if isToday { displayed = latest }
        }
    }

    private var header: some View {
        PageTitle(
            kicker: selected.formatted(.dateTime.weekday(.wide)),
            title: selected.formatted(.dateTime.month(.wide).day())
        ) {
            Button { onOpenDigest(isToday ? .morning : .evening) } label: {
                ProgressRing(done: doneCount, total: entries.count)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the day's summary")
        }
    }

    @ViewBuilder
    private var todayOnlyTop: some View {
        if isToday {
            if !store.isLive { connectCard }
            if let error = store.actionError { actionNote(error) }
            if let focus = store.focus {
                FocusCard(
                    focus: focus,
                    companion: store.companion,
                    open: { composing = .edit(focus.task) }
                )
            }
        }
    }

    private var addRow: some View {
        AddTaskRow(
            onAdd: { store.quickAdd(title: $0, scheduledAt: startOfSelected) },
            // Carries the line already typed into the composer. Reaching for
            // the date button used to hand you an empty field and make you
            // write it again.
            onExpand: { typed in
                composing = .new(title: typed, day: startOfSelected)
            }
        )
    }

    @ViewBuilder
    private var endOfDay: some View {
        if isToday {
            EndOfDayCard(
                closed: store.dayClosed,
                summary: store.reviewSummary,
                onReview: onOpenReview,
                onClose: { withAnimation(.easeOut(duration: 0.3)) { store.closeDay() } }
            )
        }
    }

    // MARK: - The day's entries

    @ViewBuilder
    private var timeline: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Rubric(isToday ? "today" : selected.formatted(.dateTime.weekday(.wide)))

            if (isToday && store.isBootstrapping) || (isLoadingDay && entries.isEmpty) {
                // The empty copy is true only once the fetch is done. Rendering
                // it mid-flight told the user their day was clear before we had
                // looked.
                SkeletonRows(rows: 4)
            } else if entries.isEmpty {
                Text(emptyLine)
                    .font(BookType.body(15))
                    .foregroundStyle(book.inkSub)
                    .padding(.vertical, Space.md)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, task in
                        TimelineRow(
                            task: task,
                            time: store.slot(for: task)?.time ?? pinnedTime(task),
                            isFirst: index == 0,
                            isLast: index == entries.count - 1,
                            toggle: {
                                withAnimation(.easeOut(duration: 0.2)) { store.toggleDone(task) }
                            },
                            edit: { composing = .edit(task) },
                            delete: {
                                withAnimation(.easeOut(duration: 0.2)) { store.deleteTask(task) }
                            }
                        )
                    }
                }
            }
        }
    }

    private var emptyLine: String {
        if !isToday { return "nothing written on this day." }
        return store.isLive ? "nothing on. rare — enjoy it." : "nothing here yet. write the first line."
    }

    /// A task with a pinned start but no plan slot still knows its own time.
    private func pinnedTime(_ task: AskcalTask) -> String? {
        guard let at = task.scheduledAt else { return nil }
        return at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
    }

    // MARK: - Connect / errors

    /// Shown until Gmail is connected. Signed out, Askcal stores tasks locally
    /// and nothing else works — no ranking, no auto-tasking — so this is the
    /// only honest thing to put near the top of the day.
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

    /// A write that failed. Nothing to retry — the change has already rolled
    /// back, so the only useful thing is to say what happened and get out of
    /// the way.
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

    // MARK: - Loading

    private var startOfSelected: Date {
        // Keep the current wall-clock time when adding to today, so a quick
        // add lands "now" rather than at midnight; other days start at 09:00.
        isToday ? .now : (cal.date(bySettingHour: 9, minute: 0, second: 0, of: selected) ?? selected)
    }


    /// Loads the selected day, leaving whatever is on screen in place until the
    /// new day is actually in hand. Blanking first and filling afterwards is
    /// what made every date change flicker.
    private func load() async {
        guard !isToday else {
            loaded = nil
            loadedDay = AskcalStore.dayString(selected)
            displayed = store.dayEntries
            return
        }
        let day = selected
        // `displayed` is deliberately left alone: whatever is on screen stays
        // there until the new day is in hand.
        let data = await store.dayData(for: day)
        // The day can change again while this is in flight — a second tap on
        // the strip — and the slower answer must not overwrite the newer one.
        guard day == selected else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            loaded = data
            displayed = data.tasks
            loadedDay = AskcalStore.dayString(day)
        }
    }

    /// Which days of the visible week have anything on them, for the strip's
    /// dots. One request per week rather than one per day.
    private func loadMarks() async {
        guard let week = cal.dateInterval(of: .weekOfYear, for: selected) else { return }
        let end = cal.date(byAdding: .day, value: -1, to: week.end) ?? week.end
        let found = await store.marks(from: week.start, to: end)
        marked = Set(found.filter { $0.value.hasTasks }.keys)
    }
}
