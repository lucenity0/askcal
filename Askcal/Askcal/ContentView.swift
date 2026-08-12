//
//  ContentView.swift
//  Askcal
//
//  Root: four tabs, and the launch greeting.
//
//  Everything used to live on one scrolling surface — the day's entries, then
//  Inbox, Routine, Tracks and Review stacked underneath. That meant writing
//  down a task pushed the rest of the app further down the screen, so the day
//  never had a settled shape and nothing had a fixed place to be. Tabs fix
//  that: the day is the day, and the other three are where they always are.
//
//  The horizontal page turn is gone with it. Paging the whole screen sideways
//  to reach Thursday was a lot of motion for a move the week strip now does in
//  one tap, without the day sliding out from under you each time.
//

import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.webAuthenticationSession) private var webAuth
    @AppStorage("themeMode") private var themeRaw = ThemeMode.storageDefault

    @State private var tab: PageDestination = .today
    @State private var showComposer = false
    @State private var editingTask: AskcalTask?
    @State private var isAddingRoutine = false
    @State private var showGreeting = false
    @State private var didLaunch = false

    private var mode: ThemeMode { ThemeMode.stored(themeRaw) }
    private var book: PaperPalette { .palette(for: mode) }

    var body: some View {
        ZStack {
            tabs

            if showGreeting {
                GreetingView(loggedIn: APIClient.shared.isConnected) {
                    withAnimation(.easeInOut(duration: 0.55)) { showGreeting = false }
                }
                // Move only. Fading it fades its background too, and the day
                // then reads through the whole time it is on screen.
                .transition(.move(edge: .top))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $showComposer) {
            TaskComposerSheet().environment(\.book, book)
        }
        .sheet(item: $editingTask) { task in
            TaskComposerSheet(editing: task).environment(\.book, book)
        }
        .environment(\.book, book)
        .preferredColorScheme(mode.polarity)
        .animation(.easeInOut(duration: 0.25), value: themeRaw)
        .task {
            guard !didLaunch else { return }
            didLaunch = true
            showGreeting = true
            await store.bootstrap()
            await NotificationManager.refreshSchedules(dayClosed: store.dayClosed)
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(PageDestination.today.title, systemImage: "calendar.day.timeline.left",
                value: .today) {
                TodayPage(
                    editingTask: $editingTask,
                    showComposer: $showComposer,
                    onConnect: connect,
                    onOpenReview: { tab = .review }
                )
            }

            Tab(PageDestination.inbox.title, systemImage: "tray", value: .inbox) {
                InboxView()
            }
            .badge(store.inboxEmails.count)

            Tab(PageDestination.calendar.title, systemImage: "calendar", value: .calendar) {
                CalendarView()
            }

            Tab(PageDestination.more.title, systemImage: "ellipsis.circle", value: .more) {
                MoreView(isAddingRoutine: $isAddingRoutine)
            }

            // Reached from the day's end-of-day card rather than from the bar:
            // closing the day is something you do once, not a place you live.
            Tab(PageDestination.review.title, systemImage: "moon", value: .review) {
                ReviewView()
            }
            .hidden()
        }
        .tint(book.ink)
        .toolbarBackground(book.recessed, for: .tabBar)
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
