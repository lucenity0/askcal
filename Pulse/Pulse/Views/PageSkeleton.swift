//
//  PageSkeleton.swift
//  Pulse
//
//  Brief placeholder shown while a page mounts during tab transitions.
//  Blocks, not a spinner — never a spinner.
//

import SwiftUI

struct PageSkeleton: View {
    @Environment(\.mono) private var mono
    @State private var dim = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                block(width: 64, height: 10)
                block(width: 148, height: 26)
            }
            SectionUnderline()
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(mono.surface)
                        .frame(width: 21, height: 21)
                    block(width: nil, height: 34)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .opacity(dim ? 0.55 : 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                dim = true
            }
        }
    }

    private func block(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(mono.surface)
            .frame(maxWidth: width ?? .infinity)
            .frame(height: height)
    }
}
