//
//  Paper.swift
//  Askcal
//
//  The palette. Semantic roles, not colour names — a view asks for `rule`
//  because it is drawing a ruled line, never for "light brown", so a theme can
//  move underneath every screen without a single call site changing.
//
//  Paper, and warm. The surfaces carry the cream-to-tan cast of a book page
//  rather than the cool green-slate they used to, because the app is a notebook
//  now: you write the day down, you rule it off, you turn the page. A cool grey
//  readout could belong to anything; this could only be a notebook.
//
//  Contrast ratios are measured and written down because they are a promise.
//  `inkSub` is the floor for anything a person has to read, and it clears 4.5:1
//  against *every* ground it can land on — page, card and recessed well — not
//  just against the page. Two earlier candidates passed on paper and quietly
//  failed on one of the other two, which is exactly the kind of thing that only
//  shows up on someone else's screen.
//

import SwiftUI

enum ThemeMode: String, CaseIterable {
    case day, night

    var label: String {
        switch self {
        case .day: return "Day"
        case .night: return "Night"
        }
    }

    /// One line on what the theme is for, shown under the label in Settings.
    var note: String {
        switch self {
        case .day: return "Cream page, ruled in sepia"
        case .night: return "Blackboard, chalk writing"
        }
    }

    var polarity: ColorScheme {
        self == .day ? .light : .dark
    }

    /// Read a stored preference, tolerating every name these themes have had.
    ///
    /// They were "light"/"dark", then "paper"/"slate", now "day"/"night", and
    /// all four strings are sitting in UserDefaults on some install somewhere.
    /// Without this mapping anyone who had chosen the dark one silently lands
    /// back on light after updating — a preference lost with no way to tell it
    /// happened.
    static func stored(_ raw: String) -> ThemeMode {
        switch raw {
        case "light", "paper": return .day
        case "dark", "slate": return .night
        default: return ThemeMode(rawValue: raw) ?? .day
        }
    }

    static let storageDefault = ThemeMode.day.rawValue
}

struct PaperPalette: Equatable {
    // ── Surfaces, sunken → raised ────────────────────────────────────────
    let paper: Color      // the page itself
    let recessed: Color   // sunken: section headers, skeleton blocks, wells
    let card: Color       // raised: cards, sheets

    // ── The ruling ───────────────────────────────────────────────────────
    let rule: Color       // the ruled baselines and every divider
    let ruleStrong: Color // emphasis borders
    let margin: Color     // the margin rule down the left — the one warm accent

    // ── Ink, brightest → dimmest ─────────────────────────────────────────
    let ink: Color        // primary text
    let inkDim: Color     // secondary text
    let inkSub: Color     // tertiary: meta, captions, timestamps

    // ── The book itself ──────────────────────────────────────────────────
    let board: Color      // the cover behind the page; the iPad backdrop
    let binding: Color    // the wire

    // ── Inversion: filled buttons, checked marks ─────────────────────────
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

    static let dayTheme = PaperPalette(
        paper: Color(hex: "#F5F0E6"),
        recessed: Color(hex: "#E8E1D3"),
        card: Color(hex: "#FBF8F1"),
        rule: Color(hex: "#CFC5AE"),       //  1.51:1 — faint by design
        ruleStrong: Color(hex: "#B3A98F"), //  2.06:1
        margin: Color(hex: "#B4654A"),     //  3.77:1 — a line, never text
        ink: Color(hex: "#2A2724"),        // 13.07:1
        inkDim: Color(hex: "#57514A"),     //  6.90:1
        inkSub: Color(hex: "#6A635A"),     //  5.22:1 page · 5.58 card · 4.55 well
        board: Color(hex: "#3E362C"),
        binding: Color(hex: "#8A7A63"),
        fill: Color(hex: "#2A2724"),
        fillText: Color(hex: "#F5F0E6"),
        swipeConfirm: Color(hex: "#2A2724"),
        swipeSnooze: Color(hex: "#6A635A"),
        sceneWall: Color(hex: "#EDE6D8"),
        sceneWallLo: Color(hex: "#DED5C2"),
        sceneSky: Color(hex: "#E2E0D4"),
        sceneSkyLo: Color(hex: "#F1E7D6"),
        sceneCloud: Color(hex: "#FAF6EC"),
        sceneInk: Color(hex: "#2A2724")
    )

    /// A blackboard, not a dimmed page. The first dark theme was the day
    /// palette turned down — warm brown-black, which reads as a sepia
    /// photograph of paper rather than as its own surface. This is slate:
    /// cooler, darker, and chalk rather than ink on top of it.
    static let nightTheme = PaperPalette(
        paper: Color(hex: "#16191B"),
        recessed: Color(hex: "#101314"),   // sunken — still the darkest
        card: Color(hex: "#1E2224"),       // raised is the *lightest* under dark
        rule: Color(hex: "#2E3336"),       //  1.38:1 — chalk dust, barely there
        ruleStrong: Color(hex: "#454B4E"), //  1.99:1
        margin: Color(hex: "#9C5B47"),     //  3.37:1 — a line, never text
        ink: Color(hex: "#E9ECE9"),        // 14.84:1  chalk, not white
        inkDim: Color(hex: "#B2B8B5"),     //  8.76:1
        inkSub: Color(hex: "#949B98"),     //  6.22:1 page · 5.65 card · 6.58 well
        board: Color(hex: "#0A0C0D"),
        binding: Color(hex: "#5A6265"),
        fill: Color(hex: "#E9ECE9"),
        fillText: Color(hex: "#16191B"),
        swipeConfirm: Color(hex: "#2E3336"),
        swipeSnooze: Color(hex: "#454B4E"),
        sceneWall: Color(hex: "#1B1F21"),
        sceneWallLo: Color(hex: "#121517"),
        sceneSky: Color(hex: "#0D1113"),
        sceneSkyLo: Color(hex: "#1A2124"),
        sceneCloud: Color(hex: "#252B2E"),
        sceneInk: Color(hex: "#E9ECE9")
    )

    static func palette(for mode: ThemeMode) -> PaperPalette {
        mode == .day ? .dayTheme : .nightTheme
    }

}

private struct PaperPaletteKey: EnvironmentKey {
    static let defaultValue: PaperPalette = .dayTheme
}

extension EnvironmentValues {
    var book: PaperPalette {
        get { self[PaperPaletteKey.self] }
        set { self[PaperPaletteKey.self] = newValue }
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
