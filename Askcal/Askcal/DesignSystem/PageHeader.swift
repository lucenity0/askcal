//
//  PageHeader.swift
//  Askcal
//
//  The one heading hierarchy: kicker (13pt secondary) above a serif title
//  (34pt pages / 28pt in-page sections). Every screen uses this — heading
//  styles are never re-specified per page.
//

import SwiftUI

struct PageHeader<Trailing: View>: View {
    let kicker: String
    let title: String
    var icon: String?
    var titleSize: CGFloat = 34
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.book) private var book

    init(
        kicker: String,
        title: String,
        icon: String? = nil,
        titleSize: CGFloat = 34,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.kicker = kicker
        self.title = title
        self.icon = icon
        self.titleSize = titleSize
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker)
                .font(BookType.kicker())
                .foregroundStyle(book.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            HStack(alignment: .center, spacing: 10) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: titleSize * 0.55))
                        .foregroundStyle(book.textPrimary)
                }
                Text(title)
                    .font(BookType.display(titleSize))
                    .foregroundStyle(book.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)  // shrink to fit, never clip or wrap
                Spacer(minLength: 0)
                trailing()
            }
        }
    }
}
