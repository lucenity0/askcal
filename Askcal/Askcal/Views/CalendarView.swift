//
//  CalendarView.swift
//  Askcal
//
//  Day / Month / Year views in the same monochrome language.
//  Day: Askcal task blocks (plain surface cards) overlaid with external
//  calendar blocks (diagonal hairline hatching); conflicts render
//  side-by-side with an "overlaps" marker.
//  Month: grid with solid dot = tasks, hollow dot = calendar events.
//  Year: twelve mini-months; tap one to open it.
//  Mock data only — the real Google sync builds against this scaffold.
//

import SwiftUI

enum CalViewMode: String, CaseIterable {
    case day = "Day"
    case month = "Month"
    case year = "Year"
}

struct CalendarView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.mono) private var mono

    @State private var mode: CalViewMode = .day
    @State private var displayedMonth: Date = .now
    @State private var displayedYear: Int = Calendar.current.component(.year, from: .now)
    @State private var selectedDate: Date = .now
    @State private var dayTasks: [AskcalTask] = []
    @State private var dayEvents: [CalendarEvent] = []
    @State private var editingTask: AskcalTask?

    private let pxPerMin: CGFloat = 1.05
    private let gutter: CGFloat = 50

    private var isToday: Bool { cal.isDateInToday(selectedDate) }

    // The visible window is 08:00–22:00 but stretches (to whole hours) when
    // real blocks fall outside it — a 07:00 lecture or 23:00 call must render
    // inside the timeline, never at a negative offset over the header.
    private var dayStartMin: Int {
        let earliest = allBlocks.map(\.startMin).min() ?? 8 * 60
        return min(8 * 60, (earliest / 60) * 60)
    }

    private var dayEndMin: Int {
        let latest = allBlocks.map(\.endMin).max() ?? 22 * 60
        return max(22 * 60, Int(ceil(Double(latest) / 60)) * 60)
    }

    private var cal: Calendar { Calendar.current }

    var body: some View {
        PageScaffold(scrollable: false) {
            PageHeader(kicker: kicker, title: "Calendar", icon: "calendar")
            SectionUnderline()
            HStack {
                modeSwitcher
                Spacer()
                if mode == .day { legend }
            }
        } content: {
            switch mode {
            case .day: daySection
            case .month: monthView
            case .year: yearView
            }
        }
        .task(id: selectedDate) { await loadSelectedDay() }
        .sheet(item: $editingTask) { task in
            TaskComposerSheet(editing: task)
                .environment(\.mono, mono)
                .onDisappear { Task { await loadSelectedDay() } }
        }
    }

    // Today reads straight from the store so new tasks appear immediately;
    // other days use the on-demand fetch cached in dayTasks/dayEvents.
    private var activeTasks: [AskcalTask] { isToday ? store.scheduledTasks : dayTasks }
    private var activeEvents: [CalendarEvent] { isToday ? store.calendarEvents : dayEvents }

    private func loadSelectedDay() async {
        guard !isToday else { return }
        let data = await store.loadDay(selectedDate)
        dayTasks = data.tasks
        dayEvents = data.events
    }

    private var kicker: String {
        switch mode {
        case .day: return isToday ? "Your day, mapped" : selectedDate.formatted(.dateTime.weekday(.wide))
        case .month: return "The month ahead"
        case .year: return "The long view"
        }
    }

    // MARK: - Mode switcher

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(CalViewMode.allCases, id: \.rawValue) { m in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(MonoType.meta(10))
                        .lineLimit(1)
                        .fixedSize() // "Month" must never wrap to "Mont/h"
                        .foregroundStyle(mode == m ? mono.fillText : mono.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(mode == m ? mono.fill : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().strokeBorder(mono.border, lineWidth: 1))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(mono.border, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(mono.surface))
                    .frame(width: 16, height: 11)
                Text("askcal")
            }
            HStack(spacing: 5) {
                DiagonalHatch(spacing: 4)
                    .stroke(mono.textSecondary.opacity(0.6), lineWidth: 0.7)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(mono.border, lineWidth: 1))
                    .frame(width: 16, height: 11)
                Text("calendar")
            }
        }
        .font(MonoType.meta(9))
        .foregroundStyle(mono.textSecondary)
    }

    // MARK: - Day view (nav + timeline + anytime list)

    private var daySection: some View {
        VStack(spacing: 0) {
            dayNav
            ScrollView(showsIndicators: false) {
                GeometryReader { geo in
                    timeline(width: geo.size.width)
                }
                .frame(height: CGFloat(dayEndMin - dayStartMin) * pxPerMin)
                .padding(.horizontal, 22)
                .padding(.top, 6)

                if !anytimeTasks.isEmpty {
                    anytimeSection
                        .padding(.horizontal, 22)
                        .padding(.top, 10)
                }

                if activeTasks.isEmpty && activeEvents.isEmpty {
                    Text(isToday ? "nothing scheduled today."
                                 : "nothing scheduled this day.")
                        .font(MonoType.body(14))
                        .foregroundStyle(mono.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.bottom, 100)
        }
    }

    private var dayNav: some View {
        HStack(spacing: 8) {
            navButton("chevron.left") { shiftDay(-1) }
            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(MonoType.item(13))
                    .foregroundStyle(mono.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !isToday {
                    Button("jump to today") {
                        withAnimation(.easeOut(duration: 0.2)) { selectedDate = .now }
                    }
                    .font(MonoType.meta(9))
                    .foregroundStyle(mono.textSecondary)
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 4)
            navButton("chevron.right") { shiftDay(1) }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var anytimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ANYTIME")
                .font(MonoType.kicker(10))
                .foregroundStyle(mono.textSecondary)
            ForEach(anytimeTasks) { task in
                Button { editingTask = task } label: {
                    HStack(spacing: 10) {
                        PriorityDot(band: task.priority)
                        Text(task.title)
                            .font(MonoType.item(13))
                            .foregroundStyle(mono.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if let d = task.deadlineLabel {
                            Text(d).font(MonoType.meta(9)).foregroundStyle(mono.textSecondary)
                        }
                    }
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                Divider().overlay(mono.border)
            }
        }
    }

    private func shiftDay(_ delta: Int) {
        if let next = cal.date(byAdding: .day, value: delta, to: selectedDate) {
            withAnimation(.easeOut(duration: 0.18)) { selectedDate = next }
        }
    }

    private func timeline(width: CGFloat) -> some View {
        let contentWidth = width - gutter
        let columnGap: CGFloat = 4
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: dayStartMin, through: dayEndMin, by: 60)), id: \.self) { minute in
                HStack(spacing: 8) {
                    Text(String(format: "%02d:00", minute / 60))
                        .font(MonoType.meta(10))
                        .foregroundStyle(mono.textSecondary.opacity(0.8))
                        .frame(width: gutter - 8, alignment: .trailing)
                    Rectangle()
                        .fill(mono.border)
                        .frame(height: 1)
                }
                .offset(y: y(for: minute) - 6)
            }

            ForEach(positionedBlocks) { positioned in
                let cols = CGFloat(positioned.colCount)
                let blockWidth = (contentWidth - columnGap * (cols - 1)) / cols
                Group {
                    switch positioned.block.kind {
                    case .task(let task):
                        Button { editingTask = task } label: {
                            TaskBlockView(block: positioned.block)
                        }
                        .buttonStyle(.plain)
                    case .event:
                        EventBlockView(block: positioned.block)
                    }
                }
                .frame(width: blockWidth,
                       height: positioned.block.height(pxPerMin: pxPerMin))
                .offset(
                    x: gutter + CGFloat(positioned.col) * (blockWidth + columnGap),
                    y: y(for: positioned.block.startMin)
                )
            }
        }
    }

    private func y(for minute: Int) -> CGFloat {
        CGFloat(minute - dayStartMin) * pxPerMin
    }

    // MARK: - Month view

    private var monthView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                monthNav
                weekdayHeader
                monthGrid(for: displayedMonth)
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
    }

    private var monthNav: some View {
        HStack(spacing: 8) {
            navButton("chevron.left") { shiftMonth(-1) }
            Spacer(minLength: 4)
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(MonoType.item(14))
                .foregroundStyle(mono.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            navButton("chevron.right") { shiftMonth(1) }
        }
    }

    private var weekdayHeader: some View {
        let symbols = orderedWeekdaySymbols()
        return HStack(spacing: 4) {
            ForEach(symbols, id: \.self) { s in
                Text(s)
                    .font(MonoType.meta(9))
                    .foregroundStyle(mono.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(for month: Date) -> some View {
        let days = daysInMonth(month)
        let blanks = leadingBlanks(month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(0..<blanks, id: \.self) { _ in
                Color.clear.frame(height: 42)
            }
            ForEach(1...days, id: \.self) { day in
                monthDayCell(day: day, month: month)
            }
        }
    }

    private func monthDayCell(day: Int, month: Date) -> some View {
        let date = dateFor(day: day, in: month)
        let today = date.map { cal.isDateInToday($0) } ?? false
        let selected = date.map { cal.isDate($0, inSameDayAs: selectedDate) } ?? false
        return Button {
            // tap any day → open its timeline
            if let date {
                withAnimation(.easeOut(duration: 0.2)) {
                    selectedDate = date
                    mode = .day
                }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if today {
                        Circle().fill(mono.fill).frame(width: 27, height: 27)
                    } else if selected {
                        Circle().strokeBorder(mono.fill, lineWidth: 1.5).frame(width: 27, height: 27)
                    }
                    Text("\(day)")
                        .font(MonoType.meta(12))
                        .foregroundStyle(today ? mono.fillText : mono.textPrimary)
                }
                .frame(height: 27)
                HStack(spacing: 3) {
                    if today && !store.scheduledTasks.isEmpty {
                        Circle().fill(mono.fill).frame(width: 4, height: 4)
                    }
                    if today && !store.calendarEvents.isEmpty {
                        Circle().strokeBorder(mono.fill, lineWidth: 1).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 5)
            }
            .frame(height: 42)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Year view

    private var yearView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    navButton("chevron.left") { displayedYear -= 1 }
                    Spacer(minLength: 4)
                    Text(String(displayedYear))
                        .font(MonoType.item(14))
                        .foregroundStyle(mono.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    navButton("chevron.right") { displayedYear += 1 }
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(1...12, id: \.self) { monthNum in
                        miniMonth(monthNum)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
    }

    private func miniMonth(_ monthNum: Int) -> some View {
        let month = cal.date(from: DateComponents(year: displayedYear, month: monthNum, day: 1)) ?? .now
        let days = daysInMonth(month)
        let blanks = leadingBlanks(month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                displayedMonth = month
                mode = .month
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(month.formatted(.dateTime.month(.abbreviated)))
                    .font(MonoType.item(12))
                    .foregroundStyle(mono.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(0..<blanks, id: \.self) { _ in
                        Color.clear.frame(height: 4)
                    }
                    ForEach(1...days, id: \.self) { day in
                        let isToday = dateFor(day: day, in: month)
                            .map { cal.isDateInToday($0) } ?? false
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isToday ? mono.fill : mono.surface)
                            .frame(height: 4)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(mono.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date helpers

    private func navButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(mono.textPrimary)
                .frame(width: 34, height: 34)
                .background(Circle().strokeBorder(mono.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.easeOut(duration: 0.18)) { displayedMonth = next }
        }
    }

    private func daysInMonth(_ month: Date) -> Int {
        cal.range(of: .day, in: .month, for: month)?.count ?? 30
    }

    private func leadingBlanks(_ month: Date) -> Int {
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return 0 }
        let weekday = cal.component(.weekday, from: first)
        return (weekday - cal.firstWeekday + 7) % 7
    }

    private func dateFor(day: Int, in month: Date) -> Date? {
        var comps = cal.dateComponents([.year, .month], from: month)
        comps.day = day
        return cal.date(from: comps)
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    // MARK: - Day-view block building

    struct DayBlock: Identifiable {
        enum Kind {
            case task(AskcalTask)
            case event(CalendarEvent)
        }

        let id: String
        let kind: Kind
        let title: String
        let startMin: Int
        let endMin: Int
        var conflicted = false

        func height(pxPerMin: CGFloat) -> CGFloat {
            max(CGFloat(endMin - startMin) * pxPerMin - 4, 30)
        }

        func overlaps(_ other: DayBlock) -> Bool {
            startMin < other.endMin && other.startMin < endMin
        }
    }

    /// A block placed into a column: `col` of `colCount` side-by-side slots.
    struct PositionedBlock: Identifiable {
        let block: DayBlock
        let col: Int
        let colCount: Int
        var id: String { block.id }
    }

    /// The task's start minute on the timeline: today's auto-scheduled slot if
    /// present, else a user-pinned time. Untimed tasks return nil → they land
    /// in the "anytime" list instead of the timeline.
    private func startMinute(for task: AskcalTask) -> Int? {
        if isToday, let slot = store.slot(for: task) {
            return minutesSinceMidnight(slot.time)
        }
        if let at = task.scheduledAt {
            let c = cal.dateComponents([.hour, .minute], from: at)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        return nil
    }

    private func durationMinutes(for task: AskcalTask) -> Int {
        if isToday, let slot = store.slot(for: task) { return slot.duration }
        return max(Int((task.estimatedHours ?? 1.0) * 60), 30)
    }

    private var taskBlocks: [DayBlock] {
        activeTasks.compactMap { task in
            guard let start = startMinute(for: task) else { return nil }
            return DayBlock(
                id: "task-\(task.id)",
                kind: .task(task),
                title: task.title,
                startMin: start,
                endMin: start + durationMinutes(for: task)
            )
        }
    }

    private var anytimeTasks: [AskcalTask] {
        activeTasks.filter { startMinute(for: $0) == nil }
    }

    private var eventBlocks: [DayBlock] {
        activeEvents.compactMap { event in
            guard let start = minutesSinceMidnight(event.start),
                  let end = minutesSinceMidnight(event.end) else { return nil }
            return DayBlock(
                id: "event-\(event.id)",
                kind: .event(event),
                title: event.title,
                startMin: start,
                endMin: end
            )
        }
    }

    private var allBlocks: [DayBlock] {
        taskBlocks + eventBlocks
    }

    /// Column-pack every overlapping run (tasks and events alike). Blocks that
    /// share a time window are grouped into a cluster and greedily assigned to
    /// the fewest columns that keep them non-overlapping — handling task↔event,
    /// event↔event, and 3+ concurrent items uniformly. Single blocks stay
    /// full-width.
    private var positionedBlocks: [PositionedBlock] {
        let blocks = allBlocks.sorted {
            $0.startMin != $1.startMin ? $0.startMin < $1.startMin : $0.endMin < $1.endMin
        }
        guard !blocks.isEmpty else { return [] }

        var result: [PositionedBlock] = []

        func flush(_ group: [DayBlock]) {
            guard !group.isEmpty else { return }
            var columnEnds: [Int] = []   // last end-minute placed in each column
            var cols: [Int] = []
            for b in group {
                if let free = columnEnds.firstIndex(where: { $0 <= b.startMin }) {
                    columnEnds[free] = b.endMin
                    cols.append(free)
                } else {
                    columnEnds.append(b.endMin)
                    cols.append(columnEnds.count - 1)
                }
            }
            let colCount = columnEnds.count
            for (b, col) in zip(group, cols) {
                var block = b
                block.conflicted = colCount > 1
                result.append(PositionedBlock(block: block, col: col, colCount: colCount))
            }
        }

        // sweep blocks into maximal connected overlap clusters
        var cluster: [DayBlock] = []
        var clusterEnd = Int.min
        for b in blocks {
            if cluster.isEmpty || b.startMin < clusterEnd {
                cluster.append(b)
                clusterEnd = max(clusterEnd, b.endMin)
            } else {
                flush(cluster)
                cluster = [b]
                clusterEnd = b.endMin
            }
        }
        flush(cluster)
        return result
    }
}

// MARK: - Block views

private struct TaskBlockView: View {
    let block: CalendarView.DayBlock
    @Environment(\.mono) private var mono

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 6) {
                Text(block.title)
                    .font(MonoType.item(12))
                    .foregroundStyle(mono.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if case .task(let task) = block.kind {
                    PriorityDot(band: task.priority)
                }
            }
            Text(metaLine)
                .font(MonoType.meta(9))
                .foregroundStyle(mono.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(mono.surface)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(mono.border, lineWidth: 1))
        )
    }

    private var metaLine: String {
        let time = "\(timeString(block.startMin))–\(timeString(block.endMin))"
        return block.conflicted ? "\(time) · overlaps" : time
    }
}

private struct EventBlockView: View {
    let block: CalendarView.DayBlock
    @Environment(\.mono) private var mono

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(block.title)
                .font(MonoType.item(11))
                .foregroundStyle(mono.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(mono.bg.opacity(0.9)))
            Text(metaLine)
                .font(MonoType.meta(8))
                .foregroundStyle(mono.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(mono.bg.opacity(0.9)))
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                DiagonalHatch(spacing: 5)
                    .stroke(mono.textSecondary.opacity(0.45), lineWidth: 0.7)
                if block.conflicted {
                    HStack(spacing: 0) {
                        Rectangle().fill(mono.fill).frame(width: 3)
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(mono.border, lineWidth: 1)
        )
    }

    private var metaLine: String {
        let time = "\(timeString(block.startMin))–\(timeString(block.endMin))"
        return block.conflicted ? "\(time) · overlaps" : time
    }
}

private func timeString(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

// MARK: - Hatch pattern

struct DiagonalHatch: Shape {
    var spacing: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}
