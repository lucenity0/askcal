//
//  MonthLayout.swift
//  Askcal
//
//  Where each day of a month sits in a seven-column grid.
//
//  Pulled out of the view for two reasons. It is date arithmetic, which is the
//  kind of thing that is wrong for one month of the year and right for the
//  other eleven, and inside a `View` it could only be checked by looking at a
//  screenshot and counting. Here it can be asserted.
//
//  The grid is one flat list of slots — leading blanks, then the days — rather
//  than a run of blanks followed by a separate run of days. Two sibling
//  `ForEach`es in a `LazyVGrid`, one of them over a runtime `Range`, is a shape
//  SwiftUI handles poorly: cells go missing rather than misplaced, which looks
//  like the calendar simply forgot the first week.
//

import Foundation

struct MonthLayout {
    /// Empty cells before the first of the month, so day 1 lands under its
    /// real weekday.
    let blanks: Int
    /// How many days this month has.
    let days: Int

    /// One entry per grid cell: `nil` for a leading blank, otherwise the day.
    let slots: [Int?]

    init(month: Date, calendar: Calendar = .current) {
        let firstOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: month)
        )
        days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30

        if let firstOfMonth {
            let weekday = calendar.component(.weekday, from: firstOfMonth)
            // `weekday` is 1-based from Sunday; `firstWeekday` is whichever day
            // this locale starts its week on, so the offset has to be taken
            // relative to it or every non-Sunday-start locale is shifted.
            blanks = (weekday - calendar.firstWeekday + 7) % 7
        } else {
            blanks = 0
        }

        slots = Array(repeating: nil, count: blanks) + (1...days).map { Optional($0) }
    }

    /// Weekday initials in this locale's order, for the grid header.
    static func weekdaySymbols(_ calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
