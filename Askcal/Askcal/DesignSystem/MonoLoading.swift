//
//  MonoLoading.swift
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

/// A hairline ring with one quarter inked.
struct MonoSpinner: View {
    var size: CGFloat = 16
    var label: String = "Loading"

    @Environment(\.book) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(book.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .background(
                Circle().strokeBorder(book.rule, lineWidth: 1).frame(width: size, height: size)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A recessed block standing in for content that hasn't arrived.
struct MonoSkeleton: View {
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
struct MonoSkeletonRows: View {
    var rows: Int = 3

    private static let widths: [CGFloat] = [180, 132, 208, 156]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: Space.lg) {
                    MonoSkeleton(width: 21, height: 21)
                    VStack(alignment: .leading, spacing: Space.sm) {
                        MonoSkeleton(width: Self.widths[i % Self.widths.count], height: 13)
                        MonoSkeleton(width: 96, height: 10)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}

/// The three states a fetched screen can be in, in one place.
///
/// Exists because the app had no vocabulary for "loading" versus "empty", and
/// so used the empty state for both — and because `try?` returning `[]` made a
/// network error indistinguishable from a genuinely empty day.
struct MonoLoadState<Content: View, Empty: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    var error: String?
    var retry: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let empty: () -> Empty

    @Environment(\.book) private var book

    var body: some View {
        if isLoading {
            MonoSkeletonRows()
        } else if let error {
            VStack(alignment: .leading, spacing: Space.md) {
                Text(error)
                    .font(BookType.body(13))
                    .foregroundStyle(book.inkDim)
                if let retry {
                    Button("Try again") { retry() }
                        .buttonStyle(PillButtonStyle(filled: false))
                }
            }
        } else if isEmpty {
            empty()
        } else {
            content()
        }
    }
}
