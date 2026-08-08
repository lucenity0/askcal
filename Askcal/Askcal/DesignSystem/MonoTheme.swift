//
//  MonoTheme.swift
//  Askcal
//
//  The palette. Semantic roles, not colour names — a view asks for `rule`
//  because it is drawing a hairline, never for "light grey", so a theme can
//  move underneath every screen without a single call site changing.
//
//  Cool paper, deliberately. The surfaces carry a faint green-slate cast
//  rather than the warm cream they are cousins to, so the two products read
//  as the same hand without reading as the same app.
//
//  Contrast ratios are measured against that theme's own `paper` and written
//  down because they are a promise: `inkSub` is the floor for anything a
//  person has to read, and it sits at 4.6:1. Anything dimmer is decoration.
//

import SwiftUI

enum ThemeMode: String, CaseIterable {
    case paper, slate

    var label: String {
        switch self {
        case .paper: return "Paper"
        case .slate: return "Slate"
        }
    }

    /// One line on what the theme is for, shown under the label in Settings.
    var note: String {
        switch self {
        case .paper: return "Cool off-white, hairline rules"
        case .slate: return "Deep slate, chalk ink"
        }
    }

    var polarity: ColorScheme {
        self == .paper ? .light : .dark
    }

    /// Read a stored preference, tolerating the pre-rename values.
    ///
    /// The themes used to be called "light" and "dark", and that string is
    /// already sitting in UserDefaults on every install. Without this mapping
    /// anyone who had chosen dark would silently land back on the light theme
    /// after updating — a preference lost with no way to tell it happened.
    static func stored(_ raw: String) -> ThemeMode {
        switch raw {
        case "light": return .paper
        case "dark": return .slate
        default: return ThemeMode(rawValue: raw) ?? .paper
        }
    }

    static let storageDefault = ThemeMode.paper.rawValue
}

struct MonoPalette: Equatable {
    // ── Surfaces, sunken → raised ────────────────────────────────────────
    let paper: Color      // the page itself
    let recessed: Color   // sunken: section headers, skeleton blocks, wells
    let card: Color       // raised: cards, sheets

    // ── Hairlines ────────────────────────────────────────────────────────
    let rule: Color       // every divider and border
    let ruleStrong: Color // hover/emphasis borders

    // ── Ink, brightest → dimmest ─────────────────────────────────────────
    let ink: Color        // primary text
    let inkDim: Color     // secondary text
    let inkSub: Color     // tertiary: meta, captions, timestamps

    // ── Inversion: filled buttons, checked boxes, the FAB ────────────────
    let fill: Color
    let fillText: Color

    /// Swipe-action panels. SwiftUI forces the glyph white, so these must stay
    /// dark in BOTH themes — a pale panel hid the tick entirely.
    let swipeConfirm: Color
    let swipeSnooze: Color

    /// The launch scene paints itself from these, so the room follows the
    /// theme instead of being a picture pasted on top of it.
    let sceneWall: Color
    let sceneWallLo: Color
    let sceneSky: Color
    let sceneSkyLo: Color
    let sceneCloud: Color
    let sceneInk: Color

    static let paperTheme = MonoPalette(
        paper: Color(hex: "#EFEFED"),
        recessed: Color(hex: "#E4E4E1"),
        card: Color(hex: "#F7F7F6"),
        rule: Color(hex: "#C2C2BE"),      // 1.62:1
        ruleStrong: Color(hex: "#A6A6A1"), // 2.28:1
        ink: Color(hex: "#222422"),        // 11.2:1
        inkDim: Color(hex: "#4E514E"),     //  6.6:1
        inkSub: Color(hex: "#6A6D69"),     //  4.6:1
        fill: Color(hex: "#222422"),
        fillText: Color(hex: "#EFEFED"),
        swipeConfirm: Color(hex: "#222422"),
        swipeSnooze: Color(hex: "#6A6D69"),
        sceneWall: Color(hex: "#E7E7E3"),
        sceneWallLo: Color(hex: "#D8D8D3"),
        sceneSky: Color(hex: "#DCE3E4"),
        sceneSkyLo: Color(hex: "#EDE7DF"),
        sceneCloud: Color(hex: "#F4F4F1"),
        sceneInk: Color(hex: "#222422")
    )

    static let slateTheme = MonoPalette(
        paper: Color(hex: "#17191A"),
        recessed: Color(hex: "#101213"),   // sunken — still the darkest
        card: Color(hex: "#1E2122"),       // raised is the *lightest* under dark
        rule: Color(hex: "#3A3F41"),       // 1.74:1 — hairlines vanish on dark,
        ruleStrong: Color(hex: "#525859"), // 2.61:1   so these sit prouder
        ink: Color(hex: "#E7E9E7"),        // 13.9:1  chalk, not white
        inkDim: Color(hex: "#AFB4B2"),     //  7.1:1
        inkSub: Color(hex: "#8B918F"),     //  4.6:1
        fill: Color(hex: "#E7E9E7"),
        fillText: Color(hex: "#17191A"),
        swipeConfirm: Color(hex: "#3A3F41"),
        swipeSnooze: Color(hex: "#525859"),
        sceneWall: Color(hex: "#1E2224"),
        sceneWallLo: Color(hex: "#15181A"),
        sceneSky: Color(hex: "#0E1418"),
        sceneSkyLo: Color(hex: "#1A2026"),
        sceneCloud: Color(hex: "#242A2E"),
        sceneInk: Color(hex: "#E7E9E7")
    )

    static func palette(for mode: ThemeMode) -> MonoPalette {
        mode == .paper ? .paperTheme : .slateTheme
    }

    // ── Compatibility aliases ────────────────────────────────────────────
    // The old vocabulary, kept so every screen picks up the new palette
    // immediately and the rename can happen screen by screen instead of in
    // one unreviewable diff. Delete each as its call sites migrate.
    var bg: Color { paper }
    var surface: Color { card }
    var border: Color { rule }
    var textPrimary: Color { ink }
    var textSecondary: Color { inkDim }
    var railInactive: Color { recessed }
}

private struct MonoPaletteKey: EnvironmentKey {
    static let defaultValue: MonoPalette = .paperTheme
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
