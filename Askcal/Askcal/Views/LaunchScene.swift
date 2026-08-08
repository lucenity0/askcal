//
//  LaunchScene.swift
//  Askcal
//
//  Askcal's illustration: a cat asleep on a desk at first light.
//
//  A cousin to the café windowsill, not a copy of it. Same construction — one
//  pixel grid, a room painted from the theme's own --scene tokens, a drawn cat
//  laid into it, and motion slow enough that you notice it only if you wait —
//  but a different room, chosen because this app is about the morning: the
//  desk is set for a day that hasn't started, the sky behind it is going from
//  night to dawn, and the cat has not moved yet.
//
//  Drawn rather than shipped as frames. A gif would have been simpler, but the
//  room has to follow the theme ladder — the window turns to night under
//  Slate — and a picture cannot do that.
//
//  Everything is expressed on a SCENE_W x SCENE_H grid and scaled as one
//  drawing, so the cat never drifts off the books when the frame resizes.
//

import SwiftUI

struct LaunchScene: View {
    /// The grid. Every coordinate below is in these units, never in points.
    ///
    /// The ratio is close to the frame it sits in on purpose: at 160x116 the
    /// scene letterboxed inside a wider box and everything in it — the cat
    /// especially — rendered too small to read as anything.
    static let W: CGFloat = 160
    static let H: CGFloat = 96

    @Environment(\.mono) private var mono
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, size in
                // One scale for the whole drawing; the room and the cat share
                // it, which is the only reason they stay registered.
                let u = min(size.width / Self.W, size.height / Self.H)
                let ox = (size.width - Self.W * u) / 2
                let oy = (size.height - Self.H * u) / 2

