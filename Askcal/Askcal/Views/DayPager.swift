//
//  DayPager.swift
//  Askcal
//
//  Turning the page.
//
//  A horizontal `ScrollView` with paging, over a `LazyHStack`, rather than a
//  paged `TabView`: the lazy stack builds only the pages on screen, so a wide
//  range of days costs nothing until you reach them. A `TabView` in page style
//  materialises its children far more eagerly, and the alternative — a
//  three-page window recentred after each swipe — needs the recentre to land
//  after the paging animation, which is a timing guess that shows as a flicker
//  when it's wrong.
//
//  Two things worth knowing about the gesture. Nested scrolling is fine because
//  the axes differ: this scrolls horizontally, each page scrolls vertically.
//  And a horizontal swipe from the leading edge normally fights the navigation
//  stack's back gesture — but this pager is the *root* of the stack, so there is
//  nothing behind it to pop to and no conflict to resolve. It must stay the
//  root for that to hold; a pager pushed onto the stack would need a different
//  answer.
//
//  Today is fixed at the moment the view appears rather than read per render,
//  so the range doesn't shift under the user if the app is open across midnight.
//

import SwiftUI

struct DayPager: View {
    @Binding var showComposer: Bool
    @Binding var editingTask: AskcalTask?
    var onConnect: () -> Void
    var onOpen: (PageDestination) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How far back and forward you can turn. Bounded because the pages are
    /// real days with real fetches behind them, not an infinite scroll.
    private static let reach = 180

    @State private var today = Calendar.current.startOfDay(for: .now)
    @State private var offset: Int? = 0

    private func date(_ dayOffset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dayOffset, to: today) ?? today
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(-Self.reach...Self.reach, id: \.self) { day in
                    DayPage(
                        date: date(day),
                        showComposer: $showComposer,
                        editingTask: $editingTask,
                        onConnect: onConnect,
                        onStep: step,
                        onOpen: onOpen,
                        isCurrent: day == (offset ?? 0)
                    )
                    .containerRelativeFrame(.horizontal)
                    .id(day)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $offset)
        .onAppear {
            // Land on today without animating in from the start of the range.
            if offset == nil { offset = 0 }
        }
    }

    /// The chevrons in each page's header. `step(0)` returns to today, which is
    /// why this takes a delta rather than a direction.
    private func step(_ delta: Int) {
        let current = offset ?? 0
        let target = delta == 0 ? 0 : max(-Self.reach, min(Self.reach, current + delta))
        guard target != current else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            offset = target
        }
    }
}
