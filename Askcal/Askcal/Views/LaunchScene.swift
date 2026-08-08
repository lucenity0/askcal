//
//  LaunchScene.swift
//  Askcal
//
//  Askcal's illustration: the cat asleep on a desk at first light.
//
//  The cat is the drawn artwork from Liffy — the same 40-frame sprite, not a
//  redrawing of it. The room around it is Askcal's: a desk set for a day that
//  hasn't started, dawn coming up through the window, a lamp still on. Same
//  construction as its cousin, different room.
//
//  Two layers on one pixel grid. The room is painted here and themes itself
//  off the palette's scene tokens — so the window turns to night under Slate —
//  while the cat stays the drawn artwork it is. Splitting them that way is
//  what lets the room follow the theme without the sprite having to.
//
//  Every coordinate is in grid units and the whole thing scales as one
//  drawing, which is the only reason the cat stays on the desk when the frame
//  resizes.
//

import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct LaunchScene: View {
    /// The grid. Matches the sprite's own scale — the cat is 128x108 of this.
    static let W: CGFloat = 320
    static let H: CGFloat = 232

    /// Where the cat sits: cushion resting exactly on the desk surface.
    static let catX: CGFloat = 104
    static let catY: CGFloat = 104
    static let catW: CGFloat = 128
    static let catH: CGFloat = 108
    static let deskY: CGFloat = 212

    @Environment(\.mono) private var mono
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let u = min(geo.size.width / Self.W, geo.size.height / Self.H)
            let ox = (geo.size.width - Self.W * u) / 2
            let oy = (geo.size.height - Self.H * u) / 2

            ZStack(alignment: .topLeading) {
                room(u: u, ox: ox, oy: oy)

                GIFPlayer(name: "launch-cat", paused: reduceMotion)
                    .frame(width: Self.catW * u, height: Self.catH * u)
                    .offset(x: ox + Self.catX * u, y: oy + Self.catY * u)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(
            "A cat asleep on a cushion on a desk, beside a lamp and a steaming "
            + "mug, with dawn coming up through the window."
        )
    }

    // MARK: - The room

    private func room(u: CGFloat, ox: CGFloat, oy: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: reduceMotion)) { timeline in
            Canvas { ctx, _ in
                func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: Color) {
                    ctx.fill(
                        Path(CGRect(x: ox + x * u, y: oy + y * u, width: w * u, height: h * u)),
                        with: .color(c)
                    )
                }
                let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                draw(px: px, t: t)
            }
        }
    }

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

        px(0, 0, Self.W, Self.H, wall)

        // ── Window ───────────────────────────────────────────────────────
        let wx: CGFloat = 26, wy: CGFloat = 22, ww: CGFloat = 132, wh: CGFloat = 74
        px(wx, wy, ww, wh, sky)
        px(wx, wy + wh * 0.58, ww, wh * 0.42, skyLo)   // dawn band on the horizon

        drawCloud(px: px, x: wx + wrap(t * 2.4, ww + 46) - 24, y: wy + 16, w: 34, c: cloud, wx: wx, ww: ww)
        drawCloud(px: px, x: wx + wrap(t * 1.3 + 70, ww + 46) - 24, y: wy + 38, w: 24, c: cloud, wx: wx, ww: ww)

        // A bird crosses now and then — motion you catch only if you wait.
        let cycle = t.truncatingRemainder(dividingBy: 16)
        if cycle < 5 {
            let bx = wx + CGFloat(cycle / 5) * ww
            let by = wy + 14 + sin(cycle * 3) * 3
            if bx > wx + 2 && bx < wx + ww - 6 {
                px(bx, by, 3, 1, ink.opacity(0.5))
                px(bx + 3, by - 1, 3, 1, ink.opacity(0.5))
            }
        }

        strokeRect(px: px, x: wx, y: wy, w: ww, h: wh, c: ink)
        px(wx + ww / 2 - 1, wy, 2, wh, ink)
        px(wx, wy + wh / 2 - 1, ww, 2, ink)
        px(wx - 4, wy + wh, ww + 8, 3, ink)            // sill

        // ── Desk ─────────────────────────────────────────────────────────
        px(10, Self.deskY, Self.W - 20, 3, ink)
        px(10, Self.deskY + 3, Self.W - 20, 6, wallLo)
        px(24, Self.deskY + 9, 3, Self.H - Self.deskY - 9, ink)
        px(Self.W - 27, Self.deskY + 9, 3, Self.H - Self.deskY - 9, ink)

        // ── Notebook stack, left of the cat ──────────────────────────────
        px(26, Self.deskY - 8, 58, 8, ink)
        px(30, Self.deskY - 14, 52, 6, wallLo)
        px(30, Self.deskY - 14, 52, 2, ink)
        px(34, Self.deskY - 20, 46, 6, ink)

        // ── Mug, with steam ──────────────────────────────────────────────
        let mx: CGFloat = 246
        px(mx, Self.deskY - 20, 22, 20, ink)
        px(mx + 22, Self.deskY - 15, 5, 8, ink)
        for i in 0..<3 {
            let phase = t * 0.85 + Double(i) * 0.9
            let rise = CGFloat(phase.truncatingRemainder(dividingBy: 3.2)) * 8
            let sway = sin(phase * 1.5) * 3
            let fade = 0.45 - Double(rise) / 60.0
            if fade > 0.04 {
                px(mx + 5 + CGFloat(i) * 6 + sway, Self.deskY - 26 - rise, 2, 4, ink.opacity(fade))
            }
        }

        // ── Lamp, still on ───────────────────────────────────────────────
        px(288, Self.deskY - 62, 3, 62, ink)
        px(268, Self.deskY - 78, 44, 6, ink)
        px(272, Self.deskY - 72, 36, 10, ink)
        px(276, Self.deskY - 62, 28, 2, ink.opacity(0.3))
        px(280, Self.deskY - 4, 20, 4, ink)
    }

    // MARK: - Pieces

    private func drawCloud(
        px: (CGFloat, CGFloat, CGFloat, CGFloat, Color) -> Void,
        x: CGFloat, y: CGFloat, w: CGFloat, c: Color, wx: CGFloat, ww: CGFloat
    ) {
        // Clipped to the glass by hand — a cloud sliding across the wall would
        // give the whole thing away.
        func band(_ bx: CGFloat, _ by: CGFloat, _ bw: CGFloat) {
            let left = max(bx, wx + 2)
            let right = min(bx + bw, wx + ww - 2)
            if right > left { px(left, by, right - left, 4, c) }
        }
        band(x, y, w)
        band(x + w * 0.24, y - 4, w * 0.55)
    }

    private func strokeRect(
        px: (CGFloat, CGFloat, CGFloat, CGFloat, Color) -> Void,
        x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, c: Color
    ) {
        px(x, y, w, 2, c)
        px(x, y + h - 2, w, 2, c)
        px(x, y, 2, h, c)
        px(x + w - 2, y, 2, h, c)
    }

    private func wrap(_ v: Double, _ span: CGFloat) -> CGFloat {
        CGFloat(v.truncatingRemainder(dividingBy: Double(span)))
    }
}

