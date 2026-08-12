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
        PageScaffold {
            PageHeader(kicker: "Every day", title: "Routine", icon: "repeat") {
                Text("\(doneCount)/\(store.routines.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.textSecondary)
            }
            SectionUnderline()
        } content: {

                VStack(spacing: 0) {
                    ForEach(store.routines) { routine in
                        HStack(spacing: 12) {
                            SquareCheckbox(checked: store.routinesDone.contains(routine.id)) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    store.toggleRoutine(routine)
                                }
                            }
                            Text(routine.title)
                                .font(BookType.entry())
                                .foregroundStyle(book.textPrimary)
                                .strikethrough(store.routinesDone.contains(routine.id),
                                               color: book.textSecondary)
                            Spacer()
                            Text(routine.cadence)
                                .font(BookType.meta(10))
                                .foregroundStyle(book.textSecondary)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    store.deleteRoutine(routine)
                                }
                            } label: {
                                Label("Delete routine", systemImage: "trash")
                            }
                        }
                        Divider().overlay(book.border)
                    }

                    if isAdding {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(book.border, lineWidth: 1.5)
                                .frame(width: 21, height: 21)
                            TextField("new routine", text: $newTitle)
                                .font(BookType.entry())
                                .foregroundStyle(book.textPrimary)
                                .focused($addFocused)
                                .onSubmit {
                                    store.addRoutine(title: newTitle)
                                    newTitle = ""
                                    isAdding = false
                                }
                        }
                        .padding(.vertical, 12)
                        .onAppear { addFocused = true }
                        .onChange(of: addFocused) { _, focused in
                            // dismissing the keyboard ends the add — it must
                            // not come back when returning to this tab
                            if !focused {
                                isAdding = false
                                newTitle = ""
                            }
                        }
                    }
                }

                if store.routines.isEmpty && !isAdding {
                    Text("no routines yet. the + is right there.")
                        .font(BookType.body())
                        .foregroundStyle(book.textSecondary)
                        .padding(.vertical, 24)
                }
        }
    }
}