                func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    ctx.fill(
                        Path(CGRect(x: ox + x * u, y: oy + y * u, width: w * u, height: h * u)),
                        with: .color(c)
                    )
                }

                // Reduced motion freezes the clock rather than the drawing, so
                // the scene still renders — just never changes.
                let t = reduceMotion
                    ? 0
                    : timeline.date.timeIntervalSinceReferenceDate

                draw(px: px, t: t)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            "A cat asleep on a stack of notebooks on a desk, beside a lamp and a "
            + "steaming mug, with dawn coming up through the window."
        )
    }

    // MARK: - The room

    private func draw(
        px: (CGFloat, CGFloat, CGFloat, CGFloat, Color) -> Void,
        t: TimeInterval
    ) {
        let wall = mono.sceneWall
        let wallLo = mono.sceneWallLo
        let sky = mono.sceneSky
        let skyLo = mono.sceneSkyLo
        let cloud = mono.sceneCloud
        let ink = mono.sceneInk

        // Wall, and a skirting line to stand the room up.
        px(0, 0, Self.W, Self.H, wall)
        px(0, 90, Self.W, 1, mono.rule)
        px(0, 91, Self.W, Self.H - 91, wallLo)

        // ── Window ───────────────────────────────────────────────────────
        // High on the wall so the cat, which sits in front of it, never
        // overlaps the sill — the two shapes touching read as one object.
        let wx: CGFloat = 16, wy: CGFloat = 8, ww: CGFloat = 78, wh: CGFloat = 44

        // Sky: two bands, dawn coming up from the horizon.
        px(wx, wy, ww, wh, sky)
        px(wx, wy + wh * 0.62, ww, wh * 0.38, skyLo)

        // Clouds drift right, wrapping. Two at different speeds so the window
        // has depth rather than one sliding sheet.
        drawCloud(px: px, x: wx + wrap(t * 1.6, ww + 30) - 15, y: wy + 10, w: 22, c: cloud, wx: wx, ww: ww)
        drawCloud(px: px, x: wx + wrap(t * 0.9 + 40, ww + 30) - 15, y: wy + 24, w: 15, c: cloud, wx: wx, ww: ww)

        // A bird, occasionally. It crosses, then is gone for a long while —
        // motion you catch only if you happen to be looking.
        let birdCycle = t.truncatingRemainder(dividingBy: 14)
        if birdCycle < 4 {
            let bx = wx + CGFloat(birdCycle / 4) * ww
            let by = wy + 8 + sin(birdCycle * 3) * 2
            if bx > wx + 1 && bx < wx + ww - 4 {
                px(bx, by, 2, 1, ink.opacity(0.55))
                px(bx + 2, by - 1, 2, 1, ink.opacity(0.55))
            }
        }

        // Frame + mullions, drawn last so nothing overlaps them.
        strokeRect(px: px, x: wx, y: wy, w: ww, h: wh, c: ink)
        px(wx + ww / 2 - 1, wy, 2, wh, ink)
        px(wx, wy + wh / 2 - 1, ww, 2, ink)
        // Sill
        px(wx - 3, wy + wh, ww + 6, 2, ink)

        // ── Desk ─────────────────────────────────────────────────────────
        let deskY: CGFloat = 78
        px(6, deskY, Self.W - 12, 2, ink)
        px(6, deskY + 2, Self.W - 12, 4, wallLo)
        // Legs
        px(12, deskY + 6, 2, 6, ink)
        px(Self.W - 14, deskY + 6, 2, 6, ink)

        // ── Notebook stack, the cat's bed ────────────────────────────────
        px(22, deskY - 4, 40, 4, ink)
        px(24, deskY - 7, 38, 3, wallLo)
        px(24, deskY - 7, 38, 1, ink)
        px(26, deskY - 10, 36, 3, ink)

        // ── Lamp ─────────────────────────────────────────────────────────
        px(122, deskY - 26, 2, 26, ink)          // stem
        px(112, deskY - 34, 22, 3, ink)          // shade top
        px(114, deskY - 31, 18, 5, ink)          // shade
        px(116, deskY - 26, 14, 1, ink.opacity(0.35))  // spill
        px(118, deskY - 2, 10, 2, ink)           // base

        // ── Mug, with steam ──────────────────────────────────────────────
        let mx: CGFloat = 96
        px(mx, deskY - 9, 12, 9, ink)
        px(mx + 12, deskY - 7, 3, 4, ink)        // handle
        for i in 0..<3 {
            let phase = t * 0.9 + Double(i) * 0.8
            let rise = CGFloat(phase.truncatingRemainder(dividingBy: 3.0)) * 4
            let sway = sin(phase * 1.6) * 1.5
            let fade = 0.5 - Double(rise) / 26.0
            if fade > 0.04 {
                px(mx + 3 + CGFloat(i) * 3 + sway, deskY - 12 - rise, 1, 2,
                   ink.opacity(fade))
            }
        }

        // ── The cat ──────────────────────────────────────────────────────
        // Breathing: the body lifts by one pixel on a slow cycle. One pixel is
        // the whole animation — at this scale it is exactly enough to read as
        // alive, and anything more read as twitching.
        let breath: CGFloat = sin(t * 1.15) > 0.35 ? 1 : 0
        drawCat(px: px, x: 24, y: deskY - 10 - 12 - breath, ink: ink, wall: wall)
    }

    // MARK: - Pieces

    /// A curled, sleeping cat: ears, a closed eye, tail wrapped to the front.
    ///
    /// Drawn as a loaf seen side-on, because at this size a realistic curl
    /// collapses into a blob — the ears and the tail are the only two shapes
    /// carrying "cat", so both sit clear of the body outline.
    private static let cat: [String] = [
        "   ##                       ##    ",
        "   ###                     ###    ",
        "   ####                   ####    ",
        "  ############################    ",
        " ##############################   ",
        "################################  ",
        "##+#############################  ",
        "################################# ",
        "################################# ",
        "################################  ",
        " ##############################   ",
        "  ###~~~~~~~~~~~~~~~~~~~~~~~~~    ",
    ]

    private func drawCat(
        px: (CGFloat, CGFloat, CGFloat, CGFloat, Color) -> Void,
        x: CGFloat, y: CGFloat, ink: Color, wall: Color
    ) {
        for (r, row) in Self.cat.enumerated() {
            for (c, ch) in row.enumerated() {
                let cx = x + CGFloat(c), cy = y + CGFloat(r)
                switch ch {
                case "#": px(cx, cy, 1, 1, ink)
                case "+": px(cx, cy, 1, 1, wall)          // the closed eye
                case "~": px(cx, cy, 1, 1, ink.opacity(0.65))  // tail, softer
                default: break
                }
            }
        }
    }

    private func drawCloud(
        px: (CGFloat, CGFloat, CGFloat, CGFloat, Color) -> Void,
        x: CGFloat, y: CGFloat, w: CGFloat, c: Color, wx: CGFloat, ww: CGFloat
    ) {
        // Clipped to the glass by hand: the canvas has no clip region here and
        // a cloud sliding across the wall would give the whole thing away.
        func band(_ bx: CGFloat, _ by: CGFloat, _ bw: CGFloat) {
            let left = max(bx, wx + 1)
            let right = min(bx + bw, wx + ww - 1)
            if right > left { px(left, by, right - left, 2, c) }
        }
        band(x, y, w)
        band(x + w * 0.22, y - 2, w * 0.55)
    }

    private func strokeRect(
        px: (CGFloat, CGFloat, CGFloat, CGFloat, Color) -> Void,
        x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, c: Color
    ) {
        px(x, y, w, 1, c)
        px(x, y + h - 1, w, 1, c)
        px(x, y, 1, h, c)
        px(x + w - 1, y, 1, h, c)
    }

    /// Position within a wrapping run of `span` units.
    private func wrap(_ v: Double, _ span: CGFloat) -> CGFloat {
        CGFloat(v.truncatingRemainder(dividingBy: Double(span)))
    }
}