// MARK: - GIF playback

/// Plays a bundled GIF frame by frame.
///
/// SwiftUI's Image cannot animate a GIF, and AnimatedImage isn't available
/// here, so the frames are decoded once with ImageIO and stepped by the
/// timeline. Decoding is cached statically: the launch scene is built more
/// than once during the greeting's transition, and re-decoding 40 frames each
/// time showed up as a stutter on the first appearance.
struct GIFPlayer: View {
    let name: String
    var paused: Bool = false

    var body: some View {
        let gif = GIFStore.shared.load(name)
        TimelineView(.animation(minimumInterval: gif.frameDuration, paused: paused)) { timeline in
            let i = paused
                ? 0
                : Int(timeline.date.timeIntervalSinceReferenceDate / gif.frameDuration)
                    % max(gif.frames.count, 1)
            if let frame = gif.frames.indices.contains(i) ? gif.frames[i] : gif.frames.first {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.none)   // pixel art: never smooth it
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

final class GIFStore {
    static let shared = GIFStore()
    private var cache: [String: Decoded] = [:]

    struct Decoded {
        let frames: [CGImage]
        let frameDuration: Double
    }

    func load(_ name: String) -> Decoded {
        if let hit = cache[name] { return hit }
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "gif"),
            let src = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            let empty = Decoded(frames: [], frameDuration: 0.1)
            cache[name] = empty
            return empty
        }
        let count = CGImageSourceGetCount(src)
        var frames: [CGImage] = []
        frames.reserveCapacity(count)
        for i in 0..<count {
            if let img = CGImageSourceCreateImageAtIndex(src, i, nil) { frames.append(img) }
        }
        // Per-frame delay from the GIF itself rather than a guess, so the cat
        // breathes at the rate it was drawn to.
        var delay = 0.1
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let d = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif[kCGImagePropertyGIFDelayTime] as? Double),
           d > 0 {
            delay = d
        }
        let decoded = Decoded(frames: frames, frameDuration: delay)
        cache[name] = decoded
        return decoded
    }
}
