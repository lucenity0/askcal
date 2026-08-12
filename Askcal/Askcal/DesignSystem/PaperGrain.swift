//
//  PaperGrain.swift
//  Askcal
//
//  The tooth of the paper.
//
//  One 128×128 tile, generated once on first use and repeated by the GPU for
//  the life of the process. The obvious alternative — a `Canvas` drawing random
//  speckle — re-runs its randomness on every redraw, which costs a frame's work
//  on every scroll *and* makes the grain crawl, because a new random field is
//  drawn each time. Paper does not shimmer.
//
//  The seed is fixed for the same reason: the grain must be identical across
//  launches, or the page looks subtly different every time you open the app.
//

import SwiftUI
import UIKit

enum PaperGrain {
    private static let tileSize = 128

    /// Built once, on first use. `nonisolated(unsafe)` because it is written
    /// exactly once during initialisation and only ever read afterwards.
    nonisolated(unsafe) static let tile: UIImage = makeTile()

    private static func makeTile() -> UIImage {
        let n = tileSize
        let bytesPerRow = n * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * n)

        // xorshift64, seeded with a constant: the same paper every launch
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> UInt8 {
            seed ^= seed << 13
            seed ^= seed >> 7
            seed ^= seed << 17
            return UInt8(truncatingIfNeeded: seed >> 24)
        }

        for i in stride(from: 0, to: pixels.count, by: 4) {
            // A narrow band around mid-grey. The tile is composited at a few
            // percent, and wide swings at that opacity read as dirt on the page
            // rather than as the tooth of the paper.
            let v = 108 &+ (next() % 40)
            pixels[i] = v
            pixels[i + 1] = v
            pixels[i + 2] = v
            pixels[i + 3] = 255
        }

        guard let context = pixels.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(
                data: raw.baseAddress,
                width: n, height: n,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }), let image = context.makeImage() else {
            // A missing tile costs texture, never correctness — the paper fill
            // underneath stands on its own.
            return UIImage()
        }
        return UIImage(cgImage: image)
    }
}

/// The page itself: the paper colour with its grain on top, composited as one
/// layer so the blend mode acts on the paper and not on whatever is behind it.
struct PaperSurface: View {
    @Environment(\.book) private var book
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            book.paper
            if PaperTexture.grainOpacity > 0 {
                Image(uiImage: PaperGrain.tile)
                    .resizable(resizingMode: .tile)
                    // multiply darkens the cream; on a dark page it would erase
                    // it, so the dark theme lightens by the same amount instead
                    .blendMode(scheme == .dark ? .screen : .multiply)
                    .opacity(PaperTexture.grainOpacity)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
    }
}
