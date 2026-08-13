//
//  DigestCard.swift
//  Askcal
//
//  The morning and evening summaries, on screen.
//
//  Every line here is written server-side and rendered verbatim. That is
//  deliberate: the notification body and this card come from the same call, so
//  a push promising three deadlines cannot open onto a card showing two. If the
//  client re-derived copy from the counts it would drift the first time either
//  side changed.
//

import SwiftUI

struct DigestCard: View {
    let kind: DigestKind
    let digest: Digest?
    let error: String?
    var onClose: () -> Void

    @Environment(\.book) private var book

    var body: some View {
        PopupHeader(kicker: kind == .morning ? "This morning" : "This evening",
                    title: digest?.headline ?? kind.title,
                    onClose: onClose)

        if let digest {
            if !digest.lines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(digest.lines, id: \.self) { line in
                        HStack(alignment: .top, spacing: Space.lg) {
                            Text("·")
                                .font(BookType.meta(12))
                                .foregroundStyle(book.inkSub)
                                // A bullet is punctuation, not content. Read
                                // aloud it is "middle dot" before every line.
                                .accessibilityHidden(true)
                            Text(line)
                                .font(BookType.body(15))
                                .foregroundStyle(book.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, Space.md)
                        .ruled()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            facts(digest)
        } else if let error {
            Text(error)
                .font(BookType.body(14))
                .foregroundStyle(book.inkDim)
        } else {
            SkeletonRows(rows: 3)
        }
    }

    /// The numbers behind the sentence, for when the headline isn't enough.
    /// Only the ones that apply to this half of the day — the two digests share
    /// a shape, so the other half's fields are present and meaningless.
    @ViewBuilder
    private func facts(_ d: Digest) -> some View {
        let rows: [(String, String)] = kind == .morning
            ? [("on today", "\(d.taskCount)"),
               ("due today", "\(d.dueToday)"),
               ("carried over", "\(d.carriedOver)"),
               ("mail needing a reply", "\(d.needsReply)")]
            : [("done", "\(d.done)"),
               ("moved to tomorrow", "\(d.carried)"),
               ("still open", "\(d.stillOpen)")]

        VStack(spacing: 0) {
            // Label and value are two columns on screen and one fact out
            // loud — read separately they arrive as "due today" … "2", with
            // everything else in between.
            ForEach(rows, id: \.0) { label, value in
                HStack {
                    Text(label)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                    Spacer()
                    Text(value)
                        .font(BookType.meta(11))
                        .foregroundStyle(book.inkDim)
                }
                .padding(.vertical, Space.sm)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
