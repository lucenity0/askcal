//
//  MonoType.swift
//  Pulse
//
//  Serif (New York) for large titles at restrained weights, SF for body,
//  SF Mono for metadata. Nothing overly bold.
//
//  All sizes scale with Dynamic Type via UIFontMetrics — .system(size:)
//  alone is fixed-size and ignores the user's accessibility setting.
//  Containment (lineLimit + minimumScaleFactor) lives at the call sites.
//

import SwiftUI

enum MonoType {
    private static func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics.default.scaledValue(for: size)
    }

    /// Large screen titles — "07.Mon", "Calendar"
    static func title(_ size: CGFloat = 34) -> Font {
        .system(size: scaled(size), weight: .semibold, design: .serif)
    }

    /// Small label above titles — "July 7", "My notes"
    static func kicker(_ size: CGFloat = 13) -> Font {
        .system(size: scaled(size), weight: .regular)
    }

    /// Task/item titles
    static func item(_ size: CGFloat = 15) -> Font {
        .system(size: scaled(size), weight: .medium)
    }

    /// Body / secondary copy
    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: scaled(size), weight: .regular)
    }

    /// Metadata — times, durations, counts
    static func meta(_ size: CGFloat = 11) -> Font {
        .system(size: scaled(size), weight: .regular, design: .monospaced)
    }
}
