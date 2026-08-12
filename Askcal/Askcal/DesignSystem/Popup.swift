//
//  Popup.swift
//  Askcal
//
//  A card that floats over the page with the page blurred behind it.
//
//  Not a system sheet. A sheet slides a full-height panel up from the bottom
//  and keeps whatever height its detent asks for, which is why the composer
//  sat above an inch of empty paper — the content was short and the panel was
//  not. This sizes to its content, appears where you are looking, and puts the
//  page out of focus rather than off screen, so opening a mail or writing a
//  task reads as a pause in what you were doing instead of a trip somewhere
//  else.
//
//  Presented from the root so it covers the tab bar. A popup that leaves the
//  bar tappable underneath is a way to end up on another tab with a modal still
//  open over it.
//

import SwiftUI

struct PopupCard<Body: View>: View {
    @ViewBuilder var content: () -> Body

    @Environment(\.book) private var book

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                content()
            }
            .padding(Space.xl)
        }
        // Sizes to the content, up to a ceiling — past that it scrolls rather
        // than growing into the status bar.
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: 460)
        .frame(maxHeight: 620)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(book.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(book.rule, lineWidth: Stroke.hair)
                )
                .shadow(color: .black.opacity(0.18), radius: 30, y: 12)
        )
        .padding(Space.xl)
    }
}

private struct PopupModifier<Item: Identifiable, PopupBody: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder var popup: (Item) -> PopupBody

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let item {
                    ZStack {
                        // The blur is the point: the page is still there, just
                        // out of focus, so the popup reads as a pause rather
                        // than a different screen.
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .ignoresSafeArea()
                            .onTapGesture { dismiss() }
                            .accessibilityLabel("Close")
                            .accessibilityAddTraits(.isButton)

                        PopupCard { popup(item) }
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96))
                    )
                    .zIndex(3)
                }
            }
            .animation(
                reduceMotion ? .easeInOut(duration: 0.15)
                             : .spring(response: 0.34, dampingFraction: 0.86),
                value: item?.id
            )
    }

    private func dismiss() {
        item = nil
    }
}

extension View {
    /// Present `popup` over this view, blurring it, whenever `item` is set.
    func popup<Item: Identifiable, PopupBody: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> PopupBody
    ) -> some View {
        modifier(PopupModifier(item: item, popup: content))
    }
}

/// A popup's own heading: what it is, and the way out.
struct PopupHeader: View {
    let kicker: String
    let title: String
    var onClose: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Rubric(kicker)
                Text(title)
                    .font(BookType.display(24))
                    .foregroundStyle(book.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.lg)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(BookType.icon(13, weight: .medium))
                    .foregroundStyle(book.inkSub)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(book.recessed))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}
