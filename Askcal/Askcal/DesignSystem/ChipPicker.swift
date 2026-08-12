//
//  ChipPicker.swift
//  Askcal
//
//  One pick from a small set, as capsule chips.
//
//  There were three of these, written separately: the track picker in the
//  composer, the theme switch in settings, and the day/month/year switch on the
//  calendar. All three did the same thing and none of them agreed on padding,
//  corner treatment or how the selected chip was drawn, which is the kind of
//  small inconsistency that adds up to a screen feeling assembled rather than
//  designed.
//
//  The two variations that turned out to be real are kept as flags. `wraps` is
//  for sets that don't fit on one line — five tracks don't, on a small phone at
//  large type. `bordered` draws the capsule around the whole control, which
//  reads as "these are the options" for a fixed set like Day/Month/Year, and is
//  wrong for a set that wraps.
//

import SwiftUI

struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var wraps = false
    var bordered = true

    @Environment(\.book) private var book

    var body: some View {
        Group {
            if wraps {
                FlowRow(spacing: Space.md) { chips }
            } else {
                HStack(spacing: 0) { chips }
            }
        }
        .padding(bordered ? 2 : 0)
        .background {
            if bordered {
                Capsule().strokeBorder(book.rule, lineWidth: Stroke.hair)
            }
        }
    }

    private var chips: some View {
        ForEach(options, id: \.self) { option in
            let isSelected = option == selection
            Button {
                withAnimation(.easeOut(duration: 0.2)) { selection = option }
            } label: {
                Text(title(option))
                    .font(BookType.meta(11))
                    .lineLimit(1)
                    .fixedSize()   // "Month" must never wrap to "Mont/h"
                    .foregroundStyle(isSelected ? book.fillText : book.inkSub)
                    .padding(.horizontal, Space.lg)
                    .padding(.vertical, Space.sm)
                    .background(Capsule().fill(isSelected ? book.fill : .clear))
                    .overlay(
                        Capsule().strokeBorder(
                            bordered || isSelected ? .clear : book.rule,
                            lineWidth: Stroke.hair
                        )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title(option))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }
}

/// Any number from a small set, as the same capsule chips.
///
/// A mailbox is the case that needed this: a college address carries coursework,
/// fees and the odd recruiter, and being made to pick the closest single one is
/// how mail ends up filed somewhere it never belonged.
///
/// Deliberately has no "none" chip. An empty selection *is* none, and an option
/// that means "I picked nothing" competes with the picking.
struct TagPicker: View {
    let options: [String]
    let title: (String) -> String
    @Binding var selection: Set<String>

    @Environment(\.book) private var book

    var body: some View {
        FlowRow(spacing: Space.md) {
            ForEach(options, id: \.self) { option in
                let isOn = selection.contains(option)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if isOn { selection.remove(option) } else { selection.insert(option) }
                    }
                } label: {
                    Text(title(option))
                        .font(BookType.meta(11))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(isOn ? book.fillText : book.inkSub)
                        .padding(.horizontal, Space.lg)
                        .padding(.vertical, Space.sm)
                        .background(Capsule().fill(isOn ? book.fill : .clear))
                        .overlay(
                            Capsule().strokeBorder(
                                isOn ? .clear : book.rule, lineWidth: Stroke.hair
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(option))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

/// Minimal wrapping stack so a set of chips never clips on small widths.
struct FlowRow: Layout {
    var spacing: CGFloat = Space.md

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
