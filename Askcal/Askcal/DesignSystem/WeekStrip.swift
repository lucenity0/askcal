//
//  WeekStrip.swift
//  Askcal
//
//  Seven days across the top, and the way you move between them.
//
//  This replaces a full-screen horizontal page turn. Paging the whole day
//  sideways meant the only way to see what was on Thursday was to travel there
//  and look, one day at a time, with the current day sliding out from under you
//  every time. A strip shows the week at once, says which days have anything on
//  them before you go, and moves in a single tap.
//

import SwiftUI

struct WeekStrip: View {
    @Binding var selected: Date
    /// Days that have something on them, keyed by `AskcalStore.dayString`.
    var marked: Set<String> = []

    @Environment(\.book) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("weekStripExpanded") private var expanded = true

    private var cal: Calendar { Calendar.current }

    /// The seven days of `selected`'s week, in this locale's order.
    private var week: [Date] {
        guard let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start
        else { return [selected] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// The month the week mostly sits in. A week that straddles a month
    /// boundary would otherwise flicker its label depending on which day you
    /// had selected.
    private var monthLabel: String {
        let middle = week.count == 7 ? week[3] : selected
        return middle.formatted(.dateTime.month(.wide)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            heading

            if expanded {
                HStack(spacing: 0) {
                    chevron("chevron.left", label: "Previous week", weeks: -1)
                    ForEach(week, id: \.timeIntervalSince1970) { day in
                        dayCell(day)
                    }
                    chevron("chevron.right", label: "Next week", weeks: 1)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // The strip used to end in mid-air with the date heading right
            // under it and nothing between them, so it read as floating rather
            // than as a band the page begins with.
            PageRule()
        }
        .clipped()   // the collapsing row must not draw past the rule
        .accessibilityElement(children: .contain)
    }

    /// The month, and the control that folds the week away. Collapsed, the day
    /// gets the room back; the choice is remembered, because whichever way you
    /// prefer it you will prefer it every time.
    private var heading: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: Space.md) {
                Text(monthLabel)
                    .font(BookType.meta(10))
                    .tracking(1.2)
                    .foregroundStyle(book.inkSub)
                if !expanded {
                    Text(selected.formatted(.dateTime.weekday(.abbreviated).day()))
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkDim)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(BookType.icon(10))
                    .foregroundStyle(book.inkSub)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weekStripToggle")
        .accessibilityLabel(expanded ? "Hide the week" : "Show the week")
        .accessibilityValue(monthLabel)
    }

    private func chevron(_ symbol: String, label: String, weeks: Int) -> some View {
        Button {
            step(weeks: weeks)
        } label: {
            Image(systemName: symbol)
                .font(BookType.icon(12))
                .foregroundStyle(book.inkSub)
                .frame(width: 26, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let hasWork = marked.contains(AskcalStore.dayString(day))

        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                selected = cal.startOfDay(for: day)
            }
            Haptics.tick()
        } label: {
            VStack(spacing: Space.hair) {
                Text(day.formatted(.dateTime.day()))
                    .font(BookType.entry(17))
                    .foregroundStyle(isSelected ? book.ink : book.inkDim)
                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
                // Reserved whether or not it is drawn, so selecting a day
                // never nudges the whole strip up or down by four points.
                Circle()
                    .fill(hasWork ? book.inkSub : .clear)
                    .frame(width: 4, height: 4)
                    .padding(.top, Space.hair)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.md)
            .background {
                if isSelected {
                    Capsule().fill(book.recessed)
                } else if isToday {
                    Capsule().strokeBorder(book.rule, lineWidth: Stroke.hair)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(hasWork ? "has work" : "clear")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func step(weeks: Int) {
        guard let moved = cal.date(byAdding: .weekOfYear, value: weeks, to: selected)
        else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            selected = cal.startOfDay(for: moved)
        }
    }
}
