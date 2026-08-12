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
    }

    @ViewBuilder
    private func section(for track: TrackKey) -> some View {
        let items = store.tasks(in: track)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Rubric(track.title)
                Spacer()
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
