//
//  ContentView.swift
//  Askcal
//
//  Root: the day, a FAB, and the first-launch greeting.
//
//  The seven-tab vertical rail is gone. It gave equal billing to reference
//  material (Tracks, Routine, Calendar) and to the thing the app exists for,
//  and its rotated labels were the least readable text on the screen. The day
//  answers itself top to bottom, and anything that needs its own screen is
//  reached from the row that summarises it.
//
//  Narrow, that row pushes onto a navigation stack. Wide — an iPad in
//  landscape — it opens on the facing page instead, because a notebook you can
//  see both pages of should use them: the day on the left, whatever you looked
//  up on the right, and the wire down the middle where a real one is.
//
//  The split is decided on measured width, not size class. An iPad in portrait
//  is a regular-width device but is nowhere near wide enough for two readable
//  pages, and giving it a spread would produce two cramped columns instead of
//  one good page.
//

import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.webAuthenticationSession) private var webAuth
    @AppStorage("themeMode") private var themeRaw = ThemeMode.storageDefault
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    @State private var showComposer = false
    @State private var editingTask: AskcalTask?
    @State private var showGreeting = false
    @State private var didLaunch = false

    /// Narrow: what's pushed on top of the day.
    @State private var path: [PageDestination] = []
    /// Wide: what's open on the facing page. Never empty — a blank right-hand
    /// page on a spread reads as something failing to load.
    @State private var facing: PageDestination = .inbox
    @State private var isAddingRoutine = false

    /// Below this, two pages would each be too narrow to read. An iPad in
    /// portrait sits under it; the same iPad turned sideways sits over it.
    private static let spreadThreshold: CGFloat = 880

    private var mode: ThemeMode { ThemeMode.stored(themeRaw) }
    private var book: PaperPalette { .palette(for: mode) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { geo in
                if geo.size.width >= Self.spreadThreshold {
                    spread
                } else {
                    single
                }
            }
            .tint(book.ink)

            FAB { showComposer = true }
                .accessibilityLabel("New task")
                .padding(.trailing, Space.gutter)
                .padding(.bottom, 28)
                .ignoresSafeArea(.keyboard)   // FAB never rides the keyboard up

            if showGreeting {
                GreetingView(loggedIn: APIClient.shared.isConnected) {
                    withAnimation(.easeInOut(duration: 0.55)) { showGreeting = false }
                }
                // Move only. Fading it fades its background too, and Today
                // then reads through the whole time it is on screen.
                .transition(.move(edge: .top))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showComposer) {
            TaskComposerSheet()
                .environment(\.book, book)
        }
        .sheet(item: $editingTask) { task in
            TaskComposerSheet(editing: task)
                .environment(\.book, book)
        }
        .environment(\.book, book)
        .preferredColorScheme(mode.polarity)
        .animation(.easeInOut(duration: 0.25), value: themeRaw)
        .task {
            if !didLaunch {
                didLaunch = true
                // First run only. A 2.5s interstitial before every single
                // launch is a toll on the person who opens this most, and the
                // greeting says nothing that changes between launches.
                if !hasLaunchedBefore {
                    showGreeting = true
                    hasLaunchedBefore = true
                }
                await store.bootstrap()
                // Dropped in the one-day-surface restructure, so reminders
                // stopped being rescheduled on launch and only refreshed when
                // the day was closed or Settings was opened.
                await NotificationManager.refreshSchedules(dayClosed: store.dayClosed)
            }
        }
    }

    // MARK: - One page (phone, iPad portrait)

    private var single: some View {
        NavigationStack(path: $path) {
            pager { path.append($0) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PageDestination.self) { destination in
                    DestinationPage(destination: destination,
                                    isAddingRoutine: $isAddingRoutine)
                }
        }
    }

    // MARK: - Two pages (iPad, landscape)

    private var spread: some View {
        // Neither page draws its own wire: an open notebook is bound down the
        // middle and its outer edges are just paper. Leaving the day page's
        // leading spine on gave the spread two bindings, one of them along an
        // edge no notebook is bound at.
        HStack(spacing: 0) {
            pager { facing = $0 }

            DestinationPage(destination: facing, isAddingRoutine: $isAddingRoutine)
                .id(facing)
                .transition(.opacity)
        }
        .environment(\.boundPage, false)
        .overlay {
            BindingEdge(placement: .gutter)
                .ignoresSafeArea(edges: .vertical)
        }
        .animation(.easeInOut(duration: 0.2), value: facing)
    }

    private func pager(onOpen: @escaping (PageDestination) -> Void) -> some View {
        DayPager(
            showComposer: $showComposer,
            editingTask: $editingTask,
            onConnect: connect,
            onOpen: onOpen
        )
    }

    private func connect() {
        Task {
            guard let url = APIClient.shared.authStartURL(scheme: "askcal") else { return }
            do {
                let callback = try await webAuth.authenticate(
                    using: url,
                    callbackURLScheme: "askcal",
                    preferredBrowserSession: .shared
                )
                if let account = APIClient.shared.handleAuthCallback(callback) {
                    await store.connected(email: account.email, name: account.name)
                }
            } catch {
                // Cancelling the sheet is not an error worth reporting.
            }
        }
    }
}
