//
//  NotebookPage.swift
//  Askcal
//
//  One page of the notebook. Every screen is one of these.
//
//  This exists because the app had grown two design systems: the day surface
//  used one set of tokens and every screen you could reach from it used
//  another, with its own gutters and its own heading block. Tapping a row
//  landed you somewhere that looked like a different app. A single container is
//  the fix — the page is assembled in one place, so no screen can drift from
//  the others without changing this file.
//
//  The paper is the notebook. The spiral binding that used to run down the edge
//  is gone: it took real width on every screen, it was the loudest thing on a
//  page whose point is the writing, and it forced entries to hang their
//  checkboxes out into a margin — which is what put those checkboxes outside
//  their parent's hit-test bounds and stopped them working at all. Warm paper,
//  a serif, and ruled separators carry the character on their own.
//

import SwiftUI

struct NotebookPage<Content: View>: View {
    /// Off for pages whose content scrolls itself (a `List`, a timeline).
    var scrollable: Bool = true
    var onRefresh: (() async -> Void)?

    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            PaperSurface()
                .ignoresSafeArea()

            // `onRefresh` and `scrollable` decide which branch of an `if` builds
            // the page, so changing either at runtime destroys the whole scroll
            // view and builds a new one — every row, the scroll offset, all of
            // it. On screen that is a hard flash.
            //
            // Both are meant to be fixed for the life of a page. TodayPage once
            // flipped `onRefresh` to nil on any day but today, and that single
            // nil was the date-change blink that survived three attempts at
            // fixing the list and the animations. If a caller needs the gesture
            // to do different things on different days, vary what the closure
            // *does* — never whether it exists.
            if scrollable {
                if let onRefresh {
                    scroll.refreshable { await onRefresh() }
                } else {
                    scroll
                }
            } else {
                padded
            }
        }
    }

    private var scroll: some View {
        ScrollView(showsIndicators: false) {
            padded
        }
    }

    private var padded: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            content()
        }
        // A line of text stops being readable somewhere around 70 characters,
        // and an iPad page is far wider than that. The block keeps its measure
        // and sits in the middle of the paper — pinned to the left edge it read
        // as a layout that had failed rather than as a margin, with a third of
        // the sheet doing nothing.
        .pageMeasure()
        .padding(.horizontal, Space.gutter)
        .padding(.top, Space.md)
        .padding(.bottom, Space.xl)
    }
}

// MARK: - The heading block

/// The one heading hierarchy: a small weekday over the date in serif. Every
/// screen uses this; heading styles are never re-specified per page.
struct PageTitle<Trailing: View>: View {
    let kicker: String
    let title: String
    var size: CGFloat = 34
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.book) private var book

    init(
        kicker: String,
        title: String,
        size: CGFloat = 34,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.kicker = kicker
        self.title = title
        self.size = size
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(kicker)
                    .font(BookType.heading(17))
                    .foregroundStyle(book.inkDim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(BookType.display(size))
                    .foregroundStyle(book.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)  // shrink to fit, never clip
            }
            Spacer(minLength: Space.lg)
            trailing()
        }
    }
}

/// "Routine    3 of 5 ›" — a screen that lives elsewhere, summarised here so
/// the count is visible without the trip.
struct SettingsRow: View {
    let title: String
    let value: String
    @Environment(\.book) private var book

    var body: some View {
        HStack {
            Text(title)
                .font(BookType.entry(16))
                .foregroundStyle(book.ink)
            Spacer()
            Text(value)
                .font(BookType.meta())
                .foregroundStyle(book.inkSub)
            Image(systemName: "chevron.right")
                .font(BookType.icon(11))
                .foregroundStyle(book.inkSub)
        }
        .padding(.vertical, Space.lg)
        .contentShape(Rectangle())
        .ruled()
        // Title and value are a label and a value. Combining them produced
        // "Routine 3 of 5" as one string, which no test or VoiceOver user could
        // identify the row by.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityHint("Opens \(title)")
    }
}

/// A small mono rubric opening a section.
struct Rubric: View {
    let text: String
    @Environment(\.book) private var book

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(BookType.meta(10))
            .tracking(1.2)
            .foregroundStyle(book.inkSub)
    }
}
