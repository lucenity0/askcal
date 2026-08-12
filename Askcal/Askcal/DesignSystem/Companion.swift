//
//  Companion.swift
//  Askcal
//
//  The idle companion on the now-working card. A pixel grid —
//  '#' = full, '+' = 40% shade, ' ' = empty. One motif is picked per app open,
//  so the app has a small life of its own without ever being the same twice.
//  Purely decorative; it encodes nothing about your day.
//

import SwiftUI

enum CompanionMotif: CaseIterable {
    case cat, coffee, book, plant

    /// Animation frames as 12-column pixel grids.
    var frames: [[String]] {
        switch self {
        case .cat:
            return [
                [
                    "   #    #   ",
                    "   ##  ##   ",
                    "  ########  ",
                    "  ## ## ##  ",
                    "  ########  ",
                    "   ######   ",
                    "  ########  ",
                    " ########## ",
                    " #########+ ",
                    "  ##    ##  ",
                ],
                [
                    "   #    #   ",
                    "   ##  ##   ",
                    "  ########  ",
                    "  ## ## ##  ",
                    "  ########  ",
                    "   ######   ",
                    "  ########+ ",
                    " ##########+",
                    " #########  ",
                    "  ##    ##  ",
                ],
                [
                    "   #    #   ",
                    "   ##  ##   ",
                    "  ########  ",
                    "  ##+##+##  ",
                    "  ########  ",
                    "   ######   ",
                    "  ########  ",
                    " ########## ",
                    " #########+ ",
                    "  ##    ##  ",
                ],
            ]
        case .coffee:
            let cup = [
                " ########   ",
                " ######## # ",
                " ######## # ",
                " #########  ",
                "  #######   ",
                "   #####    ",
            ]
            return [
                [
                    "            ",
                    "   +    +   ",
                    "   +   +    ",
                    "    +   +   ",
                    "            ",
                    "            ",
                ] + cup,
                [
                    "   +    +   ",
                    "    +  +    ",
                    "   +    +   ",
                    "            ",
                    "    +   +   ",
                    "            ",
                ] + cup,
                [
                    "    +  +    ",
                    "   +    +   ",
                    "            ",
                    "   +   +    ",
                    "            ",
                    "            ",
                ] + cup,
            ]
        case .book:
            return [
                [
                    "            ",
                    "            ",
                    " ##      ## ",
                    " #### ##### ",
                    " ########## ",
                    " ########## ",
                    " ########## ",
                    "  ########  ",
                ],
                [
                    "            ",
                    "      +     ",
                    " ##   +  ## ",
                    " #### ##### ",
                    " ########## ",
                    " ########## ",
                    " ########## ",
                    "  ########  ",
                ],
                [
                    "    +       ",
                    "     +      ",
                    " ##   +  ## ",
                    " #### ##### ",
                    " ########## ",
                    " ########## ",
                    " ########## ",
                    "  ########  ",
                ],
            ]
        case .plant:
            return [
                [
                    "     ##     ",
                    "    ###     ",
                    "  ++ #      ",
                    "   ++# ##   ",
                    "     ####   ",
                    "     #      ",
                    "  ########  ",
                    "   ######   ",
                    "   ######   ",
                ],
                [
                    "     ##     ",
                    "     ###    ",
                    "     # ++   ",
                    "  ## #++    ",
                    "  ####      ",
                    "     #      ",
                    "  ########  ",
                    "   ######   ",
                    "   ######   ",
                ],
            ]
        }
    }

    var frameDuration: Double {
        switch self {
        case .cat: return 0.55
        case .coffee: return 0.45
        case .book: return 0.6
        case .plant: return 0.7
        }
    }
}

struct PixelSprite: View {
    let motif: CompanionMotif
    var size: CGFloat = 56

    @Environment(\.book) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            grid(motif.frames[0])
        } else {
            TimelineView(.periodic(from: .now, by: motif.frameDuration)) { timeline in
                let frames = motif.frames
                let idx = Int(timeline.date.timeIntervalSinceReferenceDate / motif.frameDuration)
                    % frames.count
                grid(frames[idx])
            }
        }
    }

    private func grid(_ rows: [String]) -> some View {
        Canvas { context, canvasSize in
            let cols = rows.map(\.count).max() ?? 12
            let px = min(canvasSize.width / CGFloat(cols),
                         canvasSize.height / CGFloat(rows.count))
            // center the motif's grid inside the fixed frame — different
            // motifs have different natural bounds, the box never changes
            let offsetX = (canvasSize.width - CGFloat(cols) * px) / 2
            let offsetY = (canvasSize.height - CGFloat(rows.count) * px) / 2
            for (r, row) in rows.enumerated() {
                for (c, ch) in row.enumerated() {
                    let alpha: CGFloat
                    switch ch {
                    case "#": alpha = 1
                    case "+": alpha = 0.4
                    default: continue
                    }
                    let rect = CGRect(
                        x: offsetX + CGFloat(c) * px,
                        y: offsetY + CGFloat(r) * px,
                        width: px + 0.4, height: px + 0.4
                    )
                    context.fill(Path(rect), with: .color(book.fill.opacity(alpha)))
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .accessibilityHidden(true)
    }
}
