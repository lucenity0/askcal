//
//  Loading.swift
//  Askcal
//
//  Loading, said quietly.
//
//  Two rules carried over from the same hand that drew the rest of this:
//
//  1. No shimmer. A glossy gradient travelling across matte paper is the one
//     thing that would break the material, so a loading block is just a
//     recessed space on the page — the shape of what is coming, not an effect.
//
//  2. Reduced motion stops the spin but keeps the ring. A stationary marker
//     still reads as "in progress"; removing it entirely reads as "finished,
//     and empty", which is the wrong answer to the same question.
//
//  This replaces nothing: before it, the app had exactly one loading state in
//  the whole codebase, so a cold launch rendered its empty states ("inbox
//  quiet. enjoy it.") over data that was still in flight — copy that is
//  charming when true and a lie for the two seconds it wasn't.
//

import SwiftUI


/// A recessed block standing in for content that hasn't arrived.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 14

    @Environment(\.book) private var book

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.mark)
            .fill(book.recessed)
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// N skeleton rows shaped like the app's list rows.
///
/// Deliberately varies the title width per row: identical bars read as a
/// rendering artefact, staggered ones read as text.
struct SkeletonRows: View {
    var rows: Int = 3

    private static let widths: [CGFloat] = [180, 132, 208, 156]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: Space.lg) {
                    SkeletonBlock(width: 21, height: 21)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SkeletonBlock(width: Self.widths[i % Self.widths.count], height: 13)
                        SkeletonBlock(width: 96, height: 10)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

