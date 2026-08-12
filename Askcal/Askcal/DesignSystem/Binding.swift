//
//  Binding.swift
//  Askcal
//
//  The wire that holds the pages.
//
//  Rendered as a fixed overlay on the *container*, never inside a page. That
//  distinction is what makes the page turn read correctly: the binding is part
//  of the notebook, so pages slide beneath a stationary wire. Put it inside the
//  page and every ring slides away with the day, which reads as the whole book
//  moving rather than a page turning.
//
//  On a phone it runs down the leading edge. On an iPad spread it runs down the
//  centre, between the two pages, which is where a real one is.
//

import SwiftUI

enum BindingPlacement {
    /// Down the left of a single page — the phone, and iPad portrait.
    case leading
    /// Down the middle of a two-page spread — iPad landscape.
    case gutter
}

struct BindingEdge: View {
    var placement: BindingPlacement = .leading

    @Environment(\.book) private var book

    private var width: CGFloat { PaperTexture.bindingWidth }

    var body: some View {
        if width > 0 {
            GeometryReader { geo in
                let spacing = PaperTexture.ringSpacing
                let count = max(1, Int((geo.size.height / spacing).rounded(.down)))
                ZStack {
                    board
                    VStack(spacing: 0) {
                        ForEach(0..<count, id: \.self) { _ in ring }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, spacing / 2)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// The cover showing through. In the gutter it's a soft crease rather than
    /// a hard strip — two pages of one sheet meet there, they don't stop.
    @ViewBuilder
    private var board: some View {
        switch placement {
        case .leading:
            book.board
        case .gutter:
            LinearGradient(
                colors: [book.board.opacity(0), book.board.opacity(0.28),
                         book.board.opacity(0.28), book.board.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    /// One loop: the punched hole, and the wire crossing it.
    private var ring: some View {
        ZStack {
            Capsule()
                .fill(book.board.opacity(placement == .gutter ? 0.30 : 0.45))
                .frame(width: width * 0.40, height: PaperTexture.ringHeight * 0.46)

            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [book.binding.opacity(0.5),
                                 book.binding,
                                 book.binding.opacity(0.65)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: PaperTexture.wireWidth
                )
                .frame(width: width * 0.76, height: PaperTexture.ringHeight)
        }
        .frame(height: PaperTexture.ringSpacing)
    }
}
