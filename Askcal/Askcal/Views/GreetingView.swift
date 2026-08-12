//
//  GreetingView.swift
//  Askcal
//
//  Once-a-day greeting: a heartbeat line draws itself, the greeting fades up,
//  then the whole screen retreats to reveal Today. Tap anywhere to skip.
//

import SwiftUI

struct GreetingView: View {
    var loggedIn: Bool = false
    let onFinished: () -> Void
    @Environment(\.book) private var book
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("userName") private var userName = ""

    @State private var lineProgress: CGFloat = 0
    @State private var showText = false
    @State private var finished = false

    private var greeting: String {
        // signed-out gets the playful line; signed-in gets the time + name
        guard loggedIn else { return "hello, human? i hope." }
        let hour = Calendar.current.component(.hour, from: .now)
        let word: String
        switch hour {
        case 5..<12: word = "good morning"
        case 12..<17: word = "good afternoon"
        default: word = "good evening"
        }
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "\(word)." : "\(word), \(name.lowercased())."
    }

    private var dateKicker: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        ZStack {
            // Explicit and full-bleed. A Color inside the ZStack was letting
            // Today read through underneath — the greeting is meant to be the
            // whole screen, not a layer over it.
            Rectangle()
                .fill(book.paper)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)

            VStack(spacing: Space.section) {
                // The room fades up rather than drawing itself on. A scene
                // assembling pixel by pixel would be a second animation
                // competing with the one inside it — the cat is already
                // breathing, the clouds are already moving.
                LaunchScene()
                    // The room's own ratio, not a round number: the frame and
                    // the drawing have to agree or the scene letterboxes
                    // inside its own card.
                    .aspectRatio(LaunchScene.W / LaunchScene.H, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card)
                            .strokeBorder(book.rule, lineWidth: Stroke.hair)
                    )
                    .padding(.horizontal, Space.gutter)
                    .opacity(lineProgress)
                    .scaleEffect(0.97 + 0.03 * lineProgress, anchor: .bottom)

                VStack(spacing: Space.md) {
                    Text(dateKicker)
                        .font(BookType.kicker(12))
                        .foregroundStyle(book.inkSub)
                    Text(greeting)
                        .font(BookType.display(30))
                        .foregroundStyle(book.ink)
                }
                .opacity(showText ? 1 : 0)
                .offset(y: showText ? 0 : 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task {
            if reduceMotion {
                lineProgress = 1
                showText = true
                try? await Task.sleep(for: .seconds(1.4))
                finish()
                return
            }
            withAnimation(.easeInOut(duration: 1.1)) { lineProgress = 1 }
            try? await Task.sleep(for: .seconds(0.85))
            withAnimation(.easeOut(duration: 0.45)) { showText = true }
            try? await Task.sleep(for: .seconds(1.7))
            finish()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}

/// One heartbeat across the width: flat → small bump → tall spike → dip → flat.
struct HeartbeatLine: Shape {
    func path(in rect: CGRect) -> Path {
        let midY = rect.midY
        let h = rect.height / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.width * x, y: midY + h * y)
        }
        var p = Path()
        p.move(to: pt(0, 0))
        p.addLine(to: pt(0.28, 0))
        p.addLine(to: pt(0.34, -0.18))
        p.addLine(to: pt(0.40, 0))
        p.addLine(to: pt(0.46, -0.85))
        p.addLine(to: pt(0.53, 0.42))
        p.addLine(to: pt(0.58, 0))
        p.addLine(to: pt(1.0, 0))
        return p
    }
}
