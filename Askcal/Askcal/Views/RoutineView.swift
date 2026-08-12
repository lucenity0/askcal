//
//  RoutineView.swift
//  Askcal
//
//  Recurring habits — reset daily, quiet cadence labels.
//

import SwiftUI

struct RoutineView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @Binding var isAdding: Bool
    @State private var newTitle = ""
    @FocusState private var addFocused: Bool

    private var doneCount: Int {
        store.routines.filter { store.routinesDone.contains($0.id) }.count
    }

    var body: some View {
        NotebookPage {
            PageTitle(kicker: "Every day", title: "Routine") {
                Text("\(doneCount)/\(store.routines.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.inkSub)
            }

            VStack(spacing: 0) {
                ForEach(store.routines) { routine in
                    row(for: routine)
                }
                if isAdding { addRow }
            }

            if store.routines.isEmpty && !isAdding {
                VStack(alignment: .leading, spacing: Space.lg) {
                    Text("no routines yet. add one with +.")
                        .font(BookType.body(15))
                        .foregroundStyle(book.inkSub)
                    RuledFiller()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New routine")
            }
        }
    }

    private func row(for routine: Routine) -> some View {
        let done = store.routinesDone.contains(routine.id)
        return HStack(alignment: .top, spacing: 0) {
            EntryMark(checked: done) {
                withAnimation(.easeOut(duration: 0.2)) { store.toggleRoutine(routine) }
            }
            .frame(width: Space.markReach, alignment: .leading)
            .accessibilityLabel(routine.title)
            .accessibilityValue(done ? "Done today" : "Not done today")

            Text(routine.title)
                .font(BookType.entry())
                .foregroundStyle(done ? book.inkSub : book.ink)
                .strikethrough(done, color: book.inkSub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.lg)

            Spacer(minLength: Space.md)

            Text(routine.cadence)
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
                .padding(.top, Space.xl)
        }
        .padding(.bottom, Space.md)
        .padding(.leading, -Space.markReach)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) { store.deleteRoutine(routine) }
            } label: {
                Label("Delete routine", systemImage: "trash")
            }
        }
        .ruled()
    }

    private var addRow: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: Radius.mark)
                .strokeBorder(book.inkSub, lineWidth: Stroke.strong)
                .frame(width: 19, height: 19)
                .frame(width: Space.markReach, height: 44, alignment: .leading)

            TextField("new routine", text: $newTitle)
                .font(BookType.entry())
                .foregroundStyle(book.ink)
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit {
                    store.addRoutine(title: newTitle)
                    newTitle = ""
                    isAdding = false
                }
                .padding(.top, Space.lg)
        }
        .padding(.bottom, Space.md)
        .padding(.leading, -Space.markReach)
        .onAppear { addFocused = true }
        .onChange(of: addFocused) { _, focused in
            // dismissing the keyboard ends the add — it must not come back
            // when returning to this screen
            if !focused {
                isAdding = false
                newTitle = ""
            }
        }
        .ruled()
    }
}
