//
//  Spread.swift
//  Askcal
//
//  The notebook opened flat: one page, or two facing pages.
//
//  Every screen goes through here, so how the app uses a wide window is decided
//  once rather than per screen. Before this, one screen had a spread and the
//  rest were a phone layout stretched across an iPad — the writing pinned to the
//  left edge with a third of the paper doing nothing.
//
//  It measures the container rather than reading the size class. Size class is
//  a coarse signal about the *device*: an iPad in Split View reports regular at
//  widths where two pages will not fit, and compact at widths where they would.
//  The only thing that actually decides whether a spread works is how many
//  points there are, so that is what gets asked.
//

import SwiftUI

/// When the notebook is wide enough to open flat.
///
/// Non-generic so anything can ask. The root needs the same answer: a popup
/// there would dim a page that had room to stay visible.
enum SpreadMetrics {
    /// Below this, two pages would each be narrower than a readable line and
    /// the spread stops being a spread. `Space.measure` is roughly one page of
    /// text; two of those plus gutters is where folding it open becomes an
    /// improvement rather than a squeeze.
    static let threshold: CGFloat = Space.measure * 2 + Space.gutter * 4
}

struct Spread<Left: View, Right: View>: View {
    /// The page that is always there. Told whether a facing page exists, so it
    /// can drop anything that page is already showing.
    @ViewBuilder var left: (Bool) -> Left
    /// The facing page, shown only when there is genuinely room for it.
    @ViewBuilder var right: () -> Right

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= SpreadMetrics.threshold {
                HStack(spacing: 0) {
                    left(true)
                        .frame(maxWidth: .infinity)
                    // Two sheets meeting, not a sidebar divider — a fold, so a
                    // hairline rule rather than a piece of chrome.
                    Rectangle()
                        .fill(Color.clear)
                        .overlay(alignment: .center) { PageFold() }
                        .frame(width: Stroke.hair)
                        .ignoresSafeArea()
                    right()
                        .frame(maxWidth: .infinity)
                }
            } else {
                left(false)
            }
        }
    }
}

/// The fold between two facing pages.
private struct PageFold: View {
    @Environment(\.book) private var book

    var body: some View {
        Rectangle()
            .fill(book.rule)
            .frame(width: Stroke.hair)
    }
}

extension View {
    /// Centres a page's text block once the paper is much wider than a readable
    /// line, and leaves it against the left margin otherwise.
    ///
    /// A phone page is barely wider than its text, so left is the only sensible
    /// place for it. A full-width iPad page is not, and text hard against the
    /// left edge of a very wide sheet reads as a layout that failed rather than
    /// as a margin.
    func pageMeasure() -> some View {
        modifier(PageMeasure())
    }
}

private struct PageMeasure: ViewModifier {
    /// Deliberately no GeometryReader. One here would take all the height it is
    /// offered and report none back, so every page inside a ScrollView would
    /// collapse — and the condition it would be measuring answers itself: on a
    /// phone the cap is wider than the screen, so centring a block that already
    /// fills the width does nothing at all.
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: Space.measure, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
