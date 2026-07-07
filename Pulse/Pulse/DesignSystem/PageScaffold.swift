//
//  PageScaffold.swift
//  Pulse
//
//  Every page uses this: the header block stays pinned, only content
//  scrolls. Pages never place their own header inside a ScrollView —
//  that's how the sticky/scrolling inconsistency crept in before.
//
//  `scrollable: false` is for pages whose content manages its own
//  scrolling (List on Inbox, the timeline ScrollView on Calendar).
//

import SwiftUI

struct PageScaffold<Header: View, Content: View>: View {
    private let scrollable: Bool
    private let onRefresh: (() async -> Void)?
    private let header: Header
    private let content: Content

    init(
        scrollable: Bool = true,
        onRefresh: (() async -> Void)? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.scrollable = scrollable
        self.onRefresh = onRefresh
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                header
            }
            .padding(.horizontal, 22)

            if scrollable {
                if let onRefresh {
                    scroll.refreshable { await onRefresh() }
                } else {
                    scroll
                }
            } else {
                content
            }
        }
        .padding(.top, 18)
    }

    private var scroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(.horizontal, 22)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
    }
}
