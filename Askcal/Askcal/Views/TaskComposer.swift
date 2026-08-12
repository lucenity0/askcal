//
//  TaskComposer.swift
//  Askcal
//
//  Writing a task down properly: what, which track, when, and by when.
//
//  Opened from the add row when you want to say more than a title, and from a
//  task when you want to change one. Either way it arrives carrying what you
//  already typed — reaching for the date button used to hand you an empty field
//  and make you write the line again.
//
//  A popup rather than a sheet. The content is short and a sheet's detent is
//  not, so the old version sat above an inch of empty paper every time.
//

import SwiftUI

/// What the composer was opened for. Identifiable so it can drive a popup.
enum ComposerIntent: Identifiable {
    /// A new task, optionally pre-filled with a line already typed.
    case new(title: String, day: Date)
    /// An existing task, whose title is fixed and whose schedule can move.
    case edit(AskcalTask)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let task): return task.id.uuidString
        }
    }
}

struct TaskComposer: View {
    let intent: ComposerIntent
    var onClose: () -> Void

    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @State private var title = ""
    @State private var track: TrackKey = .uni
    @State private var scheduledAt = Date.now
    @State private var hasDeadline = false
    @State private var dueAt = Date.now.addingTimeInterval(3600)
    @State private var confirmDelete = false
    @FocusState private var focused: Bool

    private var editing: AskcalTask? {
        if case .edit(let task) = intent { return task }
        return nil
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        PopupHeader(
            kicker: editing == nil ? "New task" : "Edit",
            title: editing == nil ? "What needs doing?" : title,
            onClose: onClose
        )

        if editing == nil {
            TextField("write it down", text: $title, axis: .vertical)
                .font(BookType.entry(17))
                .foregroundStyle(book.ink)
                .focused($focused)
                .lineLimit(1...3)
                .padding(Space.lg)
                .background(
                    RoundedRectangle(cornerRadius: Radius.block)
                        .fill(book.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.block)
                                .strokeBorder(book.rule, lineWidth: Stroke.hair)
                        )
                )

            VStack(alignment: .leading, spacing: Space.md) {
                Rubric("track")
                ChipPicker(options: TrackKey.allCases,
                           title: \.title,
                           selection: $track,
                           wraps: true,
                           bordered: false)
            }
        }

        VStack(alignment: .leading, spacing: Space.md) {
            Rubric("when")
            DatePicker("", selection: $scheduledAt,
                       displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .tint(book.fill)
        }

        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Rubric("deadline")
                Spacer()
                Toggle("", isOn: $hasDeadline.animation(.easeOut(duration: 0.2)))
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
                    .accessibilityLabel("Has a deadline")
            }
            if hasDeadline {
                DatePicker("", selection: $dueAt,
                           displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .tint(book.fill)
            }
        }

        VStack(spacing: Space.md) {
            Button(editing == nil ? "Add task" : "Save changes") { save() }
                .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)

            if editing != nil {
                Button("Delete task", role: .destructive) { confirmDelete = true }
                    .buttonStyle(PillButtonStyle(filled: false, fullWidth: true))
            }
        }
        .onAppear(perform: setup)
        .confirmationDialog("Delete this task?",
                            isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let editing { store.deleteTask(editing) }
                onClose()
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    private func setup() {
        switch intent {
        case .new(let typed, let day):
            // Whatever was already written in the add row comes with it.
            title = typed
            scheduledAt = Calendar.current.isDateInToday(day) ? .now : day
            dueAt = scheduledAt.addingTimeInterval(3600)
            focused = typed.isEmpty
        case .edit(let task):
            title = task.title
            track = task.track
            scheduledAt = task.scheduledAt ?? task.scheduledFor ?? .now
            if let due = task.dueAt {
                hasDeadline = true
                dueAt = due
            }
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
        onClose()
    }
}
