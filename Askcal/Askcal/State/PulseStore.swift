//
//  AskcalStore.swift
//  Askcal
//
//  App state. Regret scoring still orders everything under the hood;
//  the UI stays quiet about it. No seed data anywhere: every collection
//  starts empty and fills from askcal-api once an account is connected.
//

import Foundation
import Observation

enum DayPart: String, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
    case anytime = "Anytime"
}

@MainActor
@Observable
final class AskcalStore {
    var tasks: [AskcalTask]
    var emails: [EmailItem]
    var dayPlan: [PlanSlot]
    var routines: [Routine]
    var calendarEvents: [CalendarEvent]
    var routinesDone: Set<UUID>
    var dayClosed = false

    /// True once a Askcal account is connected — data comes from askcal-api.
    var isLive = false
    var accountEmail: String?
    var syncError: String?

    /// Idle companion for the Up Next card — one pick per app open.
    let companion: CompanionMotif = CompanionMotif.allCases.randomElement() ?? .cat

    init(
        tasks: [AskcalTask] = [],
        emails: [EmailItem] = [],
        dayPlan: [PlanSlot] = [],
        routines: [Routine] = [],
        calendarEvents: [CalendarEvent] = []
    ) {
        self.tasks = tasks
        self.emails = emails
        self.dayPlan = dayPlan
        self.routines = routines
        self.calendarEvents = calendarEvents
        // checkmarks are day-keyed: yesterday's key never loads, so they
        // reset every morning but survive an app relaunch mid-day
        self.routinesDone = Self.loadRoutinesDone()
    }

    // MARK: - Routine checkmark persistence (device-local, resets daily)

    private static var routinesDoneKey: String { "routinesDone-\(dayString(.now))" }

    private static func loadRoutinesDone() -> Set<UUID> {
        let raw = UserDefaults.standard.stringArray(forKey: routinesDoneKey) ?? []
        return Set(raw.compactMap(UUID.init))
    }

    private func saveRoutinesDone() {
        UserDefaults.standard.set(
            routinesDone.map(\.uuidString), forKey: Self.routinesDoneKey
        )
    }

    // MARK: - Derived

    var carriedTasks: [AskcalTask] {
        tasks.filter { $0.status == .carried }
    }

    var openTasks: [AskcalTask] {
        tasks.filter { $0.status != .done }.sorted { $0.regretScore > $1.regretScore }
    }

    var scheduledTasks: [AskcalTask] {
        tasks.filter { $0.status == .pending }.sorted { $0.regretScore > $1.regretScore }
    }

    var inboxEmails: [EmailItem] {
        // score first, then recency — the recency tiebreak matters because
        // Swift's sort is unstable and equal scores reshuffled every refresh
        emails.sorted { lhs, rhs in
            let l = lhs.regretScore ?? -1
            let r = rhs.regretScore ?? -1
            if l != r { return l > r }
            return lhs.receivedAt > rhs.receivedAt
        }
    }

    /// The quiet load line: "5 things. 6h 30m planned."
    var loadLine: String {
        let count = openTasks.count
        guard count > 0 else { return "nothing on. rare — enjoy it." }
        let minutes = dayPlan.reduce(0) { $0 + $1.duration }
        let h = minutes / 60, m = minutes % 60
        let time = m == 0 ? "\(h)h" : "\(h)h \(m)m"
        return "\(count) thing\(count == 1 ? "" : "s"). \(time) planned."
    }

    func tasks(in track: TrackKey) -> [AskcalTask] {
        openTasks.filter { $0.track == track }
    }

    func task(id: UUID) -> AskcalTask? {
        tasks.first { $0.id == id }
    }

    func slot(for task: AskcalTask) -> PlanSlot? {
        dayPlan.first { $0.taskId == task.id }
    }

    // MARK: - Time-of-day grouping

    private func dayPart(of task: AskcalTask) -> DayPart {
        guard let slot = slot(for: task),
              let hour = Int(slot.time.prefix(2)) else { return .anytime }
        switch hour {
        case ..<12: return .morning
        case 12..<17: return .afternoon
        default: return .evening
        }
    }

    var groupedSchedule: [(part: DayPart, tasks: [AskcalTask])] {
        let groups = Dictionary(grouping: scheduledTasks, by: dayPart(of:))
        return DayPart.allCases.compactMap { part in
            guard let items = groups[part], !items.isEmpty else { return nil }
            return (part, items)
        }
    }

    // MARK: - Focus ("Now" card)

