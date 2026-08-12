//
//  TodayView.swift
//  Askcal
//
//  The daily view: date header + week strip, focus "Now" card,
//  uncompleted-tasks card (carry-forward), grouped schedule, inline add.
//

import SwiftUI

struct TodayView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book
    @State private var showWeek = false
    @State private var selectedDate = Date.now
    @State private var otherDayTasks: [AskcalTask] = []
    @State private var loadingOtherDay = false
    @State private var editingTask: AskcalTask?

    private var isToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: .now)
    }

    private var kickerDate: String {
        selectedDate.formatted(.dateTime.month(.wide).day())
    }

    private var titleDate: String {
        let day = Calendar.current.component(.day, from: selectedDate)
        let weekday = selectedDate.formatted(.dateTime.weekday(.abbreviated))
        return String(format: "%02d.%@", day, weekday)
    }

    var body: some View {
        PageScaffold(onRefresh: { await store.syncInbox() }) {
            header
            if showWeek { WeekStrip(selectedDate: $selectedDate) }
            Text(isToday ? store.loadLine : " ")
                .font(BookType.meta())
                .foregroundStyle(book.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            SectionUnderline()
        } content: {
            if isToday {
                todayContent
            } else {
                otherDayContent
            }
        }
        .task(id: selectedDate) {
            guard !isToday else { return }
            loadingOtherDay = true
            otherDayTasks = await store.loadDay(selectedDate).tasks
            loadingOtherDay = false
        }
        .sheet(item: $editingTask) { task in
            TaskComposerSheet(editing: task)
                .environment(\.book, book)
                .onDisappear {
                    Task { otherDayTasks = await store.loadDay(selectedDate).tasks }
                }
        }
    }

    // MARK: - Header

    private var header: some View {
        PageHeader(kicker: kickerDate, title: titleDate) {
            HStack(spacing: 10) {
                if !isToday {
                    Button("TODAY") {
                        withAnimation(.easeOut(duration: 0.2)) { selectedDate = .now }
                    }
                    .buttonStyle(PillButtonStyle(filled: false))
                }
                Button {
                    withAnimation(.easeOut(duration: 0.22)) { showWeek.toggle() }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 17))
                        .foregroundStyle(showWeek ? book.fillText : book.textPrimary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(showWeek ? book.fill : .clear))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private var todayContent: some View {
        if let focus = store.focus {
            FocusCard(focus: focus)
        }

        if !store.carriedTasks.isEmpty {
            UncompletedCard()
        }

        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.groupedSchedule, id: \.part) { group in
                Text(group.part.rawValue)
                    .font(BookType.kicker(11))
                    .foregroundStyle(book.textSecondary)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(group.tasks) { task in
                        ScheduledRow(task: task, slot: store.slot(for: task)) {
                            editingTask = task
                        }
                        Divider().overlay(book.border)
                    }
                }
            }

            if store.scheduledTasks.isEmpty && store.carriedTasks.isEmpty {
                Text("nothing here yet. the + adds your first.")
                    .font(BookType.body())
                    .foregroundStyle(book.textSecondary)
                    .padding(.vertical, 24)
            }
        }
    }

    @ViewBuilder
    private var otherDayContent: some View {
        if loadingOtherDay {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if otherDayTasks.isEmpty {
            let past = selectedDate < Calendar.current.startOfDay(for: .now)
            Text(past ? "that day's closed." : "nothing scheduled here yet. tap + to plan ahead.")
                .font(BookType.body(14))
                .foregroundStyle(book.textSecondary)
                .padding(.vertical, 32)
        } else {
            VStack(spacing: 0) {
                ForEach(otherDayTasks) { task in
                    Button { editingTask = task } label: { OtherDayRow(task: task) }
                        .buttonStyle(.plain)
                    Divider().overlay(book.border)
                }
            }
        }
    }
}

private struct OtherDayRow: View {
    let task: AskcalTask
    @Environment(\.book) private var book

