//
//  Marks.swift
//  Askcal
//
//  Shared marks and controls. State is shape and fill, never colour — the
//  palette has one ink, so a control cannot signal anything by going a
//  different hue.
//

import SwiftUI



// ─── Priority dot — solid = high, hollow = medium, absent = low ──────────────

struct PriorityDot: View {
    let band: PriorityBand
    @Environment(\.book) private var book

    var body: some View {
        switch band {
        case .high:
            Circle().fill(book.fill).frame(width: 7, height: 7)
        case .medium:
            Circle().strokeBorder(book.fill, lineWidth: 1.5).frame(width: 7, height: 7)
        case .low:
            EmptyView()
        }
    }
}

// ─── Pill button ──────────────────────────────────────────────────────────────

struct PillButtonStyle: ButtonStyle {
    var filled = true
    var fullWidth = false
    @Environment(\.book) private var book

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BookType.entry(13))
            .foregroundStyle(filled ? book.fillText : book.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule().fill(filled ? book.fill : .clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? .clear : book.rule, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}




// ─── Toggle: outlined capsule off, filled + contrasting thumb on ─────────────
// (the system Toggle's white-on-white track is invisible in dark mode)

struct PaperToggleStyle: ToggleStyle {
    @Environment(\.book) private var book

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer(minLength: 0)
            }
            .overlay(alignment: .trailing) {
                Capsule()
                    .fill(configuration.isOn ? book.fill : .clear)
                    .overlay(
                        Capsule().strokeBorder(
                            configuration.isOn ? .clear : book.inkSub.opacity(0.6),
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 46, height: 28)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? book.fillText : book.inkSub)
                            .frame(width: 20, height: 20)
                            .padding(4)
                    }
                    .animation(.easeOut(duration: 0.18), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }
}
