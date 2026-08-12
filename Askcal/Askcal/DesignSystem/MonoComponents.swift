//
//  MonoComponents.swift
//  Askcal
//
//  Shared monochrome components per pulse-ui-spec.md. State is shape + fill,
//  never color.
//

import SwiftUI

// ─── Square checkbox — task list entries ─────────────────────────────────────

struct SquareCheckbox: View {
    let checked: Bool
    let action: () -> Void
    @Environment(\.book) private var book

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(checked ? book.fill : book.textSecondary.opacity(0.6), lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4).fill(checked ? book.fill : .clear)
                    )
                    .frame(width: 21, height: 21)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(book.fillText)
                }
            }
            .frame(width: 44, height: 44) // touch target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// ─── Status circle — quick status in the Uncompleted card ────────────────────

struct StatusCircle: View {
    let done: Bool
    let action: () -> Void
    @Environment(\.book) private var book

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(done ? book.fill : book.textSecondary.opacity(0.6), lineWidth: 1.5)
                    .background(Circle().fill(done ? book.fill : .clear))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(book.fillText)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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
            .foregroundStyle(filled ? book.fillText : book.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule().fill(filled ? book.fill : .clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? .clear : book.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// ─── Section divider with short bold underline accent ────────────────────────

struct SectionUnderline: View {
    @Environment(\.book) private var book

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(book.border).frame(height: 1)
            Rectangle().fill(book.fill).frame(width: 44, height: 3).offset(y: -1)
        }
    }
}

// ─── Placeholder row — inline "add" affordance ───────────────────────────────

struct PlaceholderRow: View {
    @Environment(\.book) private var book

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(book.border, lineWidth: 1.5)
                .frame(width: 21, height: 21)
            RoundedRectangle(cornerRadius: 8)
                .fill(book.surface)
                .frame(height: 36)
        }
        .padding(.vertical, 6)
    }
}

// ─── Floating action button ───────────────────────────────────────────────────

struct FAB: View {
    let action: () -> Void
    @Environment(\.book) private var book

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(book.fillText)
                .frame(width: 56, height: 56)
                .background(Circle().fill(book.fill))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// ─── Toggle: outlined capsule off, filled + contrasting thumb on ─────────────
// (the system Toggle's white-on-white track is invisible in dark mode)

struct MonoToggleStyle: ToggleStyle {
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
                            configuration.isOn ? .clear : book.textSecondary.opacity(0.6),
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 46, height: 28)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? book.fillText : book.textSecondary)
                            .frame(width: 20, height: 20)
                            .padding(4)
                    }
                    .animation(.easeOut(duration: 0.18), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }
}