    private var timeLabel: String? {
        guard let at = task.scheduledAt else { return nil }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: at)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(BookType.entry())
                    .foregroundStyle(book.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let timeLabel {
                        Image(systemName: "clock").font(.system(size: 9))
                        Text(timeLabel)
                    } else {
                        Text("anytime")
                    }
                    if let d = task.deadlineLabel { Text("·  \(d)") }
                }
                .font(BookType.meta())
                .foregroundStyle(book.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            Spacer()
            PriorityDot(band: task.priority)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    @Binding var selectedDate: Date
    @Environment(\.book) private var book

    private var days: [Date] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.timeIntervalSinceReferenceDate) { day in
                let selected = Calendar.current.isDate(day, inSameDayAs: selectedDate)
                let isToday = Calendar.current.isDate(day, inSameDayAs: .now)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selectedDate = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(BookType.meta(9))
                            .foregroundStyle(selected ? book.fillText : book.textSecondary)
                        Text("\(Calendar.current.component(.day, from: day))")
                            .font(BookType.entry(13))
                            .foregroundStyle(selected ? book.fillText : book.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(selected ? book.fill : .clear)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            isToday && !selected ? book.textSecondary.opacity(0.5) : .clear,
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 100)
                .strokeBorder(book.border, lineWidth: 1)
        )
    }
}

// MARK: - Focus card

private struct FocusCard: View {
    let focus: AskcalStore.FocusInfo
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    private var timeLine: String? {
        if let slot = focus.slot { return "\(slot.time), \(slot.duration) mins" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(focus.kicker)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.textSecondary)
                        .kerning(1.0)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(focus.task.title)
                        .font(BookType.display(22))
                        .foregroundStyle(book.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                    if let timeLine {
                        HStack(spacing: 6) {
                            Image(systemName: "clock").font(.system(size: 9))
                            Text(timeLine)
                                .font(BookType.meta())
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(book.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                // idle companion — decorative only, one motif per app open.
                // Fixed bounding box, motif centered within it, never past
                // the card edge regardless of motif shape or Dynamic Type.
                PixelSprite(motif: store.companion, size: 52)
                    .frame(width: 56, height: 56)
            }

            if let progress = focus.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(book.border).frame(height: 3)
                        Capsule().fill(book.fill)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(book.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(book.fill, lineWidth: 1.5))
        )
    }
}

// MARK: - Uncompleted card

private struct UncompletedCard: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Uncompleted tasks")
                        .font(BookType.entry())
                        .foregroundStyle(book.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(book.textSecondary)
                        .rotationEffect(.degrees(expanded ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(store.carriedTasks) { task in
                    HStack {
                        Text(task.title)
                            .font(BookType.body(14))
                            .foregroundStyle(book.textPrimary)
                        Spacer()
                        StatusCircle(done: false) { store.review(task, done: true) }
                    }
                }
                Button("Reschedule to Today") {
                    withAnimation(.easeOut(duration: 0.25)) {
                        store.rescheduleAllToToday()
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
                .padding(.top, 6)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(book.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(book.border, lineWidth: 1))
        )
    }
}

// MARK: - Scheduled row

private struct ScheduledRow: View {
    let task: AskcalTask
    let slot: PlanSlot?
    var onEdit: (() -> Void)? = nil
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SquareCheckbox(checked: task.status == .done) {
                withAnimation(.easeOut(duration: 0.2)) { store.toggleDone(task) }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(BookType.entry())
                    .foregroundStyle(book.textPrimary)
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(metaLine)
                        .font(BookType.meta())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(book.textSecondary)
            }
            Spacer()
            PriorityDot(band: task.priority)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        // tap the row (not the checkbox) to reschedule / set a deadline
        .onTapGesture { onEdit?() }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let slot { parts.append(slot.time); parts.append("\(slot.duration) mins") }
        if let deadline = task.deadlineLabel { parts.append(deadline) }
        return parts.isEmpty ? task.track.title.lowercased() : parts.joined(separator: ",  ")
    }
}
