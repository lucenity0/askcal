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
    ///
    /// Kept narrow on purpose. At 26pt the spine took nearly 7% of a phone's
    /// width as a solid dark slab and became the loudest thing on a page whose
    /// whole point is the writing.
    static let bindingWidth: CGFloat = 14
    /// Distance between rings, centre to centre.
    static let ringSpacing: CGFloat = 30
    /// How tall a single loop of wire stands.
    static let ringHeight: CGFloat = 15
    /// Thickness of the wire itself.
    static let wireWidth: CGFloat = 1.8
    /// Where the spine stops being solid and starts falling away into the page.
    /// A hard edge reads as a black bar stuck to the side of the screen; a soft
    /// one reads as paper curving into the binding.
    static let spineFalloff: Double = 0.55

    // ── Ruling ───────────────────────────────────────────────────────────
    /// The margin rule is a guide, not a border — it should be visible without
    /// ever competing with what is written next to it.
    static let marginOpacity: Double = 0.55
    /// Blank ruling below the last entry, so a short day still reads as a page
    /// rather than as a list that stopped early. 0 ends the ruling at the last
    /// entry.
    static let fillerRules: Int = 6
}
