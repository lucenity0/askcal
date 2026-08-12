//
//  BookType.swift
//  Askcal
//
//  Two faces, split by what the text *is*.
//
//    New York (serif)  anything written: entries, headings, body, the date
//    SF Mono           anything measured: times, counts, deadlines, labels
//
//  This split is the single biggest lever on whether the app reads as a page or
//  as an instrument panel. Mono body copy was a deliberate choice once — the
//  app was a readout and mono said so. It is a notebook now, and a notebook is
//  written in. So the serif carries the writing and mono is demoted to the
//  things that genuinely are data, where its fixed advance actually earns its
//  keep: a column of times lines up, a column of sentences shouldn't have to.
//
//  New York rather than a bundled book face because it ships with the system:
//  no ~450KB in the bundle, no licence file, and it already carries the full
//  Dynamic Type range. Bundling something later is a swap of these six
//  functions and nothing else.
//
//  All sizes scale via UIFontMetrics — .system(size:) alone is fixed and
//  ignores the user's accessibility setting. Containment (lineLimit +
//  minimumScaleFactor) lives at the call sites.
//

import SwiftUI

enum BookType {
    private static func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics.default.scaledValue(for: size)
    }

    /// The date headline — "12.Wed". The largest thing on the page.
    static func display(_ size: CGFloat = 34) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .serif)
    }

    /// In-page headings — a section that owns a screen.
    static func heading(_ size: CGFloat = 22) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .serif)
    }

    /// An entry: a task, an email subject, a routine. The thing you wrote.
    static func entry(_ size: CGFloat = 17) -> Font {
        .system(size: scaled(size), weight: .regular, design: .serif)
    }

    /// Running copy — explanations, empty states, snippets.
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: scaled(size), weight: .regular, design: .serif)
    }

    /// Measured things: times, durations, counts, deadlines. Mono earns its
    /// place here — a column of these lines up.
    static func meta(_ size: CGFloat = 11) -> Font {
        .system(size: scaled(size), weight: .regular, design: .monospaced)
    }

    /// The small label above a heading, and section rubrics in the margin.
    static func kicker(_ size: CGFloat = 12) -> Font {
        .system(size: scaled(size), weight: .regular, design: .monospaced)
    }

    /// SF Symbol glyphs.
    ///
    /// Exists because ten call sites reached for a bare `.system(size:)`, which
    /// is *not* Dynamic-Type scaled — so at large accessibility sizes the icons
    /// stayed put while the text beside them grew, and the two visibly came
    /// apart.
    static func icon(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight)
    }
}
