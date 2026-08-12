//
//  Ruling.swift
//  Askcal
//
//  The ruled lines, and the rule that decides where they go.
//
//  Rules are drawn *by the row that sits on them*, not as a fixed grid painted
//  behind the page. This is the whole trick. A background grid has to guess the
//  text's line height, and it guesses wrong the moment anything changes it —
//  a two-line task title, a larger Dynamic Type setting, a different face. Text
//  floating a few points off its rule is precisely the "not quite right" look
//  this design exists to remove, and it is the failure mode that only shows up
//  on someone else's accessibility settings.
//
//  Drawing the rule as the row's own bottom edge makes alignment structural:
//  there is no measurement to get wrong. The blank ruling that continues below
//  the last entry is the only place a fixed step is used, and nothing sits on
//  it, so drift there costs nothing.
//

import SwiftUI

enum Ruling {
    /// The step for *blank* ruling. Scaled so empty ruling stays in proportion
    /// to the writing above it rather than crowding it at large type sizes.
    static var lineHeight: CGFloat {
        UIFontMetrics.default.scaledValue(for: 30)
    }
}

// MARK: - A row that sits on its rule

private struct Ruled: ViewModifier {
    @Environment(\.book) private var book

    func body(content: Content) -> some View {
        content
            // A rule on a page runs the width of the page. Without this the
            // overlay takes the row's intrinsic width, so a short line of text
            // got a short rule and the ruling came out ragged wherever the
            // content didn't happen to fill the measure.
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(book.rule)
                    .frame(height: Stroke.hair)
            }
    }
}

extension View {
    /// Draw this row's ruled line beneath it. Alignment is guaranteed because
    /// the line is the row's own edge.
    func ruled() -> some View { modifier(Ruled()) }
}

// MARK: - Blank ruling below the writing

/// Ruling that continues past the last entry, so a short day still reads as a
/// page you haven't filled rather than as a list that stopped early.
struct RuledFiller: View {
    var lines: Int = PaperTexture.fillerRules
    @Environment(\.book) private var book

    var body: some View {
        if lines > 0 {
            VStack(spacing: 0) {
                ForEach(0..<lines, id: \.self) { _ in
                    Rectangle()
                        .fill(book.rule)
                        .frame(height: Stroke.hair)
                        .frame(height: Ruling.lineHeight, alignment: .bottom)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// A standalone rule between blocks that aren't rows — the divisions on a
/// settings page, say, where there is no entry to hang a line off.
struct PageRule: View {
    @Environment(\.book) private var book

    var body: some View {
        Rectangle()
            .fill(book.rule)
            .frame(height: Stroke.hair)
            .accessibilityHidden(true)
    }
}

