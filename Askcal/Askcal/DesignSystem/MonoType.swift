//
//  MonoType.swift
//  Askcal
//
//  Two faces, one role each.
//
//    New York (serif)  display only — the date headline, page titles
//    SF Mono           everything else: items, meta, labels, chrome
//
//  The serif is the signature. "08.Sat" set in New York is the one thing on
//  screen that could not belong to any other app, so it stays; the mono
//  underneath it is what gives the rest the plain, instrument-panel quality
//  the design is after. Body copy in mono is a deliberate choice, not an
//  oversight — this app is a readout, and a proportional face made it look
//  like a document.
//
//  SF Mono rather than a bundled superfamily because it ships with the system:
//  no ~450KB of webfont in the bundle, no licence file, and it already carries
//  the full Dynamic Type range. Bundling Monaspace later is a swap of these
//  five functions and nothing else.
//
//  All sizes scale via UIFontMetrics — .system(size:) alone is fixed and
//  ignores the user's accessibility setting. Containment (lineLimit +
//  minimumScaleFactor) lives at the call sites.
//

import SwiftUI

enum MonoType {
    private static func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics.default.scaledValue(for: size)
    }

    /// Large screen titles — "08.Sat", "Calendar". The serif, and the only
    /// place it appears.
    static func title(_ size: CGFloat = 34) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .serif)
    }

    /// Small label above titles — "August 8", "Settings"
    static func kicker(_ size: CGFloat = 12) -> Font {
        .system(size: scaled(size), weight: .regular, design: .monospaced)
    }

    /// Task/item titles
    static func item(_ size: CGFloat = 15) -> Font {
        .system(size: scaled(size), weight: .medium, design: .monospaced)
    }

    /// Body / secondary copy
    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: scaled(size), weight: .regular, design: .monospaced)
    }

    /// Metadata — times, durations, counts
    static func meta(_ size: CGFloat = 11) -> Font {
        .system(size: scaled(size), weight: .regular, design: .monospaced)
    }

    /// SF Symbol glyphs.
    ///
    /// Exists because ten call sites reached for a bare `.system(size:)`,
    /// which is *not* Dynamic-Type scaled — so at large accessibility sizes
    /// the icons stayed put while the text beside them grew, and the two
    /// visibly came apart.
    static func icon(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: scaled(size), weight: weight)
    }
}
