//
//  ContentView.swift
//  Askcal
//
//  Root: one day surface in a navigation stack, a FAB, and the cold-launch
//  greeting.
//
//  The seven-tab vertical rail is gone. It gave equal billing to reference
//  material (Tracks, Routine, Calendar) and to the thing the app exists for,
//  and its rotated labels were the least readable text on the screen. What
//  replaced it is DayView: the day answers itself top to bottom, and anything
//  that needs its own screen is reached from the row that summarises it.
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

    private var mode: ThemeMode { ThemeMode.stored(themeRaw) }
    private var book: PaperPalette { .palette(for: mode) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NavigationStack {
                DayPager(
                    showComposer: $showComposer,
                    editingTask: $editingTask,
                    onConnect: connect
                )
                .toolbar(.hidden, for: .navigationBar)
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
