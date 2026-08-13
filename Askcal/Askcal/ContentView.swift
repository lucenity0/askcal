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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("themeMode") private var themeRaw = ThemeMode.storageDefault

    @State private var tab: PageDestination = .today
    @State private var composing: ComposerIntent?
    @State private var openedEmail: EmailItem?
    /// Identifiable so Review rides the same popup machinery as everything
    /// else. A plain Bool cannot drive `.popup(item:)`.
    private struct ReviewRequest: Identifiable { let id = "review" }
    @State private var review: ReviewRequest?
    @State private var digestKind: DigestKind?
    @State private var digest: Digest?
    @State private var digestError: String?
    @State private var windowWidth: CGFloat = 0
    private var isWide: Bool { windowWidth >= SpreadMetrics.threshold }
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
        // Read without a GeometryReader in the layout path — one there would
        // take all the height it was offered and hand none back.
        .background(
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size.width, initial: true) { _, w in
                    windowWidth = w
                }
            }
        )
        .popup(item: $composing) { intent in
            TaskComposer(intent: intent) { composing = nil }
        }
        // Suppressed once the inbox is a spread: the mail is already open on the
        // facing page, and a popup would dim a list that had room to stay
        // readable. Measured here rather than passed up, because this is the
        // view that owns the popup and the width is the same one the spread
        // inside the tab is looking at.
        .popup(item: Binding(
            get: { isWide ? nil : openedEmail },
            set: { openedEmail = $0 }
        )) { email in
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
        .popup(item: $digestKind) { kind in
            DigestCard(kind: kind, digest: digest, error: digestError) {
                digestKind = nil
            }
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
        // Coming back to the app refetches. The server syncs on its own every
        // few minutes, but nothing told the app about it — so mail that had
        // arrived and been ranked an hour ago was simply not on screen until
        // something was pulled by hand, which read as the sync being broken.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, didLaunch else { return }
            Task { await store.refreshAll() }
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(PageDestination.today.title, systemImage: "calendar.day.timeline.left",
                value: .today) {
                TodayPage(
                    composing: $composing,
                    onConnect: connect,
                    onOpenReview: { review = .init() },
                    onOpenDigest: { openDigest($0) }
                )
            }

            Tab(PageDestination.inbox.title, systemImage: "tray", value: .inbox) {
                InboxView(opened: $openedEmail)
            }
            .badge(store.inboxEmails.count)

            Tab(PageDestination.calendar.title, systemImage: "calendar", value: .calendar) {
                CalendarView(composing: $composing)
            }

            Tab(PageDestination.settings.title, systemImage: "gearshape", value: .settings) {
                SettingsPage(composing: $composing)
            }
        }
        .tint(book.ink)
        .toolbarBackground(book.recessed, for: .tabBar)
    }

    /// Opens the popup immediately and fills it when the fetch lands, rather
    /// than waiting on the network before showing anything — a tap that does
    /// nothing for a second reads as a tap that missed.
    private func openDigest(_ kind: DigestKind) {
        digest = nil
        digestError = nil
        digestKind = kind
        Task {
            do {
                digest = try await APIClient.shared.digest(kind)
            } catch {
                digestError = (error as? LocalizedError)?.errorDescription
                    ?? "couldn't put your day together."
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
