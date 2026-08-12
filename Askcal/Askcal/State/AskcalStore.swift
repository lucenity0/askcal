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

/// Mirrors `QUICK_ADD_REGRET` in askcal-api's tasks router: a manual add starts
/// low, because the classifier only scores email-born work. Kept in step so an
/// optimistic row doesn't visibly re-rank the instant the server replies.
enum QuickAdd {
    static let regretScore = 20
}

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
    var calendarEvents: [CalendarEvent]
    var dayClosed = false

    /// The account's tracks, as the user has them.
    ///
    /// Held here rather than fetched per screen because three surfaces need
    /// them — the composer's picker, the Tracks page, and anywhere a task's
    /// track is named — and a track renamed on one of them must not still read
    /// by its old name on the other two.
    var tracks: [Track] = []

    /// True once a Askcal account is connected — data comes from askcal-api.
    var isLive = false
    /// True while the cold-launch fetch is in flight.
    var isBootstrapping = false
    var accountEmail: String?
    /// A *read* that failed — the last refresh couldn't complete.
    var syncError: String?
    /// A *write* that failed, in the user's words.
    ///
    /// Every mutating call used to be wrapped in `try?`, so a create that hit a
    /// network error, an expired token or a decode mismatch all did the same
    /// thing: nothing, silently. The task never appeared and the app never said
    /// why. Writes are optimistic now — the row shows immediately and rolls back
    /// here if the server refuses it.
    var actionError: String?

    /// The idle companion on the now-working card. One motif per app open, so
    /// the card has a small life of its own and is not the same twice.
    let companion: CompanionMotif = CompanionMotif.allCases.randomElement() ?? .cat


    init(
        tasks: [AskcalTask] = [],
        emails: [EmailItem] = [],
        dayPlan: [PlanSlot] = [],
        calendarEvents: [CalendarEvent] = []
    ) {
        self.tasks = tasks
        self.emails = emails
        self.dayPlan = dayPlan
        self.calendarEvents = calendarEvents
        // Before any view renders. Doing this in bootstrap() raced @AppStorage:
        // a view could read a stored preference and cache it a moment before
        // the wipe removed the key, so the reset appeared to work except when
        // it didn't.
        if Self.wantsCleanSlate { resetForTesting() }
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

    /// Everything on today, ticked ones included, in the order the day happens.
    ///
    /// The day list used to be `scheduledTasks`, which is pending-only — so
    /// ticking something made it disappear off the page entirely. That reads as
    /// the checkbox having deleted your task rather than completed it, and it
    /// throws away the only evidence that the day is going well. Done work
    /// stays, struck through, until the day is closed.
    ///
    /// Carried work is no longer filtered out by status. The server moves a
    /// carried task's `scheduledFor` to tomorrow, so the day it belongs to now
    /// does that job — and filtering on status as well made carried work
    /// invisible on every day including the one it had been moved to.
    var dayEntries: [AskcalTask] {
        tasks
            .filter { isToday($0.scheduledFor) }
            .sorted { lhs, rhs in
                let l = minuteOfDay(lhs), r = minuteOfDay(rhs)
                if l != r { return l < r }
                return lhs.regretScore > rhs.regretScore
            }
    }

    /// When a task happens, in minutes past midnight. Its plan slot first, then
    /// a time the user pinned themselves; anything with neither sorts to the
    /// end, because "sometime today" comes after everything with an hour.
    private func minuteOfDay(_ task: AskcalTask) -> Int {
        if let slot = slot(for: task), let minutes = minutesSinceMidnight(slot.time) {
            return minutes
        }
        if let at = task.scheduledAt {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: at)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        return .max
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

    func tasks(in track: Track) -> [AskcalTask] {
        openTasks.filter { $0.track == track.id }
    }

    /// The track a task is filed under, or nil when it names one this account
    /// no longer has — a track since deleted, or mail classified before the
    /// list arrived.
    func track(_ slug: String) -> Track? {
        tracks.first { $0.id == slug }
    }

    /// What to call a track by slug, whether or not we still have it.
    func trackLabel(_ slug: String) -> String {
        track(slug)?.label ?? Track.title(for: slug)
    }

    /// Where a new task goes when the user has not said. The first track that
    /// is on — never a hardcoded one, since the account may not have it.
    var defaultTrack: Track? {
        tracks.first { $0.active } ?? tracks.first
    }

    // MARK: - The day's page

    /// Notes by day string. Held here rather than in the view so the phone's
    /// collapsed row, the popup editor and the iPad's facing page are all
    /// reading the same text — three copies of one note is how two of them end
    /// up stale.
    var notes: [String: DayNote] = [:]

    private var noteSaves: [String: Task<Void, Never>] = [:]

    /// How long to wait after the last keystroke before writing. Long enough
    /// that a sentence is one request rather than forty, short enough that
    /// closing the app straight after typing does not lose the line.
    private static let noteSaveDelay: Duration = .milliseconds(700)

    func note(for date: Date) -> DayNote {
        notes[Self.dayString(date)] ?? DayNote(day: date, body: "", updatedAt: nil)
    }

    func hasNote(on date: Date) -> Bool {
        !(notes[Self.dayString(date)]?.isEmpty ?? true)
    }

    func loadNote(for date: Date) async {
        guard isLive else { return }
        let key = Self.dayString(date)
        // A save in flight for this day would be overwritten by whatever the
        // server still has, putting the user's own words back a version.
        guard noteSaves[key] == nil else { return }
        guard let fetched = try? await APIClient.shared.note(on: date) else { return }
        notes[key] = fetched
    }

    /// Which days in the visible week have been written on, for the strip.
    func loadNoteMarks(from start: Date, to end: Date) async {
        guard isLive else { return }
        guard let fetched = try? await APIClient.shared.notes(from: start, to: end)
        else { return }
        for note in fetched where noteSaves[Self.dayString(note.day)] == nil {
            notes[Self.dayString(note.day)] = note
        }
    }

    /// Applies immediately and writes after a pause. The text on screen is the
    /// truth while you are typing; the server catches up.
    func writeNote(_ body: String, for date: Date) {
        let key = Self.dayString(date)
        notes[key] = DayNote(day: date, body: body, updatedAt: .now)
        saveLocal()

        noteSaves[key]?.cancel()
        guard isLive else { return }
        noteSaves[key] = Task {
            try? await Task.sleep(for: Self.noteSaveDelay)
            guard !Task.isCancelled else { return }
            do {
                _ = try await APIClient.shared.saveNote(on: date, body: body)
                actionError = nil
            } catch {
                // Deliberately no rollback. Replacing what someone is currently
                // writing with an older copy, because a request failed, loses
                // the very thing they would have wanted kept.
                report(error)
            }
            noteSaves[key] = nil
        }
    }

    func refreshTracks() async {
        guard isLive else { return }
        guard let fetched = try? await APIClient.shared.tracks() else { return }
        tracks = fetched
    }

    /// Add a track, then pull the list back so counts and slug come from the
    /// server rather than a guess made here.
    func addTrack(label: String, detail: String?) async {
        guard isLive else { return }
        do {
            _ = try await APIClient.shared.createTrack(label: label, detail: detail)
            await refreshTracks()
            // A new track re-runs the auto-task gates server-side over mail
            // already classified, so the day can have changed too.
            await refreshAll()
        } catch {
            report(error)
        }
    }

    /// Change a track. Applied locally first so the switch moves under the
    /// finger, and rolled back if the server disagrees.
    func updateTrack(
        _ track: Track, label: String? = nil, detail: String? = nil,
        active: Bool? = nil, autoTasks: Bool? = nil
    ) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let previous = tracks[index]
        if let label { tracks[index].label = label }
        if let detail { tracks[index].detail = detail }
        if let active { tracks[index].active = active }
        if let autoTasks { tracks[index].autoTasks = autoTasks }

        guard isLive else { return }
        let updated = tracks[index]
        Task {
            do {
                _ = try await APIClient.shared.updateTrack(
                    track.id, label: label, detail: detail,
                    active: active, autoTasks: autoTasks
                )
                // Turning one on is retroactive: mail already in the inbox is
                // reconsidered, so tasks can appear without anything else
                // having happened.
                if updated.active && updated.autoTasks { await refreshAll() }
            } catch {
                if let i = tracks.firstIndex(where: { $0.id == previous.id }) {
                    tracks[i] = previous
                }
                report(error)
            }
        }
    }

    func deleteTrack(_ track: Track) {
        guard let index = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let removed = tracks.remove(at: index)
        guard isLive else { return }
        Task {
            do {
                try await APIClient.shared.deleteTrack(removed.id)
                // Its tasks are left untracked server-side rather than moved,
                // so the day list has changed shape.
                await refreshAll()
            } catch {
                tracks.insert(removed, at: min(index, tracks.count))
                report(error)
            }
        }
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
        // Distinguishes "still fetching" from "genuinely empty". Without it the
        // day surface rendered its empty copy over data in flight, which read
        // as an answer rather than a wait.
        isBootstrapping = true
        defer { isBootstrapping = false }

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
    private static let localNotesKey = "localNotes"

    /// UI tests share one simulator, and the signed-out store persists to
    /// UserDefaults — so without a way to ask for a clean slate each test
    /// inherits whatever the last one wrote, and they only pass in isolation.
    /// Test-only: nothing passes this argument in a shipped build.
    private static var wantsCleanSlate: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestCleanSlate")
    }

    /// Wipe everything a previous test left behind.
    ///
    /// Done by clearing keys rather than by seeding them from launch
    /// arguments: an argument lands in `NSArgumentDomain`, which outranks the
    /// app's own domain and cannot be written over — so a preference seeded
    /// that way is pinned for the life of the process and any control bound to
    /// it silently stops working.
    private func resetForTesting() {
        let ud = UserDefaults.standard
        for key in [Self.localTasksKey, Self.localNotesKey, "localRoutines", "weekStripExpanded",
                    "userName", "streakCount", "lastClosedDate"] {
            ud.removeObject(forKey: key)
        }
        tasks = []
    }

    private func loadLocal() {
        let ud = UserDefaults.standard
        if let d = ud.data(forKey: Self.localTasksKey),
           let t = try? JSONDecoder().decode([AskcalTask].self, from: d) { tasks = t }
    }

    /// Persist the offline session so a rebuild/relaunch keeps it. No-op when
    /// live (the backend is the source of truth then).
    private func saveLocal() {
        guard !isLive else { return }
        let ud = UserDefaults.standard
        ud.set(try? JSONEncoder().encode(tasks), forKey: Self.localTasksKey)
        ud.set(try? JSONEncoder().encode(notes), forKey: Self.localNotesKey)
    }

    /// Full, irreversible wipe of the not-signed-in session's local data.
    func deleteLocalData() {
        tasks = []
        let ud = UserDefaults.standard
        ud.removeObject(forKey: Self.localTasksKey)
        ud.removeObject(forKey: Self.localNotesKey)
        // Left over from the routine tracker, which no longer exists — cleared
        // so an old install stops carrying dead keys around forever.
        ud.removeObject(forKey: "localRoutines")
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
        actionError = nil
        tasks = []
        emails = []
        dayPlan = []
        calendarEvents = []
    }

    func refreshAll() async {
        guard isLive else { return }
        await fetchAll()
    }

    private func fetchAll() async {
        invalidateDayCache()
        do {
            async let tasksReq = APIClient.shared.tasks()
            async let todayReq = APIClient.shared.today()
            async let inboxReq = APIClient.shared.inbox()
            async let tracksReq = APIClient.shared.tracks()
            tasks = try await tasksReq
            dayPlan = try await todayReq.dayPlan
            emails = try await inboxReq
            // Tolerated separately: tracks are for naming and picking, so
            // losing them should not turn a successful refresh into an error.
            tracks = (try? await tracksReq) ?? tracks
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

    /// Days already fetched, keyed by `dayString`. Turning pages back and forth
    /// across a week would otherwise refetch the same day every time it came
    /// back on screen.
    private var dayCache: [String: DayData] = [:]

    /// A day's tasks and events, from cache where possible. Today is always
    /// served live from the store — it is the day being edited, and a cached
    /// copy of it would go stale the moment anything was ticked.
    /// `force` skips the cache — what pull-to-refresh on a day that isn't today
    /// means. Without it the gesture would spin and hand back the same cached
    /// answer, which is worse than not offering it.
    func dayData(for date: Date, force: Bool = false) async -> DayData {
        if Calendar.current.isDateInToday(date) {
            return DayData(tasks: scheduledTasks, events: calendarEvents)
        }
        let key = Self.dayString(date)
        if !force, let cached = dayCache[key] { return cached }
        let data = await loadDay(date)
        dayCache[key] = data
        return data
    }

    /// Any write can move a task onto or off another day, so the cache is
    /// dropped wholesale rather than guessing which days it touched.
    private func invalidateDayCache() {
        dayCache.removeAll()
    }

    /// Which days in a range have work on them, and which have calendar events.
    ///
    /// The month grid used to gate its dots on `today &&`, so no day but today
    /// could ever show one — the grid looked identical in an empty month and a
    /// full one. Keyed by `dayString` so the caller can look a cell up directly.
    struct DayMarks: Equatable {
        var hasTasks = false
        var hasEvents = false
    }

    func marks(from start: Date, to end: Date) async -> [String: DayMarks] {
        guard isLive else { return localMarks(from: start, to: end) }

        async let tasksReq = APIClient.shared.tasks(from: start, to: end)
        async let eventsReq = APIClient.shared.calendarEvents(
            start: Self.dayString(start), end: Self.dayString(end)
        )
        let rangeTasks = (try? await tasksReq) ?? []
        let rangeEvents = (try? await eventsReq) ?? []

        var marks: [String: DayMarks] = [:]
        for task in rangeTasks {
            guard let day = task.scheduledFor else { continue }
            marks[Self.dayString(day), default: DayMarks()].hasTasks = true
        }
        for event in rangeEvents {
            guard let day = event.start else { continue }
            marks[Self.dayString(day), default: DayMarks()].hasEvents = true
        }
        return marks
    }

    /// Signed out there is no calendar and no server, but the locally-stored
    /// tasks still deserve their dots.
    private func localMarks(from start: Date, to end: Date) -> [String: DayMarks] {
        var marks: [String: DayMarks] = [:]
        for task in tasks {
            guard let day = task.scheduledFor, day >= start, day <= end else { continue }
            marks[Self.dayString(day), default: DayMarks()].hasTasks = true
        }
        return marks
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

    /// Pull-to-refresh on Today and Inbox, and the manual "sync now" action
    /// in More: trigger a Gmail sync, wait, then refetch everything. The
    /// pipeline may have auto-created tasks from actionable mail, so tasks
    /// and the day plan refresh along with the inbox.
    func syncInbox() async {
        guard isLive else { return }
        do {
            try await APIClient.shared.triggerSync()
        } catch {
            // a pull-to-refresh that quietly does nothing is worse than one
            // that says the sync didn't start
            report(error)
            return
        }
        try? await Task.sleep(for: .seconds(6))
        await fetchAll()
    }

    // MARK: - Actions

    /// Put a failed write into words the user can act on. `APIError` already
    /// carries a decent message for every case — it was simply never read.
    private func report(_ error: Error) {
        actionError = (error as? LocalizedError)?.errorDescription
            ?? "that didn't save. try again?"
    }

    func dismissActionError() { actionError = nil }

    func toggleDone(_ task: AskcalTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = tasks[idx].status
        tasks[idx].status = previous == .done ? .pending : .done
        // Stamped here as well as on the server, so the time appears beside the
        // mark on the same frame as the tick rather than after the next
        // refresh. The server's own stamp replaces it when the list reloads.
        tasks[idx].completedAt = tasks[idx].status == .done ? .now : nil
        if tasks[idx].status == .done { Haptics.tick() }
        pushStatus(task.id, tasks[idx].status, revertingTo: previous)
        saveLocal()
    }


    private func pushStatus(_ id: UUID, _ status: TaskStatus, revertingTo previous: TaskStatus) {
        guard isLive else { return }
        Task {
            do {
                _ = try await APIClient.shared.setTaskStatus(id, status)
                actionError = nil
            } catch {
                // put the tick back — a checkbox that stays checked after the
                // server refused it is a lie the next refresh silently undoes
                if let idx = tasks.firstIndex(where: { $0.id == id }) {
                    tasks[idx].status = previous
                    // Rolled back with it, or a refused tick leaves a finish
                    // time on a task that was never finished.
                    if previous != .done { tasks[idx].completedAt = nil }
                }
                report(error)
            }
        }
    }

    /// Remove a task outright — the undo for a wrong auto-tasked item or a
    /// mistyped quick-add. Without it the only way to clear one was to mark it
    /// done, so every mistake accumulated permanently.
    func deleteTask(_ task: AskcalTask) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let removed = tasks.remove(at: idx)
        Haptics.medium()
        guard isLive else { saveLocal(); return }
        Task {
            do {
                try await APIClient.shared.deleteTask(removed.id)
                actionError = nil
            } catch {
                tasks.insert(removed, at: min(idx, tasks.count))
                report(error)
            }
        }
    }

    func handleEmail(_ email: EmailItem) {
        guard let idx = emails.firstIndex(where: { $0.id == email.id }) else { return }
        let removed = emails.remove(at: idx)
        Haptics.tick()
        guard isLive else { return }
        Task {
            do {
                let task = try await APIClient.shared.handleEmail(removed.id)
                if isToday(task.scheduledFor) { tasks.append(task) }
                actionError = nil
            } catch {
                emails.insert(removed, at: min(idx, emails.count))
                report(error)
            }
        }
    }

    func snoozeEmail(_ email: EmailItem) {
        guard let idx = emails.firstIndex(where: { $0.id == email.id }) else { return }
        let removed = emails.remove(at: idx)
        Haptics.tick()
        guard isLive else { return }
        Task {
            do {
                try await APIClient.shared.snoozeEmail(removed.id)
                actionError = nil
            } catch {
                emails.insert(removed, at: min(idx, emails.count))
                report(error)
            }
        }
    }

    /// Create a task. The row appears immediately and is reconciled with the
    /// server's copy when it lands — a create that only shows after a round trip
    /// reads as a failure on a slow connection, which is how this looked.
    func quickAdd(
        title: String, track: String? = nil,
        scheduledAt: Date? = nil, dueAt: Date? = nil, scheduledFor: Date? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.tick()

        // No default track can be named here: the account's tracks are whatever
        // the user made them. Falls back to the first one that is on.
        let slug = track ?? defaultTrack?.id ?? ""

        let optimistic = AskcalTask(
            id: UUID(), track: slug, title: trimmed, meta: nil,
            regretScore: QuickAdd.regretScore, estimatedHours: nil,
            scheduledFor: scheduledFor ?? scheduledAt,
            scheduledAt: scheduledAt, dueAt: dueAt
        )
        if isToday(optimistic.scheduledFor) { tasks.append(optimistic) }

        guard isLive else { saveLocal(); return }

        Task {
            do {
                let saved = try await APIClient.shared.createTask(
                    title: trimmed, track: slug,
                    scheduledAt: scheduledAt, dueAt: dueAt, scheduledFor: scheduledFor
                )
                // swap the placeholder for the server's row: real id, real score
                replace(placeholder: optimistic.id, with: saved)
                actionError = nil
                // refresh the plan so a pinned time lands on the timeline
                if let today = try? await APIClient.shared.today() {
                    dayPlan = today.dayPlan
                }
            } catch {
                tasks.removeAll { $0.id == optimistic.id }
                report(error)
            }
        }
    }

    /// Reconcile an optimistic row with the server's version of it, honouring
    /// the day the server actually filed it under.
    private func replace(placeholder id: UUID, with saved: AskcalTask) {
        let belongsHere = isToday(saved.scheduledFor)
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            if belongsHere { tasks[idx] = saved } else { tasks.remove(at: idx) }
        } else if belongsHere {
            tasks.append(saved)
        }
    }

    /// Shift a task's day/pinned time and/or deadline (from the edit sheet).
    func updateTaskSchedule(
        _ task: AskcalTask, scheduledAt: Date?, dueAt: Date?, scheduledFor: Date?
    ) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = tasks[idx]
        Haptics.tick()

        var moved = previous
        moved.scheduledAt = scheduledAt
        moved.dueAt = dueAt
        moved.scheduledFor = scheduledFor ?? scheduledAt
        // moved off today → leaves the list
        if isToday(moved.scheduledFor) { tasks[idx] = moved } else { tasks.remove(at: idx) }

        guard isLive else { saveLocal(); return }

        Task {
            do {
                let updated = try await APIClient.shared.updateTaskSchedule(
                    previous.id, scheduledAt: scheduledAt,
                    dueAt: dueAt, scheduledFor: scheduledFor
                )
                replace(placeholder: previous.id, with: updated)
                actionError = nil
                if let today = try? await APIClient.shared.today() { dayPlan = today.dayPlan }
            } catch {
                if let i = tasks.firstIndex(where: { $0.id == previous.id }) {
                    tasks[i] = previous
                } else {
                    tasks.insert(previous, at: min(idx, tasks.count))
                }
                report(error)
            }
        }
    }

    // MARK: - Review ritual + streak

    func review(_ task: AskcalTask, done: Bool) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let previous = tasks[idx].status
        tasks[idx].status = done ? .done : .carried
        if !done {
            // Matches what the server does with a carry: the task moves to
            // tomorrow rather than merely being labelled. Without this the row
            // stays on today until the next refetch quietly removes it.
            tasks[idx].scheduledFor = Calendar.current.date(
                byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now)
            )
        }
        Haptics.tick()
        // review marks must survive a relaunch even if the day is never
        // formally closed — push each one, don't wait for closing time
        pushStatus(task.id, tasks[idx].status, revertingTo: previous)
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
                do {
                    _ = try await APIClient.shared.closingTime(
                        date: today, pulled: pulled, remaining: remaining
                    )
                    actionError = nil
                } catch {
                    // the local close still stands; the carry-forward just
                    // hasn't reached the server, and saying so beats a day that
                    // silently reopens tomorrow
                    report(error)
                }
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
