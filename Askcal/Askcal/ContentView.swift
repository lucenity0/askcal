//
//  ContentView.swift
//  Askcal
//
//  Root: vertical tab rail with a sliding liquid-glass active indicator,
//  coordinated content morph + brief skeleton on tab change, FAB, and the
//  once-a-day greeting overlay.
//

import SwiftUI

enum RailTab: String, CaseIterable {
    case today = "Today"
    case inbox = "Inbox"
    case calendar = "Calendar"
    case routine = "Routine"
    case tracks = "Tracks"
    case review = "Review"
    case more = "More"
}

struct ContentView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("themeMode") private var themeRaw = ThemeMode.storageDefault
    @State private var tab: RailTab = .today
    @State private var showComposer = false
    @State private var isAddingRoutine = false
    @State private var showGreeting = false
    @State private var didLaunch = false
    @Namespace private var railNS

    private var mode: ThemeMode { ThemeMode.stored(themeRaw) }
    private var mono: MonoPalette { .palette(for: mode) }

    /// Rail + content share one clock so the glass slide and the content
    /// morph read as a single motion.
    private var transitionSpring: Animation { .spring(response: 0.38, dampingFraction: 0.86) }

    // ── Tab sizing: each tab fits ITS OWN label, measured with the
    // Dynamic-Type-scaled font (a fixed-size measurement is exactly how
    // "Calendar" got clipped). Truncation only past a 12-char hard ceiling.
    private static let railWidth: CGFloat = 46

    private func tabTextWidth(_ label: String) -> CGFloat {
        let font = UIFontMetrics.default.scaledFont(
            for: .systemFont(ofSize: 12.5, weight: .medium)
        )
        let ceiling = ("MMMMMMMMMMMM" as NSString) // 12-char hard cap
            .size(withAttributes: [.font: font]).width
        let width = (label as NSString).size(withAttributes: [.font: font]).width
        return ceil(min(width, ceiling)) + 2
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack(spacing: 0) {
                rail
                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(mono.bg)
                    .clipShape(
                        .rect(topLeadingRadius: 18, bottomLeadingRadius: 18)
                    )
            }
            .background(mono.railInactive.ignoresSafeArea())

            if tab == .today || tab == .tracks || tab == .routine {
                FAB {
                    if tab == .routine {
                        isAddingRoutine = true
                    } else {
                        showComposer = true
                    }
                }
                .padding(.trailing, 22)
                .padding(.bottom, 28)
                .ignoresSafeArea(.keyboard) // FAB never rides the keyboard up
            }

            if showGreeting {
                // onboarding: plays on every cold launch, animated
                GreetingView(loggedIn: APIClient.shared.isConnected) {
                    withAnimation(.easeInOut(duration: 0.55)) { showGreeting = false }
                }
                // Move only. Fading the greeting fades its background too, so
                // Today read through it the whole time it was on screen —
                // the greeting is meant to be the screen, not a scrim over it.
                .transition(.move(edge: .top))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showComposer) {
            TaskComposerSheet()
                .environment(\.mono, mono)
        }
        .environment(\.mono, mono)
        .preferredColorScheme(mode.polarity)
        .animation(.easeInOut(duration: 0.25), value: themeRaw)
        .onAppear {
            if !didLaunch { didLaunch = true; showGreeting = true }
        }
        .task {
            await store.bootstrap()
            await NotificationManager.refreshSchedules(dayClosed: store.dayClosed)
        }
    }

    // MARK: - Content area: smooth cross-dissolve between tabs

    private var contentArea: some View {
        content
            .id(tab)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.99, anchor: .center)),
                        removal: .opacity
                    )
            )
            .animation(reduceMotion ? .easeInOut(duration: 0.15)
                                    : .easeInOut(duration: 0.28), value: tab)
    }

    private var content: some View {
        Group {
            switch tab {
            case .today: TodayView()
            case .inbox: InboxView()
            case .calendar: CalendarView()
            case .routine: RoutineView(isAdding: $isAddingRoutine)
            case .tracks: TracksView()
            case .review: ReviewView()
            case .more: MoreView()
            }
        }
    }

    private func switchTab(_ item: RailTab) {
        guard item != tab else { return }
        isAddingRoutine = false // leaving a tab always dismisses its inline input
        // one clock for the rail glass (spring) and the content cross-dissolve;
        // no skeleton flash — the content is already in memory, so faking a
        // load only made the switch feel janky
        withAnimation(transitionSpring) { tab = item }
    }

    // MARK: - Rail with liquid-glass indicator

    private var rail: some View {
        VStack(spacing: 0) {
            ForEach(RailTab.allCases, id: \.rawValue) { item in
                let textWidth = tabTextWidth(item.rawValue)
                Button {
                    switchTab(item)
                } label: {
                    Text(item.rawValue)
                        .font(MonoType.item(12.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(tab == item ? mono.textPrimary : mono.textSecondary)
                        .frame(width: textWidth)
                        .rotationEffect(.degrees(-90))
                        .frame(width: Self.railWidth, height: textWidth + 28)
                        .background {
                            if tab == item {
                                glassIndicator
                            }
                        }
                        .scaleEffect(tab == item ? 1.0 : 0.96)
                        .opacity(tab == item ? 1.0 : 0.85)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 8)
        .frame(width: Self.railWidth)
        .animation(reduceMotion ? nil : transitionSpring, value: tab)
        .ignoresSafeArea(.keyboard) // rail stays planted when the keyboard rises
    }

    @ViewBuilder
    private var glassIndicator: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12)
        if reduceMotion {
            // static fill, no morphing panel
            shape.fill(mono.bg).padding(.vertical, 3)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(mono.bg.opacity(0.55)))
                .overlay(
                    shape.strokeBorder(mono.border.opacity(0.6), lineWidth: 0.5)
                )
                .padding(.vertical, 3)
                .matchedGeometryEffect(id: "railGlass", in: railNS)
        }
    }
}

#Preview("Light") {
    ContentView().environment(AskcalStore())
}
