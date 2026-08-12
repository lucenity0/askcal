//
//  TaskComposerSheet.swift
//  Askcal
//
//  Create or edit a task: title + track + a scheduled date/time (pinned,
//  defaulting to the device's current local time) + an optional deadline.
//  In edit mode the title/track are fixed and only the schedule shifts.
//

import SwiftUI

struct TaskComposerSheet: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book
    @Environment(\.dismiss) private var dismiss

    /// When set, the sheet edits this task's schedule instead of creating one.
    var editing: AskcalTask? = nil

    @State private var title = ""
    @State private var track: TrackKey = .uni
    @State private var scheduledAt = Date.now
    @State private var hasDeadline = false
    @State private var dueAt = Date.now.addingTimeInterval(3600)
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    private var isEditing: Bool { editing != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(
                    kicker: isEditing ? "Reschedule" : "Quick add",
                    title: isEditing ? "Edit task" : "New task",
                    size: 26
                )

                if isEditing {
                    Text(title)
                        .font(BookType.entry())
                        .foregroundStyle(book.ink)
                        .lineLimit(2)
                } else {
                    TextField("what needs doing?", text: $title)
                        .font(BookType.entry())
                        .foregroundStyle(book.ink)
                        .focused($focused)
                        .submitLabel(.done)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(book.card)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(book.rule, lineWidth: 1))
                        )
                    trackPicker
                }

                field("Scheduled") {
                    DatePicker("", selection: $scheduledAt,
                               displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(book.fill)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Deadline")
                            .font(BookType.meta(10))
                            .foregroundStyle(book.inkSub)
                        Spacer()
                        Toggle("", isOn: $hasDeadline.animation(.easeOut(duration: 0.2)))
                            .labelsHidden()
                            .toggleStyle(PaperToggleStyle())
                    }
                    if hasDeadline {
                        DatePicker("", selection: $dueAt,
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .tint(book.fill)
                    }
                }

                Button(isEditing ? "Save changes" : "Add task") { save() }
                    .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)

                if isEditing {
                    Button("Delete task", role: .destructive) { confirmDelete = true }
                        .buttonStyle(PillButtonStyle(filled: false, fullWidth: true))
                }

                Spacer(minLength: 0)
            }
            .padding(22)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(book.paper)
        .onAppear(perform: setup)
        .confirmationDialog(
            "Delete this task?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let editing { store.deleteTask(editing) }
                dismiss()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private var trackPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Track")
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
            // wraps to two rows on narrow widths / large type
            FlowRow(spacing: 8) {
                ForEach(TrackKey.allCases) { key in
                    Button { track = key } label: {
                        Text(key.title)
                            .font(BookType.meta(11))
                            .lineLimit(1)
                            .foregroundStyle(track == key ? book.fillText : book.inkSub)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(track == key ? book.fill : .clear))
                            .overlay(Capsule().strokeBorder(
                                track == key ? .clear : book.rule, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func field<Content: View>(
        _ label: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
            Spacer()
            content()
        }
    }

    private func setup() {
        if let editing {
            title = editing.title
            track = editing.track
            scheduledAt = editing.scheduledAt ?? editing.scheduledFor ?? .now
            if let due = editing.dueAt { hasDeadline = true; dueAt = due }
        } else {
            scheduledAt = .now
            dueAt = .now.addingTimeInterval(3600)
            focused = true
        }
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: scheduledAt)
        let deadline = hasDeadline ? dueAt : nil
        if let editing {
            store.updateTaskSchedule(editing, scheduledAt: scheduledAt,
                                     dueAt: deadline, scheduledFor: day)
        } else {
            store.quickAdd(title: title, track: track, scheduledAt: scheduledAt,
                           dueAt: deadline, scheduledFor: day)
        }
        dismiss()
    }
}

/// Minimal wrapping HStack so the 5 track chips never clip on small widths.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

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
