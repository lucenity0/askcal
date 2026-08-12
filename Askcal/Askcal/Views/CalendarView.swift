//
//  CalendarView.swift
//  Askcal
//
//  The month, and what is on the day you pick.
//
//  This replaces a Day/Month/Year switcher wrapped around a hand-drawn
//  timeline: task blocks laid out by the minute, external events hatched with
//  diagonal lines, overlap resolution, a legend explaining the hatching, and a
//  twelve-month grid behind it. Roughly five hundred lines to show a day, in a
//  visual language used nowhere else in the app — you left the day surface and
//  arrived somewhere that drew tasks as boxes instead of lines.
//
//  A calendar's job here is to answer "which day" and "what is on it". The
//  month grid answers the first, the same timeline rows the day uses answer the
//  second, and Google events sit in that list rather than in a parallel
//  notation you have to learn.
//

import SwiftUI

struct CalendarView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @State private var month: Date = .now
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var day: AskcalStore.DayData?
    /// Which day `day` holds, so "loading" and "empty" are distinguishable.
    @State private var loadedDay: String?
    @State private var marks: [String: AskcalStore.DayMarks] = [:]
    @State private var editingTask: AskcalTask?

    private var cal: Calendar { Calendar.current }
    private var isToday: Bool { cal.isDateInToday(selected) }
    private var isLoading: Bool { loadedDay != AskcalStore.dayString(selected) }

    private var entries: [AskcalTask] {
        isToday ? store.dayEntries : (day?.tasks ?? [])
    }

    private var events: [CalendarEvent] {
        isToday ? store.calendarEvents : (day?.events ?? [])
    }

    var body: some View {
        NotebookPage {
            PageTitle(kicker: "The month", title: month.formatted(.dateTime.month(.wide).year()))
            monthBlock
            dayBlock
        }
        .task(id: selected) { await loadDay() }
        .task(id: monthKey) { await loadMarks() }
        .sheet(item: $editingTask) { task in
            TaskComposerSheet(editing: task).environment(\.book, book)
        }
    }

    private var monthKey: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
    }

    // MARK: - Month

    private var monthBlock: some View {
        VStack(spacing: Space.xl) {
            HStack {
                navButton("chevron.left") { shiftMonth(-1) }
                Spacer()
                Button("Today") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        month = .now
                        selected = cal.startOfDay(for: .now)
                    }
                }
                .font(BookType.meta(11))
                .foregroundStyle(book.inkDim)
                .buttonStyle(.plain)
                Spacer()
                navButton("chevron.right") { shiftMonth(1) }
            }

            HStack(spacing: Space.xs) {
                ForEach(MonthLayout.weekdaySymbols(cal), id: \.self) { symbol in
                    Text(symbol)
                        .font(BookType.meta(9))
                        .foregroundStyle(book.inkSub)
                        .frame(maxWidth: .infinity)
                }
            }

            grid
            PageRule()
        }
    }

    private var grid: some View {
        let layout = MonthLayout(month: month, calendar: cal)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs), count: 7)
        // One flat list of slots. A run of blanks followed by a separate ForEach
        // over a runtime range makes SwiftUI drop cells rather than misplace
        // them, which is how this grid silently lost the first week of every
        // month.
        return LazyVGrid(columns: columns, spacing: Space.lg) {
            ForEach(Array(layout.slots.enumerated()), id: \.offset) { _, number in
                if let number {
                    cell(number)
                } else {
                    Color.clear.frame(height: 40)
                }
            }
        }
    }

    private func cell(_ number: Int) -> some View {
        let date = dateFor(number)
        let isSelected = date.map { cal.isDate($0, inSameDayAs: selected) } ?? false
        let today = date.map { cal.isDateInToday($0) } ?? false
        let mark = date.map { self.mark(for: $0) } ?? AskcalStore.DayMarks()

        return Button {
            guard let date else { return }
            withAnimation(.easeOut(duration: 0.2)) { selected = cal.startOfDay(for: date) }
            Haptics.tick()
        } label: {
            VStack(spacing: Space.xs) {
                ZStack {
                    if isSelected {
                        Circle().fill(book.fill).frame(width: 28, height: 28)
                    } else if today {
                        Circle().strokeBorder(book.ruleStrong, lineWidth: Stroke.hair)
                            .frame(width: 28, height: 28)
                    }
                    Text("\(number)")
                        .font(BookType.meta(12))
                        .foregroundStyle(isSelected ? book.fillText : book.ink)
                }
                .frame(height: 28)

                // Solid = work filed on that day, hollow = a calendar event.
                HStack(spacing: 3) {
                    if mark.hasTasks {
                        Circle().fill(book.inkSub).frame(width: 4, height: 4)
                    }
                    if mark.hasEvents {
                        Circle().strokeBorder(book.inkSub, lineWidth: 1)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date?.formatted(.dateTime.weekday(.wide).month(.wide).day()) ?? "\(number)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BookType.icon(12))
                .foregroundStyle(book.inkDim)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "chevron.left" ? "Previous month" : "Next month")
    }

    // MARK: - The selected day

    @ViewBuilder
    private var dayBlock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Rubric(isToday ? "today" : selected.formatted(.dateTime.weekday(.wide).month().day()))

            if isLoading && entries.isEmpty && events.isEmpty {
                SkeletonRows(rows: 3)
            } else if entries.isEmpty && events.isEmpty {
                Text("nothing on this day.")
                    .font(BookType.body(15))
                    .foregroundStyle(book.inkSub)
                    .padding(.vertical, Space.md)
            } else {
                if !events.isEmpty { eventList }
                if !entries.isEmpty { taskList }
            }
        }
    }

    /// Google events are read-only here, so they carry no check — a mark you
    /// cannot tick is worse than no mark.
    private var eventList: some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                HStack(alignment: .top, spacing: Space.lg) {
                    Text(event.start)
                        .font(BookType.meta(12))
                        .foregroundStyle(book.inkSub)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(event.title)
                            .font(BookType.entry(16))
                            .foregroundStyle(book.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(event.start)–\(event.end) · calendar")
                            .font(BookType.meta(10))
                            .foregroundStyle(book.inkSub)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.lg)
                .ruled()
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var taskList: some View {
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
                    edit: { editingTask = task },
                    delete: {
                        withAnimation(.easeOut(duration: 0.2)) { store.deleteTask(task) }
                    }
                )
            }
        }
    }

    private func pinnedTime(_ task: AskcalTask) -> String? {
        guard let at = task.scheduledAt else { return nil }
        return at.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
    }

    // MARK: - Data

    private func dateFor(_ number: Int) -> Date? {
        var parts = cal.dateComponents([.year, .month], from: month)
        parts.day = number
        return cal.date(from: parts)
    }

    /// Today's marks come from the live store, so ticking something updates the
    /// grid without a refetch.
    private func mark(for date: Date) -> AskcalStore.DayMarks {
        if cal.isDateInToday(date) {
            return .init(hasTasks: !store.dayEntries.isEmpty,
                         hasEvents: !store.calendarEvents.isEmpty)
        }
        return marks[AskcalStore.dayString(date)] ?? .init()
    }

    private func shiftMonth(_ delta: Int) {
        guard let moved = cal.date(byAdding: .month, value: delta, to: month) else { return }
        withAnimation(.easeOut(duration: 0.2)) { month = moved }
    }

    /// Leaves the previous day on screen until the next is in hand. Blanking
    /// first and filling afterwards is what made every date tap flicker.
    private func loadDay() async {
        guard !isToday else {
            day = nil
            loadedDay = AskcalStore.dayString(selected)
            return
        }
        let target = selected
        let data = await store.dayData(for: target)
        guard target == selected else { return }   // a newer tap won
        withAnimation(.easeInOut(duration: 0.18)) {
            day = data
            loadedDay = AskcalStore.dayString(target)
        }
    }

    private func loadMarks() async {
        let layout = MonthLayout(month: month, calendar: cal)
        guard let first = dateFor(1), let last = dateFor(layout.days) else { return }
        marks = await store.marks(from: first, to: last)
    }
}
