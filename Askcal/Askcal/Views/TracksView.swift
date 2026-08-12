//
//  TracksView.swift
//  Askcal
//
//  Everything open, filed by track.
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

import SwiftUI

struct TracksView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    @Binding var composing: ComposerIntent?

    /// Which tracks auto-task. Unknown until the first load, and assumed on so
    /// a toggle never flickers off before the truth arrives.
    @State private var active: [TrackKey: Bool] = [:]

    var body: some View {
        NotebookPage {
            PageTitle(kicker: "Everything open", title: "Tracks") {
                Text("\(store.openTasks.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.inkSub)
            }

            ForEach(TrackKey.allCases) { track in
                section(for: track)
            }
        }
        .task {
            guard active.isEmpty, store.isLive else { return }
            guard let on = try? await APIClient.shared.activeTracks() else { return }
            active = Dictionary(uniqueKeysWithValues: TrackKey.allCases.map {
                ($0, on.contains($0))
            })
        }
    }

    @ViewBuilder
    private func section(for track: TrackKey) -> some View {
        let items = store.tasks(in: track)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.md) {
                Rubric(track.title)
                Spacer()
                // An inactive track blocks auto-tasking for everything filed
                // under it. That was previously invisible and unchangeable,
                // which is how design mail could score 97 and never become a
                // task.
                Toggle("", isOn: Binding(
                    get: { active[track] ?? true },
                    set: { on in
                        active[track] = on
                        Task { try? await APIClient.shared.setTrack(track, active: on) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(PaperToggleStyle())
                .accessibilityLabel("Auto-task from \(track.title)")
                Text("\(items.count)")
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }
            .padding(.bottom, Space.md)

            if items.isEmpty {
                Text(track == .career ? "nothing in the pipeline." : "nothing filed here.")
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
