//
//  MonoTheme.swift
//  Pulse
//
//  Monochrome design system (pulse-ui-spec.md). Two themes, zero accent
//  colors — state is conveyed by shape, fill, weight and iconography only.
//

import SwiftUI

enum ThemeMode: String, CaseIterable {
    case light, dark

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct MonoPalette: Equatable {
    let bg: Color            // screen background
    let surface: Color       // cards
    let textPrimary: Color
    let textSecondary: Color
    let border: Color        // hairlines, outlines
    let fill: Color          // active/filled elements
    let fillText: Color      // text on filled elements
    let railInactive: Color  // inactive rail tabs
    // Swipe-action panels: SwiftUI forces the glyph white, so these must stay
    // dark in BOTH themes (a white `fill` panel hid the tick in dark mode).
    let swipeConfirm: Color
    let swipeSnooze: Color

    static let light = MonoPalette(
        bg: Color(hex: "#FFFFFF"),
        surface: Color(hex: "#F7F7F7"),
        textPrimary: Color(hex: "#000000"),
        textSecondary: Color(hex: "#6B6B6B"),
        border: Color(hex: "#E5E5E5"),
        fill: Color(hex: "#000000"),
        fillText: Color(hex: "#FFFFFF"),
        railInactive: Color(hex: "#EDEDED"),
        swipeConfirm: Color(hex: "#000000"),
        swipeSnooze: Color(hex: "#6B6B6B")
    )

    static let dark = MonoPalette(
        bg: Color(hex: "#000000"),
        surface: Color(hex: "#111111"),
        textPrimary: Color(hex: "#FFFFFF"),
        textSecondary: Color(hex: "#A0A0A0"),
        border: Color(hex: "#2A2A2A"),
        fill: Color(hex: "#FFFFFF"),
        fillText: Color(hex: "#000000"),
        railInactive: Color(hex: "#1A1A1A"),
        swipeConfirm: Color(hex: "#3A3A3A"),
        swipeSnooze: Color(hex: "#4A4A4A")
    )

    static func palette(for mode: ThemeMode) -> MonoPalette {
        mode == .light ? .light : .dark
    }
}

private struct MonoPaletteKey: EnvironmentKey {
    static let defaultValue: MonoPalette = .light
}

extension EnvironmentValues {
    var mono: MonoPalette {
        get { self[MonoPaletteKey.self] }
        set { self[MonoPaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            (r, g, b) = (Double((int >> 16) & 0xFF) / 255,
                         Double((int >> 8) & 0xFF) / 255,
                         Double(int & 0xFF) / 255)
        default:
            (r, g, b) = (1, 1, 1)
        }
        self.init(red: r, green: g, blue: b)
    }
}
