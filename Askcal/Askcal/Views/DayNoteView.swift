//
//  DayNoteView.swift
//  Askcal
//
//  The day's page — whatever needed writing down that wasn't a task.
//
//  Askcal could only hold things with a shape: a task, a mail, a track. A
//  thought about the day had nowhere to go, which is a strange gap in an app
//  that spent this long trying to look like a notebook.
//
//  It reads as typeset markdown and becomes an editor when you tap it. That is
//  not a flourish — it is the difference between a page and a text box, and a
//  page is what the rest of the app has been promising. Handwriting works
//  through Scribble, which converts to text as you write, so a note taken with
//  the Pencil on iPad is still readable on the phone. Storing raw strokes would
//  have looked more like ink and been unsearchable, unsyncable and unreadable
//  anywhere else.
//

import SwiftUI

struct DayNoteView: View {
    let date: Date
    /// Fills the height it is given rather than sizing to its text — true on
    /// the iPad's facing page, false in the popup where the page is a sheet.
    var fillsHeight = false

    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    private var note: DayNote { store.note(for: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            if editing {
                editor
            } else {
                rendered
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: AskcalStore.dayString(date)) {
            // The fetch belongs to whoever shows the day, not to this view —
            // on the phone this only exists while the popup is open, so
            // fetching here left the collapsed row blank until it was tapped.
            // Kept as a fallback for the iPad's facing page, which is the one
            // place this view appears without a day page having asked first.
            await store.loadNote(for: date)
            // Only when not mid-edit: replacing the field under someone's
            // cursor with a slower answer from the network loses whatever they
            // typed while it was in flight.
            if !editing { draft = note.body }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { withAnimation(.easeOut(duration: 0.2)) { editing = false } }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            TextEditor(text: Binding(
                get: { draft },
                set: { new in
                    draft = new
                    store.writeNote(new, for: date)
                }
            ))
            .font(BookType.body(15))
            .foregroundStyle(book.ink)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .frame(minHeight: 120, maxHeight: fillsHeight ? .infinity : 320)

            HStack(spacing: Space.md) {
                Text("markdown · scribble with a pencil")
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
                Spacer()
                Button("done") { focused = false }
                    .font(BookType.meta(11))
                    .foregroundStyle(book.ink)
            }
        }
    }

    private var rendered: some View {
        Button {
            draft = note.body
            withAnimation(.easeOut(duration: 0.2)) { editing = true }
            focused = true
        } label: {
            VStack(alignment: .leading, spacing: Space.sm) {
                if note.isEmpty {
                    Text("nothing written here yet.")
                        .font(BookType.body(15))
                        .foregroundStyle(book.inkSub)
                } else {
                    // Rendered per line rather than as one blob, so a heading
                    // can be a heading and a list item can keep its hanging
                    // indent. AttributedString(markdown:) on the whole string
                    // collapses every line into one paragraph.
                    ForEach(Array(note.body.components(separatedBy: "\n").enumerated()),
                            id: \.offset) { _, line in
                        MarkdownLine(line: line)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: fillsHeight ? 160 : 0, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(note.isEmpty ? "Write a note for this day" : note.body)
        .accessibilityHint("Opens the day's page for editing")
    }
}

/// One line of markdown, drawn the way a page would set it.
///
/// Only the marks that actually get used when jotting: headings, bullets,
/// quotes, and inline emphasis. Anything else falls through as plain text
/// rather than being swallowed, because a note that silently eats a character
/// you typed is worse than one that shows it.
private struct MarkdownLine: View {
    let line: String
    @Environment(\.book) private var book

    var body: some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            Color.clear.frame(height: Space.sm)
        } else if let heading = heading(trimmed) {
            Text(inline(heading.text))
                .font(BookType.heading(heading.level == 1 ? 20 : 17))
                .foregroundStyle(book.ink)
                .padding(.top, Space.xs)
        } else if let bullet = strip(trimmed, of: ["- ", "* ", "+ "]) {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text("·")
                    .font(BookType.body(15))
                    .foregroundStyle(book.inkSub)
                Text(inline(bullet))
                    .font(BookType.body(15))
                    .foregroundStyle(book.ink)
            }
        } else if let quote = strip(trimmed, of: ["> "]) {
            Text(inline(quote))
                .font(BookType.body(15))
                .foregroundStyle(book.inkDim)
                .padding(.leading, Space.lg)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(book.rule)
                        .frame(width: Stroke.strong)
                }
        } else {
            Text(inline(trimmed))
                .font(BookType.body(15))
                .foregroundStyle(book.ink)
        }
    }

    private func heading(_ text: String) -> (level: Int, text: String)? {
        guard text.hasPrefix("#") else { return nil }
        let hashes = text.prefix { $0 == "#" }.count
        let rest = text.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (min(hashes, 2), rest)
    }

    private func strip(_ text: String, of prefixes: [String]) -> String? {
        for prefix in prefixes where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return nil
    }

    /// Bold and italic only. `inlineOnlyPreservingWhitespace` so an unmatched
    /// asterisk stays an asterisk instead of taking the rest of the line with it.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
