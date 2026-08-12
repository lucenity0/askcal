//
//  TracksView.swift
//  Askcal
//
//  Career / Design / Uni / Feed as "My notes"-style lists.
//

import SwiftUI

struct TracksView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book

    var body: some View {
        PageScaffold {
            PageHeader(kicker: "My tracks", title: "Tracks") {
                Text("\(store.openTasks.count)")
                    .font(BookType.meta(13))
                    .foregroundStyle(book.textSecondary)
            }
            SectionUnderline()
        } content: {
                ForEach(TrackKey.allCases) { track in
                    VStack(alignment: .leading, spacing: 10) {
                        PageHeader(
                            kicker: track.sectionKicker, title: track.title,
                            icon: track.icon, titleSize: 28
                        ) {
                            Text("\(store.tasks(in: track).count)")
                                .font(BookType.meta(12))
                                .foregroundStyle(book.textSecondary)
                        }
                        SectionUnderline()

                        let items = store.tasks(in: track)
                        if items.isEmpty {
                            Text(track == .career ? "nothing in the pipeline yet." : "nothing here yet.")
                                .font(BookType.body())
                                .foregroundStyle(book.textSecondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(items) { task in
                                    HStack(spacing: 12) {
                                        SquareCheckbox(checked: task.status == .done) {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                store.toggleDone(task)
                                            }
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(task.title)
                                                .font(BookType.entry())
                                                .foregroundStyle(book.textPrimary)
                                            if let detail = detailLine(for: task) {
                                                Text(detail)
                                                    .font(BookType.meta(10))
                                                    .foregroundStyle(book.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        PriorityDot(band: task.priority)
                                    }
                                    .padding(.vertical, 6)
                                    Divider().overlay(book.border)
                                }
                            }
                        }
                    }
                }
        }
    }

    private func detailLine(for task: AskcalTask) -> String? {
        var parts: [String] = []
        if let pipeline = task.pipeline { parts.append(pipeline.uppercased()) }
        if let meta = task.meta { parts.append(meta) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