    struct FocusInfo: Equatable {
        let task: AskcalTask
        let slot: PlanSlot?      // present when the task is on the day plan
        let kicker: String       // "NOW" / "DUE IN 3 H" / "UP NEXT · 14:00"
        let progress: Double?    // live bar when a slot is in progress
    }

    /// The "Now" card. Priority is the closest deadline — the thing most
    /// worth surfacing — falling back to the schedule (current or next slot)
    /// when nothing has a deadline.
    var focus: FocusInfo? {
        let now = Date.now

        if let task = tasks
            .filter({ $0.status == .pending && $0.dueAt != nil })
            .min(by: { $0.dueAt! < $1.dueAt! }) {
            let s = slot(for: task)
            var progress: Double?
            if let s, let start = s.start(on: now) {
                let end = start.addingTimeInterval(Double(s.duration) * 60)
                if now >= start, now < end {
                    progress = now.timeIntervalSince(start) / end.timeIntervalSince(start)
                }
            }
            let kicker = (task.deadlineLabel ?? "due").uppercased()
            return FocusInfo(task: task, slot: s, kicker: kicker, progress: progress)
        }

        // no deadlines anywhere → schedule-driven focus
        var upcoming: (PlanSlot, Date)?
        for slot in dayPlan {
            guard let start = slot.start(on: now),
                  let task = task(id: slot.taskId), task.status == .pending else { continue }
            let end = start.addingTimeInterval(Double(slot.duration) * 60)
            if now >= start, now < end {
                let progress = now.timeIntervalSince(start) / end.timeIntervalSince(start)
                return FocusInfo(task: task, slot: slot, kicker: "NOW", progress: progress)
            }
            if start > now, upcoming == nil || start < upcoming!.1 {
                upcoming = (slot, start)
            }
        }
        if let (slot, _) = upcoming, let task = task(id: slot.taskId) {
            return FocusInfo(task: task, slot: slot, kicker: "UP NEXT · \(slot.time)", progress: nil)
        }
        return nil
    }

    // MARK: - Live sync

    /// Called once at launch — switches to live data if an account is
    /// connected, otherwise restores locally-saved offline data.
    func bootstrap() async {
        guard APIClient.shared.isConnected else {
            loadLocal()
            return
        }
        isLive = true
        accountEmail = UserDefaults.standard.string(forKey: "accountEmail")
        await APIClient.shared.syncTimezone()  // align plans to device local time
        await refreshAll()
    }

    // MARK: - Offline local persistence (not-signed-in users)

    private static let localTasksKey = "localTasks"
    private static let localRoutinesKey = "localRoutines"

