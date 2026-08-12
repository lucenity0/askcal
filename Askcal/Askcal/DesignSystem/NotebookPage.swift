//
//  NotebookPage.swift
//  Askcal
//
//  One page of the notebook. Every screen is one of these.
//
//  This exists because the app had grown two design systems: the day surface
//  used one set of tokens and every screen you could reach *from* it used
//  another, with its own gutters and its own heading block. Tapping a row landed
//  you somewhere that looked like a different app, which is most of what "it
//  looks broken" actually was. A single container is the fix — the page is
//  assembled in one place, so no screen can drift from the others without
//  changing this file.
//
//  Layout, leading edge inward: the wire, the paper, the margin rule, and then
//  the writing. Marks that belong to an entry rather than to its text — the
//  checkbox, the priority dot — live in the margin, which is what the margin is
//  for.
//

import SwiftUI

struct NotebookPage<Content: View>: View {
    /// Whether this page shows the wire. Off for sheets and for the right-hand
    /// page of a spread, which shares the binding with the left.
    var bound: Bool = true
    var placement: BindingPlacement = .leading
    /// Off for pages whose content scrolls itself (a `List`, a timeline).
    var scrollable: Bool = true
    var onRefresh: (() async -> Void)?

    @ViewBuilder var content: () -> Content

    /// Where the writing starts: clear of the margin rule, never on it.
    private var textInset: CGFloat { Space.margin + Space.lg }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PaperSurface()
                .ignoresSafeArea()

            MarginRule()
                .padding(.leading, Space.margin)
                .ignoresSafeArea(edges: .vertical)

            Group {
                if scrollable {
                    if let onRefresh {
                        scroll.refreshable { await onRefresh() }
                    } else {
                        scroll
                    }
                } else {
                    padded
                }
            }

            if bound {
                BindingEdge(placement: placement)
                    .ignoresSafeArea(edges: .vertical)
            }
        }
    }

    private var scroll: some View {
        ScrollView(showsIndicators: false) {
            padded
        }
    }

    private var padded: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, textInset)
        .padding(.trailing, Space.gutter)
        .padding(.top, Space.md)
        .padding(.bottom, Space.fabClearance)
    }
}

// MARK: - The heading block

/// The one heading hierarchy: a mono kicker over a serif title. Every page uses
/// this; heading styles are never re-specified per screen.
struct PageTitle<Trailing: View>: View {
    let kicker: String
    let title: String
    var size: CGFloat = 34
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.book) private var book

    init(
        kicker: String,
        title: String,
        size: CGFloat = 34,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.kicker = kicker
        self.title = title
        self.size = size
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(kicker)
                    .font(BookType.kicker())
                    .foregroundStyle(book.inkSub)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(BookType.display(size))
                    .foregroundStyle(book.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)  // shrink to fit, never clip
            }
            Spacer(minLength: Space.lg)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small mono rubric opening a section, set in the margin.
struct Rubric: View {
    let text: String
    @Environment(\.book) private var book

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(BookType.meta(10))
            .tracking(1.2)
            .foregroundStyle(book.inkSub)
    }
}
