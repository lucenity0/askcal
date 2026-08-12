//
//  MonthLayoutTests.swift
//  AskcalTests
//
//  The month grid drew August 2026 without its first five days. The arithmetic
//  turned out to be right and the rendering wrong, but there was no way to know
//  that without counting cells in a screenshot — which is the reason this file
//  exists rather than the bug being fixed in place.
//

import Foundation
import Testing
@testable import Askcal

private func gregorian(firstWeekday: Int = 1) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.locale = Locale(identifier: "en_US_POSIX")
    c.timeZone = .current
    c.firstWeekday = firstWeekday
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ cal: Calendar) throws -> Date {
    try #require(cal.date(from: DateComponents(year: y, month: m, day: d)))
}

struct MonthLayoutTests {

    /// 1 August 2026 is a Saturday, so a Sunday-start week needs six blanks
    /// before it and day 1 lands in the last column.
    @Test func augustTwentyTwentySixStartsOnSaturday() throws {
        let cal = gregorian()
        let layout = MonthLayout(month: try date(2026, 8, 1, cal), calendar: cal)

        #expect(layout.blanks == 6)
        #expect(layout.days == 31)
        #expect(layout.slots.count == 37)
        #expect(layout.slots[6] == 1)
    }

    /// Every day of the month has a slot, in order, with no gaps. This is the
    /// property the grid actually depends on and the one whose failure looked
    /// like "the calendar forgot the first week".
    @Test func everyDayGetsExactlyOneSlotInOrder() throws {
        let cal = gregorian()
        for month in 1...12 {
            let layout = MonthLayout(month: try date(2026, month, 1, cal), calendar: cal)
            let present = layout.slots.compactMap { $0 }
            #expect(present == Array(1...layout.days),
                    "month \(month) lost or reordered days")
            #expect(layout.slots.prefix(layout.blanks).allSatisfy { $0 == nil })
        }
    }

    @Test func februaryKnowsAboutLeapYears() throws {
        let cal = gregorian()
        #expect(MonthLayout(month: try date(2028, 2, 1, cal), calendar: cal).days == 29)
        #expect(MonthLayout(month: try date(2026, 2, 1, cal), calendar: cal).days == 28)
    }

    /// A Monday-start locale shifts every month by one column. Taking the
    /// offset from `firstWeekday` rather than from Sunday is what makes that
    /// work; hardcoding Sunday silently shifts the whole grid for most of
    /// Europe.
    @Test func aMondayStartWeekShiftsTheMonth() throws {
        let sunday = gregorian(firstWeekday: 1)
        let monday = gregorian(firstWeekday: 2)
        let first = try date(2026, 8, 1, sunday)

        #expect(MonthLayout(month: first, calendar: sunday).blanks == 6)
        #expect(MonthLayout(month: first, calendar: monday).blanks == 5)
    }

    @Test func weekdaySymbolsFollowTheLocalesFirstDay() {
        let sunday = MonthLayout.weekdaySymbols(gregorian(firstWeekday: 1))
        let monday = MonthLayout.weekdaySymbols(gregorian(firstWeekday: 2))

        #expect(sunday.count == 7)
        #expect(monday.count == 7)
        #expect(sunday.first == monday.last)
    }

    /// The layout is built from whatever date it is handed, not only the first
    /// of the month — the calendar passes `displayedMonth`, which is `.now`
    /// until someone pages away from it.
    @Test func anyDateInTheMonthGivesTheSameLayout() throws {
        let cal = gregorian()
        let fromFirst = MonthLayout(month: try date(2026, 8, 1, cal), calendar: cal)
        let fromMiddle = MonthLayout(month: try date(2026, 8, 19, cal), calendar: cal)

        #expect(fromFirst.blanks == fromMiddle.blanks)
        #expect(fromFirst.slots == fromMiddle.slots)
    }
}
