//
//  PaperTexture.swift
//  Askcal
//
//  Every knob on the notebook, in one file.
//
//  Grain and binding are the parts of this design most likely to want dialling
//  back once they're on a real screen for a week — texture that reads as
//  character on day one can read as noise on day thirty. Keeping the numbers
//  here means that adjustment is one edit to one file, not a hunt through
//  views, and it means turning a feature *off* is setting it to zero rather
//  than deleting code.
//
//  Set `grainOpacity` to 0 for clean paper; set `bindingWidth` to 0 for an
//  unbound pad. Both are honoured everywhere without further change.
//

import CoreGraphics

enum PaperTexture {

    // ── Grain ────────────────────────────────────────────────────────────
    /// How much tooth the paper has. Deliberately small: the tile is composited
    /// over every screen, and anything you can consciously see here is
    /// competing with the text for attention rather than supporting it.
    static let grainOpacity: Double = 0.055

    // ── Binding ──────────────────────────────────────────────────────────
    /// Width of the bound edge. 0 removes the binding entirely.
    static let bindingWidth: CGFloat = 26
    /// Distance between rings, centre to centre.
    static let ringSpacing: CGFloat = 34
    /// How tall a single loop of wire stands.
    static let ringHeight: CGFloat = 19
    /// Thickness of the wire itself.
    static let wireWidth: CGFloat = 2

    // ── Ruling ───────────────────────────────────────────────────────────
    /// The margin rule is a guide, not a border — it should be visible without
    /// ever competing with what is written next to it.
    static let marginOpacity: Double = 0.55
    /// Blank ruling below the last entry, so a short day still reads as a page
    /// rather than as a list that stopped early. 0 ends the ruling at the last
    /// entry.
    static let fillerRules: Int = 6
}
