//
//  MonoMetrics.swift
//  Askcal
//
//  Geometry tokens. MonoTheme covers colour and MonoType covers type; nothing
//  covered spacing, so the app had accumulated 15 distinct `spacing:` values,
//  7 corner radii and 5 line widths — and the 22pt page gutter was written out
//  by hand in eleven files, which meant changing the gutter required finding
//  all eleven.
//
//  The scale is 2/4/6/8/12/16/22/34: a 4pt base with two half-steps at the
//  small end, where hairline work actually needs them.
//

import CoreGraphics

enum MonoSpace {
    /// Hairline gaps — between a glyph and its label.
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16

    /// The page gutter. Every screen's horizontal inset, one number.
    static let gutter: CGFloat = 22

    /// Vertical rhythm between major sections.
    static let section: CGFloat = 34

    /// Bottom padding that clears the floating action button. Scroll content
    /// that ignores this ends with its last row trapped under the FAB.
    static let fabClearance: CGFloat = 100
}

enum MonoRadius {
    /// Checkboxes and other small marks.
    static let mark: CGFloat = 4
    /// Timeline blocks, inputs, wells.
    static let block: CGFloat = 10
    /// Cards and sheets.
    static let card: CGFloat = 14
    /// Pills and capsules — anything fully rounded.
    static let pill: CGFloat = 100
}

enum MonoStroke {
    /// Hairlines: dividers, card borders.
    static let hair: CGFloat = 1
    /// Emphasis borders — the focused card.
    static let strong: CGFloat = 1.5
}
