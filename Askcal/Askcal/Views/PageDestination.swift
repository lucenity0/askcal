//
//  PageDestination.swift
//  Askcal
//
//  The places you can go from the day.
//
//  Naming them as data rather than wiring `NavigationLink` into each row is
//  what lets the same row mean two different things depending on the device.
//  On a phone, opening the inbox pushes it. On an iPad held wide, it belongs on
//  the facing page — and a `NavigationLink` can only ever do the first.
//

import SwiftUI

enum PageDestination: String, Hashable, CaseIterable, Identifiable {
    case inbox, routine, tracks, review, calendar, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .routine: return "Routine"
        case .tracks: return "Tracks"
        case .review: return "Review"
        case .calendar: return "Calendar"
        case .settings: return "Settings"
        }
    }
}

/// Resolves a destination to its screen. One place, so the phone's navigation
/// stack and the iPad's facing page can never drift into showing different
/// things for the same row.
struct DestinationPage: View {
    let destination: PageDestination
    @Binding var isAddingRoutine: Bool

    var body: some View {
        switch destination {
        case .inbox: InboxView()
        case .routine: RoutineView(isAdding: $isAddingRoutine)
        case .tracks: TracksView()
        case .review: ReviewView()
        case .calendar: CalendarView()
        case .settings: MoreView()
        }
    }
}
