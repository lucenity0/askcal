//
//  PageDestination.swift
//  Askcal
//
//  The tabs, named.
//
//  `review` is in this list but not on the bar. Closing the day is something
//  you do once at the end of it, reached from the day itself — a permanent slot
//  in the tab bar would give a nightly ritual the same standing as the inbox.
//  It still needs an identity so the day can select it.
//

import SwiftUI

enum PageDestination: String, Hashable, CaseIterable, Identifiable {
    case today, inbox, calendar, more, review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .calendar: return "Calendar"
        case .more: return "More"
        case .review: return "Review"
        }
    }
}
