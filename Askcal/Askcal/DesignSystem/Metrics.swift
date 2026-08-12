//
//  Metrics.swift
//  Askcal
//
//  Geometry tokens. Paper covers colour and BookType covers type; nothing
//  covered spacing, so the app had accumulated 15 distinct `spacing:` values,
//  7 corner radii and 5 line widths — and the 22pt page gutter was written out
//  by hand in eleven files, which meant changing the gutter required finding
//  all eleven.
//
//  The scale is 2/4/6/8/12/16/22/34: a 4pt base with two half-steps at the
//  small end, where hairline work actually needs them.
//

import CoreGraphics

enum Space {
    /// Hairline gaps — between a glyph and its label.
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16

    /// The page gutter: where the text block starts, measured from the paper's
    /// edge. Sits clear of the margin rule rather than on top of it.
    static let gutter: CGFloat = 22

    /// Distance from the paper's leading edge to the margin rule. Entries begin
    /// after it; only checkboxes and priority marks live to its left.
    static let margin: CGFloat = 50

    /// The visible width of an entry's mark — the checkbox. Marks belong to the
    /// entry but not to its text, which is what a notebook's margin is for.
    static let markColumn: CGFloat = 26

    /// Where the writing starts: clear of the margin rule, never on it.
    static var textInset: CGFloat { margin + lg }

    /// How far a mark reaches back from the text inset, so it lands in the band
    /// between the binding and the rule with clearance on both sides.
    ///
    /// Derived rather than written down: the mark used to sit at a hand-picked
    /// offset and ended up underneath the spine. Expressed this way the binding
    /// can change width — or be turned off entirely — and the mark still lands
    /// somewhere sensible.
    static var markReach: CGFloat {
        margin + lg - PaperTexture.bindingWidth - sm
    }

    /// Vertical rhythm between major sections.
    static let section: CGFloat = 34

    /// Bottom padding that clears the floating action button. Scroll content
    /// that ignores this ends with its last row trapped under the FAB.
    static let fabClearance: CGFloat = 100
}

enum Radius {
    /// Checkboxes and other small marks.
    static let mark: CGFloat = 4
    /// Timeline blocks, inputs, wells.
    static let block: CGFloat = 10
    /// Cards and sheets.
    static let card: CGFloat = 14
    /// Pills and capsules — anything fully rounded.
    static let pill: CGFloat = 100
}

enum Stroke {
    /// The ruled lines, dividers, card borders.
    static let hair: CGFloat = 1
    /// Emphasis borders — the focused card.
    static let strong: CGFloat = 1.5
}
