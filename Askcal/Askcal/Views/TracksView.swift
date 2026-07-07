//
//  TracksView.swift
//  Askcal
//
//  Career / Design / Uni / Feed as "My notes"-style lists.
//

import SwiftUI

struct TracksView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.mono) private var mono

    var body: some View {
        PageScaffold {
            PageHeader(kicker: "My tracks", title: "Tracks") {
                Text("\(store.openTasks.count)")
                    .font(MonoType.meta(13))
                    .foregroundStyle(mono.textSecondary)
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
                                .font(MonoType.meta(12))
                                .foregroundStyle(mono.textSecondary)
                        }
                        SectionUnderline()

                        let items = store.tasks(in: track)
                        if items.isEmpty {
                            Text(track == .career ? "nothing in the pipeline yet." : "nothing here yet.")
                                .font(MonoType.body())
                                .foregroundStyle(mono.textSecondary)
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
                                                .font(MonoType.item())
                                                .foregroundStyle(mono.textPrimary)
                                            if let detail = detailLine(for: task) {
                                                Text(detail)
                                                    .font(MonoType.meta(10))
                                                    .foregroundStyle(mono.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        PriorityDot(band: task.priority)
                                    }
                                    .padding(.vertical, 6)
                                    Divider().overlay(mono.border)
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
