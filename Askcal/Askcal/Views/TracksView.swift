//
//  TracksView.swift
//  Askcal
//
//  Everything open, filed by track — and where tracks are made.
//
//  Each track used to get a full `PageHeader` — kicker, 28pt serif title, icon
//  and a bold underline stub — six times inside a page that already had a
//  header of its own. Six page titles on one page is not a hierarchy, it is six
//  competing claims to be the top of the screen, and it was the loudest single
//  source of the "everything is random" feeling.
//
//  A track is a rubric in the margin now: small, mono, quiet. The entries under
//  it are the content, which is the way round it should have been.
//
//  The list is the account's own. It used to be a fixed five, which is how a PR
//  review ended up filed as design work — there was nothing else to call it.
//

import SwiftUI

struct TracksView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @Binding var composing: ComposerIntent?

    @State private var adding = false
    @State private var newLabel = ""
    @State private var newDetail = ""
    @State private var editing: Track?

    var body: some View {
        NotebookPage {
            PageTitle(kicker: "Everything open", title: "Tracks") {
                Text("\(store.openTasks.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.inkSub)
            }

            ForEach(store.tracks) { track in
                section(for: track)
            }

            addRow
        }
        .task { await store.refreshTracks() }
        .popup(item: $editing) { track in
            TrackEditor(track: track) { editing = nil }
        }
    }

    // MARK: - Adding

    @ViewBuilder
    private var addRow: some View {
        if adding {
            VStack(alignment: .leading, spacing: Space.md) {
                Rubric("new track")
                TextField("what do you call it?", text: $newLabel)
                    .font(BookType.entry(17))
                    .foregroundStyle(book.ink)
                // The description is not decoration: it goes to the classifier
                // verbatim, and it is the only thing that decides what lands
                // here. Asked for at the moment the track is made, because a
                // track with no description sorts nothing.
                TextField("what belongs in it?", text: $newDetail, axis: .vertical)
                    .font(BookType.body(15))
                    .foregroundStyle(book.inkDim)
                    .lineLimit(1...3)

                HStack(spacing: Space.lg) {
                    Button("add") {
                        let label = newLabel.trimmingCharacters(in: .whitespaces)
                        guard !label.isEmpty else { return }
                        let detail = newDetail.trimmingCharacters(in: .whitespaces)
                        Task { await store.addTrack(label: label, detail: detail.isEmpty ? nil : detail) }
                        newLabel = ""
                        newDetail = ""
                        withAnimation(.easeOut(duration: 0.2)) { adding = false }
                    }
                    .font(BookType.meta(12))
                    .foregroundStyle(book.ink)
                    Button("cancel") {
                        withAnimation(.easeOut(duration: 0.2)) { adding = false }
                    }
                    .font(BookType.meta(12))
                    .foregroundStyle(book.inkSub)
                }
            }
            .padding(.vertical, Space.lg)
            .ruled()
        } else {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { adding = true }
            } label: {
                HStack(spacing: Space.md) {
                    Image(systemName: "plus")
                        .font(BookType.icon(12))
                    Text("new track")
                        .font(BookType.meta(12))
                    Spacer()
                }
                .foregroundStyle(book.inkSub)
                .padding(.vertical, Space.lg)
            }
            .ruled()
        }
    }

    // MARK: - A track

    @ViewBuilder
    private func section(for track: Track) -> some View {
        let items = store.tasks(in: track)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.md) {
                Button { editing = track } label: {
                    HStack(spacing: Space.sm) {
                        Rubric(track.label)
                        Image(systemName: "pencil")
                            .font(BookType.icon(9))
                            .foregroundStyle(book.inkSub)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                // An inactive track blocks auto-tasking for everything filed
                // under it. That was previously invisible and unchangeable,
                // which is how design mail could score 97 and never become a
                // task.
                Toggle("", isOn: Binding(
                    get: { track.active },
                    set: { store.updateTrack(track, active: $0) }
                ))
                .labelsHidden()
                .toggleStyle(PaperToggleStyle())
                .accessibilityLabel("Auto-task from \(track.label)")
                Text("\(items.count)")
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }
            .padding(.bottom, Space.md)

            if items.isEmpty {
                Text("nothing filed here.")
                    .font(BookType.body(14))
                    .foregroundStyle(book.inkSub)
                    .padding(.bottom, Space.lg)
                    .ruled()
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                    TimelineRow(
                        task: task,
                        time: nil,
                        isFirst: index == 0,
                        isLast: index == items.count - 1,
                        toggle: {
                            withAnimation(.easeOut(duration: 0.2)) { store.toggleDone(task) }
                        },
                        edit: { composing = .edit(task) },
                        delete: {
                            withAnimation(.easeOut(duration: 0.2)) { store.deleteTask(task) }
                        }
                    )
                }
            }
        }
    }
}

/// Renaming a track, and saying what belongs in it.
///
/// The description is the working part. A track called "work" tells the
/// classifier nothing; "anything from my team or about a PR" is what actually
/// moves a PR review out of wherever it was landing.
private struct TrackEditor: View {
    let track: Track
    var onClose: () -> Void

    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @State private var label = ""
    @State private var detail = ""
    @State private var confirmDelete = false

    /// The track as the store has it now, not the copy this popup opened with.
    /// Without this the switch below reads a value frozen at presentation time
    /// and snaps back the moment you move it.
    private var live: Track { store.track(track.id) ?? track }

    var body: some View {
        PopupHeader(kicker: "Track", title: live.label, onClose: onClose)

        VStack(alignment: .leading, spacing: Space.md) {
            Rubric("name")
            TextField("what do you call it?", text: $label)
                .font(BookType.entry(17))
                .foregroundStyle(book.ink)
        }

        VStack(alignment: .leading, spacing: Space.md) {
            Rubric("what belongs here")
            TextField("in your words", text: $detail, axis: .vertical)
                .font(BookType.body(15))
                .foregroundStyle(book.ink)
                .lineLimit(2...5)
            Text("this is what sorts your mail.")
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
        }

        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Rubric("make tasks")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { live.autoTasks },
                    set: { store.updateTrack(track, autoTasks: $0) }
                ))
                .labelsHidden()
                .toggleStyle(PaperToggleStyle())
                .accessibilityLabel("Mail here becomes tasks")
            }
            Text("off for things you only read.")
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
        }

        HStack(spacing: Space.lg) {
            Button("save") {
                store.updateTrack(
                    track,
                    label: label.trimmingCharacters(in: .whitespaces),
                    detail: detail.trimmingCharacters(in: .whitespaces)
                )
                onClose()
            }
            .font(BookType.meta(12))
            .foregroundStyle(book.ink)

            Spacer()

            // Built-ins can be renamed to anything and switched off, which
            // covers every reason to want one gone without stranding the mail
            // already filed under it.
            if !live.isBuiltin {
                Button(confirmDelete ? "sure?" : "delete") {
                    if confirmDelete {
                        store.deleteTrack(track)
                        onClose()
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) { confirmDelete = true }
                    }
                }
                .font(BookType.meta(12))
                .foregroundStyle(book.inkSub)
            }
        }
        .onAppear {
            label = track.label
            detail = track.detail ?? ""
        }
    }
}