    private func loadLocal() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: Self.localTasksKey),
           let t = try? JSONDecoder().decode([AskcalTask].self, from: d) { tasks = t }
        if let d = ud.data(forKey: Self.localRoutinesKey),
           let r = try? JSONDecoder().decode([Routine].self, from: d) { routines = r }
    }

    /// Persist the offline session so a rebuild/relaunch keeps it. No-op when
    /// live (the backend is the source of truth then).
    private func saveLocal() {
        guard !isLive else { return }
        let ud = UserDefaults.standard
        ud.set(try? JSONEncoder().encode(tasks), forKey: Self.localTasksKey)
        ud.set(try? JSONEncoder().encode(routines), forKey: Self.localRoutinesKey)
    }

    /// Full, irreversible wipe of the not-signed-in session's local data.
    func deleteLocalData() {
        tasks = []
        routines = []
        routinesDone = []
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.localTasksKey)
        ud.removeObject(forKey: Self.localRoutinesKey)
        ud.removeObject(forKey: Self.routinesDoneKey)
        Haptics.medium()
    }

    private func isToday(_ date: Date?) -> Bool {
        guard let date else { return true }   // nil scheduled_for = today
        return Calendar.current.isDateInToday(date)
    }

    func connected(email: String, name: String) async {
        isLive = true
        accountEmail = email
        UserDefaults.standard.set(email, forKey: "accountEmail")
        // default the greeting name from the Google account on first connect
        let existing = UserDefaults.standard.string(forKey: "userName") ?? ""
        if existing.isEmpty, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "userName")
        }
        await APIClient.shared.syncTimezone()
        await refreshAll()
    }

    func disconnect() {
        APIClient.shared.disconnect()
        UserDefaults.standard.removeObject(forKey: "accountEmail")
        isLive = false
        accountEmail = nil
        syncError = nil
        tasks = []
        emails = []
        dayPlan = []
        routines = []
        calendarEvents = []
    }

    func refreshAll() async {
        guard isLive else { return }
        do {
            async let tasksReq = APIClient.shared.tasks()
            async let todayReq = APIClient.shared.today()
            async let inboxReq = APIClient.shared.inbox()
            async let routinesReq = APIClient.shared.routines()
            tasks = try await tasksReq
            dayPlan = try await todayReq.dayPlan
            emails = try await inboxReq
            routines = try await routinesReq
            await refreshCalendar()
            syncError = nil
        } catch {
            syncError = "couldn't pull the latest. try again?"
        }
    }

    struct DayData: Equatable {
        var tasks: [AskcalTask]
        var events: [CalendarEvent]
    }

    /// Tasks + external events for a specific day — powers the calendar's
    /// per-date view and Today's date scrubber. Today is served from the
    /// already-loaded store; other days are fetched on demand.
    func loadDay(_ date: Date) async -> DayData {
        if Calendar.current.isDateInToday(date) {
            return DayData(tasks: scheduledTasks, events: calendarEvents)
        }
        guard isLive else {
            let dayTasks = tasks.filter {
                guard let d = $0.scheduledFor else { return false }
                return Calendar.current.isDate(d, inSameDayAs: date)
            }
            return DayData(tasks: dayTasks, events: [])
        }
        let dayStr = Self.dayString(date)
        async let tasksReq = APIClient.shared.tasks(on: date)
        async let eventsReq = APIClient.shared.calendarEvents(start: dayStr, end: dayStr)
        let dayTasks = (try? await tasksReq) ?? []
        let apiEvents = (try? await eventsReq) ?? []
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        let events = apiEvents.compactMap { e -> CalendarEvent? in
            guard !e.allDay, let s = e.start, let en = e.end else { return nil }
            return CalendarEvent(id: e.id, title: e.title,
                                 start: fmt.string(from: s), end: fmt.string(from: en))
        }
        return DayData(tasks: dayTasks, events: events)
    }

    private func refreshCalendar() async {
        let day = Self.dayString(.now)
        guard let apiEvents = try? await APIClient.shared.calendarEvents(start: day, end: day)
        else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        calendarEvents = apiEvents.compactMap { e in
            guard !e.allDay, let start = e.start, let end = e.end else { return nil }
            return CalendarEvent(
                id: e.id, title: e.title,
                start: formatter.string(from: start),
                end: formatter.string(from: end)
            )
        }
    }

    /// Pull-to-refresh on Inbox: trigger a Gmail sync, wait, re-fetch.
    /// The pipeline may have auto-created tasks from actionable mail, so
    /// tasks and the day plan refresh along with the inbox.
    func syncInbox() async {
        guard isLive else { return }
        try? await APIClient.shared.triggerSync()
        try? await Task.sleep(for: .seconds(6))
        if let fresh = try? await APIClient.shared.inbox() { emails = fresh }
        if let freshTasks = try? await APIClient.shared.tasks() { tasks = freshTasks }
        if let today = try? await APIClient.shared.today() { dayPlan = today.dayPlan }
    }

    // MARK: - Actions

    func toggleDone(_ task: AskcalTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].status = tasks[idx].status == .done ? .pending : .done
        if tasks[idx].status == .done { Haptics.tick() }
        pushStatus(task.id, tasks[idx].status)
        saveLocal()
    }

    func rescheduleAllToToday() {
        for idx in tasks.indices where tasks[idx].status == .carried {
            tasks[idx].status = .pending
            pushStatus(tasks[idx].id, .pending)
        }
        Haptics.medium()
    }

    private func pushStatus(_ id: UUID, _ status: TaskStatus) {
        guard isLive else { return }
        Task { _ = try? await APIClient.shared.setTaskStatus(id, status) }
    }

    func handleEmail(_ email: EmailItem) {
        emails.removeAll { $0.id == email.id }
        Haptics.tick()
        guard isLive else { return }
        Task {
            if let task = try? await APIClient.shared.handleEmail(email.id) {
                tasks.append(task)
            }
        }
    }

    func snoozeEmail(_ email: EmailItem) {
        emails.removeAll { $0.id == email.id }
        Haptics.tick()
        if isLive {
            Task { try? await APIClient.shared.snoozeEmail(email.id) }
        }
    }

    func quickAdd(
        title: String, track: TrackKey = .uni,
        scheduledAt: Date? = nil, dueAt: Date? = nil, scheduledFor: Date? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.tick()
        if isLive {
            Task {
                if let task = try? await APIClient.shared.createTask(
                    title: trimmed, track: track,
                    scheduledAt: scheduledAt, dueAt: dueAt, scheduledFor: scheduledFor
                ) {
                    // only surface it in Today if it belongs to today; either
                    // way refresh the plan so a pinned time lands on the timeline
                    if isToday(task.scheduledFor) { tasks.append(task) }
                    if let today = try? await APIClient.shared.today() {
                        dayPlan = today.dayPlan
                    }
                }
            }
        } else {
            let day = scheduledFor ?? scheduledAt
            let task = AskcalTask(
                id: UUID(), track: track, title: trimmed, meta: nil,
                regretScore: 20, estimatedHours: nil,
                scheduledFor: day, scheduledAt: scheduledAt, dueAt: dueAt
            )
            if isToday(task.scheduledFor) { tasks.append(task) }
            saveLocal()
        }
    }

    /// Shift a task's day/pinned time and/or deadline (from the edit sheet).
    func updateTaskSchedule(
        _ task: AskcalTask, scheduledAt: Date?, dueAt: Date?, scheduledFor: Date?
    ) {
        Haptics.tick()
        if isLive {
            Task {
                guard let updated = try? await APIClient.shared.updateTaskSchedule(
                    task.id, scheduledAt: scheduledAt, dueAt: dueAt, scheduledFor: scheduledFor
                ) else { return }
                if let idx = tasks.firstIndex(where: { $0.id == updated.id }) {
                    if isToday(updated.scheduledFor) { tasks[idx] = updated }
                    else { tasks.remove(at: idx) }  // moved off today → leaves the list
                }
                if let today = try? await APIClient.shared.today() { dayPlan = today.dayPlan }
            }
        } else if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            var t = task
            t.scheduledAt = scheduledAt
            t.dueAt = dueAt
            t.scheduledFor = scheduledFor ?? scheduledAt
            if isToday(t.scheduledFor) { tasks[idx] = t } else { tasks.remove(at: idx) }
            saveLocal()
        }
    }

    // MARK: - Routines

    func toggleRoutine(_ routine: Routine) {
        if routinesDone.contains(routine.id) {
            routinesDone.remove(routine.id)
        } else {
            routinesDone.insert(routine.id)
            Haptics.tick()
        }
        saveRoutinesDone()
    }

    func addRoutine(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.tick()
        if isLive {
            Task {
                if let routine = try? await APIClient.shared.createRoutine(title: trimmed) {
                    routines.append(routine)
                }
            }
        } else {
            routines.append(Routine(id: UUID(), title: trimmed, cadence: "daily"))
            saveLocal()
        }
    }

    func deleteRoutine(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        routinesDone.remove(routine.id)
        saveRoutinesDone()
        Haptics.tick()
        if isLive {
            Task { try? await APIClient.shared.deleteRoutine(routine.id) }
        } else {
            saveLocal()
        }
    }

    // MARK: - Review ritual + streak

    func review(_ task: AskcalTask, done: Bool) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[idx].status = done ? .done : .carried
        Haptics.tick()
        // review marks must survive a relaunch even if the day is never
        // formally closed — push each one, don't wait for closing time
        pushStatus(task.id, tasks[idx].status)
        saveLocal()
    }

    var streak: Int {
        UserDefaults.standard.integer(forKey: "streakCount")
    }

    func closeDay() {
        dayClosed = true
        let ud = UserDefaults.standard
        let today = Self.dayString(.now)
        let yesterday = Self.dayString(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        if ud.string(forKey: "lastClosedDate") != today {
            let current = ud.integer(forKey: "streakCount")
            ud.set(ud.string(forKey: "lastClosedDate") == yesterday ? current + 1 : 1,
                   forKey: "streakCount")
            ud.set(today, forKey: "lastClosedDate")
        }
        Haptics.success()
        if isLive {
            let pulled = tasks.filter { $0.status == .done }.map(\.id)
            let remaining = tasks.filter { $0.status == .carried }.map(\.id)
            Task {
                _ = try? await APIClient.shared.closingTime(
                    date: today, pulled: pulled, remaining: remaining
                )
                await refreshAll()
            }
        }
        Task { await NotificationManager.refreshSchedules(dayClosed: true) }
    }

    var reviewSummary: String {
        let done = tasks.filter { $0.status == .done }.count
        let moved = carriedTasks.count
        return "\(done) done · \(moved) moved to tomorrow"
    }

    /// yyyy-MM-dd for the date's *local* calendar day. Must use the device
    /// timezone: `.iso8601` FormatStyle formats in UTC, which shifts the day
    /// by ±1 for users east/west of GMT (e.g. IST midnight is still the prior
    /// day in UTC) — the source of calendar/today off-by-one-day bugs.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

extension PlanSlot {
    /// "09:00" → a concrete Date on the given day
    func start(on day: Date) -> Date? {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)
    }
}
