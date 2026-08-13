//
//  TaskWriteTests.swift
//  AskcalTests
//
//  Covers the paths that made "add a task" appear to do nothing.
//
//  Everything here runs on the offline (not-signed-in) branch, which takes no
//  network and is therefore deterministic. The live branch differs only in that
//  it reconciles with the server afterwards; the row-appears-immediately
//  behaviour under test is the same code either way.
//

import Foundation
import Testing
@testable import Askcal

@MainActor
private func freshStore() -> AskcalStore {
    // A store built directly is offline: `isLive` only flips in bootstrap()
    // or connected(), so no request is ever made from these tests.
    AskcalStore()
}

private let cal = Calendar.current

// MARK: - Creating

@MainActor
struct QuickAddTests {

    @Test func addingATaskMakesItVisibleImmediately() {
        let store = freshStore()
        store.quickAdd(title: "finish the brief", scheduledAt: .now)

        #expect(store.tasks.count == 1)
        #expect(store.openTasks.first?.title == "finish the brief")
    }

    @Test func titleIsTrimmed() {
        let store = freshStore()
        store.quickAdd(title: "  read the paper  ", scheduledAt: .now)

        #expect(store.tasks.first?.title == "read the paper")
    }

    @Test func blankTitlesAreRejected() {
        let store = freshStore()
        store.quickAdd(title: "   ", scheduledAt: .now)

        #expect(store.tasks.isEmpty)
    }

    /// The optimistic row must carry the same starting score the server would
    /// assign, or the entry visibly re-ranks the moment the response lands.
    @Test func optimisticRowUsesTheServersQuickAddScore() {
        let store = freshStore()
        store.quickAdd(title: "email supervisor", scheduledAt: .now)

        #expect(store.tasks.first?.regretScore == QuickAdd.regretScore)
    }

    @Test func aNewTaskStartsPendingAndSoAppearsOnTheSchedule() {
        let store = freshStore()
        store.quickAdd(title: "submit form", scheduledAt: .now)

        #expect(store.tasks.first?.status == .pending)
        #expect(store.scheduledTasks.count == 1)
        // no plan slot yet, so it groups under "anytime" rather than vanishing
        #expect(store.groupedSchedule.contains { $0.part == .anytime })
    }

    /// Tomorrow's work is real and saved, it simply isn't today's problem.
    @Test func aTaskScheduledForTomorrowStaysOffToday() throws {
        let store = freshStore()
        let tomorrow = try #require(cal.date(byAdding: .day, value: 1, to: .now))
        store.quickAdd(title: "next week's reading", scheduledAt: tomorrow,
                       scheduledFor: cal.startOfDay(for: tomorrow))

        #expect(store.tasks.isEmpty)
    }

    @Test func aDeadlineSurvivesOntoTheTask() throws {
        let store = freshStore()
        let due = try #require(cal.date(byAdding: .hour, value: 3, to: .now))
        store.quickAdd(title: "hand in", scheduledAt: .now, dueAt: due)

        let task = try #require(store.tasks.first)
        #expect(task.dueAt != nil)
        #expect(task.deadlineLabel?.hasPrefix("due in") == true)
    }
}

// MARK: - Removing

@MainActor
struct DeleteTaskTests {

    /// Before this existed, the only way to clear a wrongly auto-tasked item
    /// was to mark it done, so every mistake accumulated permanently.
    @Test func deletingRemovesTheTask() throws {
        let store = freshStore()
        store.quickAdd(title: "wrong task", scheduledAt: .now)
        let task = try #require(store.tasks.first)

        store.deleteTask(task)

        #expect(store.tasks.isEmpty)
    }

    @Test func deletingAnAlreadyGoneTaskIsHarmless() {
        let store = freshStore()
        store.quickAdd(title: "keep me", scheduledAt: .now)
        let stranger = AskcalTask(id: UUID(), track: "uni", title: "never added",
                                  regretScore: 20)

        store.deleteTask(stranger)

        #expect(store.tasks.count == 1)
    }
}

// MARK: - Completing

@MainActor
struct ToggleDoneTests {

    /// The day list was pending-only, so ticking something removed it from the
    /// page. That reads as the checkbox having deleted the task rather than
    /// completed it — and it throws away the only evidence the day is going
    /// well.
    @Test func tickingATaskKeepsItOnTheDay() throws {
        let store = freshStore()
        store.quickAdd(title: "tick me", scheduledAt: .now)
        let task = try #require(store.tasks.first)

        store.toggleDone(task)

        #expect(store.dayEntries.count == 1)
        #expect(store.dayEntries.first?.status == .done)
    }

    /// Work moved to tomorrow is genuinely not on today any more, so it is the
    /// one status the day list does drop.
    @Test func carriedWorkLeavesTheDay() throws {
        let store = freshStore()
        store.quickAdd(title: "not today", scheduledAt: .now)
        let task = try #require(store.tasks.first)

        store.review(task, done: false)

        #expect(store.dayEntries.isEmpty)
    }

