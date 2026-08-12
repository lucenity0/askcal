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
    @State private var composing: ComposerIntent?
    @State private var openedEmail: EmailItem?
    /// Identifiable so Review rides the same popup machinery as everything
    /// else. A plain Bool cannot drive `.popup(item:)`.
    private struct ReviewRequest: Identifiable { let id = "review" }
    @State private var review: ReviewRequest?
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
        // Popups live at the root so they cover the tab bar. Presented lower
        // down, the bar stays tappable underneath and you can end up on another
        // tab with a modal still open over it.
        .popup(item: $composing) { intent in
            TaskComposer(intent: intent) { composing = nil }
        }
        .popup(item: $openedEmail) { email in
            EmailDetail(
                email: email,
                makeTask: { store.handleEmail(email); openedEmail = nil },
                snooze: { store.snoozeEmail(email); openedEmail = nil },
                onClose: { openedEmail = nil }
            )
        }
        .popup(item: $review) { _ in
            ReviewSheet { review = nil }
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
                    composing: $composing,
                    onConnect: connect,
                    onOpenReview: { review = .init() }
                )
            }

            Tab(PageDestination.inbox.title, systemImage: "tray", value: .inbox) {
                InboxView(opened: $openedEmail)
            }
            .badge(store.inboxEmails.count)

            Tab(PageDestination.calendar.title, systemImage: "calendar", value: .calendar) {
                CalendarView(composing: $composing)
            }

            Tab(PageDestination.more.title, systemImage: "ellipsis.circle", value: .more) {
                MoreView(composing: $composing)
            }
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
