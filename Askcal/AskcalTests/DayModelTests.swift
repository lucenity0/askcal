//
//  DayModelTests.swift
//  AskcalTests
//
//  The logic behind what a day looks like, tested without drawing one.
//
//  Every case here is something that shipped broken. The day list sorted
//  finished work to the bottom regardless of when it happened; a created task
//  could vanish between the server and the screen because one field decoded
//  strictly; a task pinned late in the evening was filed on two days at once.
//  None of that needed a simulator to notice, and none of it was noticed.
//

import Foundation
import Testing

@testable import Askcal

private let cal = Calendar.current

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    cal.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
}

private func task(
    _ title: String,
    done: Bool = false,
    finishedAt: Date? = nil,
    pinnedAt: Date? = nil,
    due: Date? = nil,
    regret: Int = 50
) -> AskcalTask {
    AskcalTask(
        id: UUID(),
        track: "uni",
        title: title,
        regretScore: regret,
        status: done ? .done : .pending,
        scheduledFor: cal.startOfDay(for: .now),
        scheduledAt: pinnedAt,
        dueAt: due,
        completedAt: finishedAt
    )
}

// MARK: - The order the day reads in

@MainActor
struct DayOrderTests {

    @Test func finishedWorkSortsByWhenItWasFinished() {
        // It sorted by a plan slot the task no longer has, which sent every
        // completed row to the bottom however early it actually happened.
        let store = AskcalStore()
        store.tasks = [
            task("late", done: true, finishedAt: at(21)),
            task("early", done: true, finishedAt: at(9)),
        ]

        #expect(store.dayEntries.map(\.title) == ["early", "late"])
    }

    @Test func pinnedWorkSortsByItsPinnedTime() {
        let store = AskcalStore()
        store.tasks = [task("evening", pinnedAt: at(20)), task("morning", pinnedAt: at(8))]

        #expect(store.dayEntries.map(\.title) == ["morning", "evening"])
    }

    @Test func workWithNoTimeAtAllComesLast() {
        // "Sometime today" comes after everything with an hour on it.
        let store = AskcalStore()
        store.tasks = [task("whenever"), task("nine", pinnedAt: at(9))]

        #expect(store.dayEntries.map(\.title) == ["nine", "whenever"])
    }

    @Test func consequenceBreaksATieOnTime() {
        let store = AskcalStore()
        store.tasks = [
            task("minor", pinnedAt: at(9), regret: 10),
            task("major", pinnedAt: at(9), regret: 90),
        ]

        #expect(store.dayEntries.map(\.title) == ["major", "minor"])
    }

    @Test func tickingSomethingDoesNotRemoveItFromTheDay() {
        // A task that disappears the moment you complete it reads as the
        // checkbox having deleted it.
        let store = AskcalStore()
        store.tasks = [task("write it up")]
        store.toggleDone(store.tasks[0])

        #expect(store.dayEntries.count == 1)
        #expect(store.dayEntries[0].status == .done)
    }

    @Test func tickingStampsAFinishTimeImmediately() {
        // Stamped locally as well as server-side, so the time lands on the same
        // frame as the tick rather than after the next refresh.
        let store = AskcalStore()
        store.tasks = [task("write it up")]
        store.toggleDone(store.tasks[0])

        #expect(store.tasks[0].completedAt != nil)
    }

    @Test func untickingClearsTheFinishTime() {
        let store = AskcalStore()
        store.tasks = [task("write it up", done: true, finishedAt: at(9))]
        store.toggleDone(store.tasks[0])

        #expect(store.tasks[0].completedAt == nil)
    }
}

// MARK: - Decoding what the server sends

struct TaskDecodingDefaultsTests {

    private func decode(_ json: String) throws -> AskcalTask {
        try APIDates.decoder.decode(AskcalTask.self, from: Data(json.utf8))
    }

    @Test func aTaskMissingEverythingOptionalStillDecodes() throws {
        // The defensive decode exists because one strict field took the whole
        // task with it, which is how created tasks vanished on the way back.
        let decoded = try decode("""
        {"id":"\(UUID().uuidString)","title":"survives"}
        """)

        #expect(decoded.title == "survives")
        #expect(decoded.status == .pending)
        #expect(decoded.regretScore == 0)
        #expect(decoded.track == "")
    }

    @Test func aTrackTheAppHasNeverHeardOfDecodes() throws {
        // Tracks are rows the user names. A compile-time set cannot cover them,
        // and refusing an unknown one would drop the task entirely.
        let decoded = try decode("""
        {"id":"\(UUID().uuidString)","title":"x","track":"whatever-they-called-it"}
        """)

        #expect(decoded.track == "whatever-they-called-it")
    }

}

// MARK: - The countdown

struct DeadlineLabelTests {

    private func label(secondsFromNow: Double) -> String? {
        task("x", due: Date.now.addingTimeInterval(secondsFromNow)).deadlineLabel
    }

    @Test func underAnHourCountsInMinutes() {
        #expect(label(secondsFromNow: 25 * 60) == "due in 25 min")
    }

    @Test func underADayCountsInHours() {
        // The extra minute matters: the label truncates, and the microseconds
        // spent getting here turn exactly six hours into five and a bit.
        #expect(label(secondsFromNow: 6 * 3600 + 60) == "due in 6 h")
    }

    @Test func beyondADayCountsInDays() {
        #expect(label(secondsFromNow: 3 * 86400 + 60) == "due in 3 days")
    }

    @Test func oneDayIsSingular() {
        #expect(label(secondsFromNow: 86400 + 60) == "due in 1 day")
    }

    @Test func somethingPastSaysOverdue() {
        #expect(label(secondsFromNow: -2 * 3600) == "overdue by 2 h")
    }

    @Test func noDeadlineFallsBackToWhateverTheServerSaid() {
        var undated = task("x")
        undated.meta = "no rush"
        #expect(undated.deadlineLabel == "no rush")
    }
}