    /// The day reads in the order it happens, not by score.
    @Test func theDayIsOrderedByTheClock() throws {
        let store = freshStore()
        let cal = Calendar.current
        let nine = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        let five = try #require(cal.date(bySettingHour: 17, minute: 0, second: 0, of: .now))

        store.quickAdd(title: "evening", scheduledAt: five)
        store.quickAdd(title: "morning", scheduledAt: nine)

        #expect(store.dayEntries.map(\.title) == ["morning", "evening"])
    }

    /// Something with no hour on it is still on the day — it just sorts after
    /// everything that does, rather than dropping out of the list.
    @Test func untimedWorkSortsToTheEnd() throws {
        let store = freshStore()
        let cal = Calendar.current
        let nine = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now))

        store.quickAdd(title: "sometime", scheduledFor: cal.startOfDay(for: .now))
        store.quickAdd(title: "at nine", scheduledAt: nine)

        #expect(store.dayEntries.map(\.title) == ["at nine", "sometime"])
    }

    @Test func togglingMarksDoneAndBack() throws {
        let store = freshStore()
        store.quickAdd(title: "tick me", scheduledAt: .now)
        let task = try #require(store.tasks.first)

        store.toggleDone(task)
        #expect(store.tasks.first?.status == .done)
        #expect(store.openTasks.isEmpty)

        store.toggleDone(task)
        #expect(store.tasks.first?.status == .pending)
        #expect(store.openTasks.count == 1)
    }
}

// MARK: - Rescheduling

@MainActor
struct UpdateScheduleTests {

    @Test func movingATaskToTomorrowTakesItOffToday() throws {
        let store = freshStore()
        store.quickAdd(title: "shift me", scheduledAt: .now)
        let task = try #require(store.tasks.first)
        let tomorrow = try #require(cal.date(byAdding: .day, value: 1, to: .now))

        store.updateTaskSchedule(task, scheduledAt: tomorrow, dueAt: nil,
                                 scheduledFor: cal.startOfDay(for: tomorrow))

        #expect(store.tasks.isEmpty)
    }

    @Test func retimingWithinTodayKeepsTheTask() throws {
        // Pinned to fixed hours rather than `.now` and `.now + 90m`: run after
        // 22:30 the "later" time crossed midnight, the task moved to tomorrow,
        // and a test named "within today" failed for being right.
        let store = freshStore()
        let morning = try #require(cal.date(bySettingHour: 9, minute: 0, second: 0, of: .now))
        let later = try #require(cal.date(bySettingHour: 10, minute: 30, second: 0, of: .now))

        store.quickAdd(title: "stay put", scheduledAt: morning)
        let task = try #require(store.tasks.first)

        store.updateTaskSchedule(task, scheduledAt: later, dueAt: nil,
                                 scheduledFor: cal.startOfDay(for: later))

        #expect(store.tasks.count == 1)
        #expect(store.tasks.first?.scheduledAt != nil)
    }
}

// MARK: - Decoding

struct TaskDecodingTests {

    private func decode(_ json: String) throws -> AskcalTask {
        try APIDates.decoder.decode(AskcalTask.self, from: Data(json.utf8))
    }

    /// `TaskOut.track` is `str | None` in the API contract. A hard decode here
    /// threw on a legitimate response and took the whole task with it — and the
    /// `try?` around the call meant that looked exactly like "nothing happened".
    @Test func aNullTrackFallsBackInsteadOfFailingTheDecode() throws {
        let task = try decode("""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","track":null,
         "title":"no track","meta":null,"regretScore":20,
         "estimatedHours":null,"status":"pending"}
        """)

        // A slug now, not an enum case: tracks are rows the user names, so a
        // null one has no five-member set to fall back into.
        #expect(task.track == "")
        #expect(task.title == "no track")
    }

    @Test func aMissingStatusDefaultsToPending() throws {
        let task = try decode("""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","track":"uni",
         "title":"lean response","meta":null,"regretScore":20}
        """)

        #expect(task.status == .pending)
    }

    /// `scheduledFor` arrives date-only; the datetime fields arrive ISO-8601
    /// with and without fractional seconds depending on the column. All three
    /// have to parse or the task silently disappears between server and screen.
    @Test func allThreeWireDateShapesParse() throws {
        let task = try decode("""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","track":"uni",
         "title":"dates","meta":null,"regretScore":20,"status":"pending",
         "scheduledFor":"2026-08-12",
         "scheduledAt":"2026-08-12T14:30:00+05:30",
         "dueAt":"2026-08-12T17:00:00.123456+05:30"}
        """)

        #expect(task.scheduledFor != nil)
        #expect(task.scheduledAt != nil)
        #expect(task.dueAt != nil)
    }

    /// The day formatter pins `en_US_POSIX`; without it a device set to a
    /// Buddhist or Japanese regional calendar reads "yyyy" as an era year and
    /// lands on a date centuries away.
    @Test func dayOnlyParsingIgnoresTheDeviceCalendar() throws {
        let parsed = try #require(APIDates.dayOnly.date(from: "2026-08-12"))
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current

        #expect(gregorian.component(.year, from: parsed) == 2026)
        #expect(gregorian.component(.month, from: parsed) == 8)
        #expect(gregorian.component(.day, from: parsed) == 12)
    }
}
