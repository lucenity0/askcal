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
    @Environment(\.mono) private var mono

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(checked ? mono.fill : mono.textSecondary.opacity(0.6), lineWidth: 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4).fill(checked ? mono.fill : .clear)
                    )
                    .frame(width: 21, height: 21)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mono.fillText)
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
    @Environment(\.mono) private var mono

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(done ? mono.fill : mono.textSecondary.opacity(0.6), lineWidth: 1.5)
                    .background(Circle().fill(done ? mono.fill : .clear))
                    .frame(width: 22, height: 22)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mono.fillText)
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
    @Environment(\.mono) private var mono

    var body: some View {
        switch band {
        case .high:
            Circle().fill(mono.fill).frame(width: 7, height: 7)
        case .medium:
            Circle().strokeBorder(mono.fill, lineWidth: 1.5).frame(width: 7, height: 7)
        case .low:
            EmptyView()
        }
    }
}

// ─── Pill button ──────────────────────────────────────────────────────────────

struct PillButtonStyle: ButtonStyle {
    var filled = true
    var fullWidth = false
    @Environment(\.mono) private var mono

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MonoType.item(13))
            .foregroundStyle(filled ? mono.fillText : mono.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule().fill(filled ? mono.fill : .clear)
            )
            .overlay(
                Capsule().strokeBorder(filled ? .clear : mono.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// ─── Section divider with short bold underline accent ────────────────────────

struct SectionUnderline: View {
    @Environment(\.mono) private var mono

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(mono.border).frame(height: 1)
            Rectangle().fill(mono.fill).frame(width: 44, height: 3).offset(y: -1)
        }
    }
}

// ─── Placeholder row — inline "add" affordance ───────────────────────────────

struct PlaceholderRow: View {
    @Environment(\.mono) private var mono

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(mono.border, lineWidth: 1.5)
                .frame(width: 21, height: 21)
            RoundedRectangle(cornerRadius: 8)
                .fill(mono.surface)
                .frame(height: 36)
        }
        .padding(.vertical, 6)
    }
}

// ─── Floating action button ───────────────────────────────────────────────────

struct FAB: View {
    let action: () -> Void
    @Environment(\.mono) private var mono

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(mono.fillText)
                .frame(width: 56, height: 56)
                .background(Circle().fill(mono.fill))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// ─── Toggle: outlined capsule off, filled + contrasting thumb on ─────────────
// (the system Toggle's white-on-white track is invisible in dark mode)

struct MonoToggleStyle: ToggleStyle {
    @Environment(\.mono) private var mono

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
                    .fill(configuration.isOn ? mono.fill : .clear)
                    .overlay(
                        Capsule().strokeBorder(
                            configuration.isOn ? .clear : mono.textSecondary.opacity(0.6),
                            lineWidth: 1.5
                        )
                    )
                    .frame(width: 46, height: 28)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? mono.fillText : mono.textSecondary)
                            .frame(width: 20, height: 20)
                            .padding(4)
                    }
                    .animation(.easeOut(duration: 0.18), value: configuration.isOn)
            }
        }
        .buttonStyle(.plain)
    }
}
