//
//  MoreView.swift
//  Askcal
//
//  Settings: account, theme, your name (for the greeting), nudges.
//

import AuthenticationServices
import SwiftUI

struct MoreView: View {
    /// Read from the bundle, not hardcoded — the literal here said 0.1.0 while
    /// MARKETING_VERSION had moved on to 1.0, so the settings screen quietly
    /// reported the wrong build to the only person who would ever check it.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book
    @Environment(\.webAuthenticationSession) private var webAuth
    @AppStorage("themeMode") private var themeRaw = ThemeMode.storageDefault
    @AppStorage("userName") private var userName = ""
    @AppStorage("morningDigest") private var morningDigest = true
    @AppStorage("eveningNudge") private var eveningNudge = true
    @State private var connectError: String?

    /// Routine's inline add field is opened from this screen's toolbar, so the
    /// flag has to live above the pushed view.
    @Binding var isAddingRoutine: Bool
    @Binding var composing: ComposerIntent?

    @State private var nameDraft = ""
    @State private var savingName = false
    @State private var nameStatus: SaveStatus = .idle
    @State private var showDeleteConfirm = false

    private enum SaveStatus { case idle, success, failure }

    /// The stored value is a raw string that may still be one of the older
    /// names, so the picker works in `ThemeMode` and writes back the current
    /// spelling rather than binding straight to `themeRaw`.
    private var themeSelection: Binding<ThemeMode> {
        Binding(
            get: { ThemeMode.stored(themeRaw) },
            set: { newValue in
                withAnimation(.easeInOut(duration: 0.25)) { themeRaw = newValue.rawValue }
            }
        )
    }

    var body: some View {
        NavigationStack {
            page
                .navigationDestination(for: MoreDestination.self) { destination in
                    switch destination {
                    case .routine: RoutineView(isAdding: $isAddingRoutine)
                    case .tracks: TracksView(composing: $composing)
                    }
                }
        }
    }

    /// Where the reference material lives now.
    ///
    /// Routine and Tracks used to be rows under the day's entries, which meant
    /// writing anything down pushed them further off the screen. They are
    /// things you consult, so they sit behind More rather than competing with
    /// the day for the top of it.
    private enum MoreDestination: Hashable { case routine, tracks }

    private var page: some View {
        NotebookPage {
            PageTitle(kicker: "Settings", title: "More")

                VStack(spacing: 0) {
                    NavigationLink(value: MoreDestination.routine) {
                        SettingsRow(title: "Routine",
                                    value: store.routines.isEmpty
                                        ? "none set"
                                        : "\(store.routinesDone.count) of \(store.routines.count)")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: MoreDestination.tracks) {
                        SettingsRow(title: "Tracks", value: "\(store.openTasks.count) open")
                    }
                    .buttonStyle(.plain)
                }

                accountSection
                PageRule()

                // Theme switch
                HStack {
                    Text("Theme")
                        .font(BookType.entry())
                        .foregroundStyle(book.ink)
                    Spacer()
                    ChipPicker(options: ThemeMode.allCases,
                               title: \.label,
                               selection: themeSelection)
                }
                PageRule()

                // Name — used by the greeting
                nameSection
                PageRule()

                // Nudges
                toggleRow("Morning digest", subtitle: "08:30 — your day is ready", isOn: $morningDigest)
                toggleRow("Evening nudge", subtitle: "21:00 — close the day", isOn: $eveningNudge)

                settingRow("Tracks", value: "\(TrackKey.allCases.count) tracks")
                settingRow("Version", value: Self.appVersion)

                if !store.isLive {
                    PageRule()
                    localDataSection
                }
        }
        .onAppear { if nameDraft.isEmpty { nameDraft = userName } }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteLocalDataSheet { store.deleteLocalData(); nameDraft = userName }
                .environment(\.book, book)
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(BookType.entry())
                .foregroundStyle(book.ink)
            HStack(spacing: 10) {
                TextField("what should mornings call you?", text: $nameDraft)
                    .font(BookType.body(14))
                    .foregroundStyle(book.ink)
                    .onChange(of: nameDraft) { nameStatus = .idle }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(book.card)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(book.rule, lineWidth: 1))
                    )
                Button {
                    saveName()
                } label: {
                    if savingName {
                        ProgressView().tint(book.fillText).frame(width: 44)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(PillButtonStyle(filled: true))
                .disabled(savingName || nameDraft.trimmingCharacters(in: .whitespaces).isEmpty
                          || nameDraft == userName)
            }
            switch nameStatus {
            case .success:
                Text("saved — mornings will call you \(userName.lowercased()).")
                    .font(BookType.meta(10)).foregroundStyle(book.inkSub)
            case .failure:
                Text("couldn't save — check your connection and try again.")
                    .font(BookType.meta(10)).foregroundStyle(book.inkSub)
            case .idle:
                EmptyView()
            }
        }
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savingName = true
        nameStatus = .idle
        Task {
            var ok = true
            if store.isLive {
                do { userName = try await APIClient.shared.updateName(trimmed) }
                catch { ok = false }
            } else {
                userName = trimmed
            }
            savingName = false
            nameStatus = ok ? .success : .failure
            if ok { Haptics.tick() }
        }
    }

    // MARK: - Local data (not signed in)

    private var localDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local data")
                .font(BookType.entry())
                .foregroundStyle(book.ink)
            Text("you're not signed in — tasks and routines live only on this device.")
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
            Button("Delete local data") { showDeleteConfirm = true }
                .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    // MARK: - Account

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google account")
                        .font(BookType.entry())
                        .foregroundStyle(book.ink)
                    Text(store.isLive ? (store.accountEmail ?? "connected")
                                      : "demo data — connect to go live")
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
                Spacer()
                if store.isLive {
                    Button("Disconnect") { store.disconnect() }
                        .buttonStyle(PillButtonStyle(filled: false))
                } else {
                    Button("Connect") { connectGoogle() }
                        .buttonStyle(PillButtonStyle(filled: true))
                }
            }
            if let error = connectError ?? store.syncError {
                Text(error)
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
            }
            if store.isLive {
                Button("Sync inbox now") {
                    Task { await store.syncInbox() }
                }
                .buttonStyle(PillButtonStyle(filled: false))
            }
        }
    }

    private func connectGoogle() {
        connectError = nil
        guard let url = APIClient.shared.authStartURL(scheme: "askcal") else {
            connectError = "bad API URL."
            return
        }
        Task {
            do {
                let callback = try await webAuth.authenticate(
                    using: url,
                    callbackURLScheme: "askcal",
                    preferredBrowserSession: .shared
                )
                if let account = APIClient.shared.handleAuthCallback(callback) {
                    await store.connected(email: account.email, name: account.name)
                } else {
                    connectError = "couldn't read the sign-in response."
                }
            } catch {
                connectError = "sign-in cancelled or failed."
            }
        }
    }

    private func toggleRow(_ label: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(BookType.entry())
                        .foregroundStyle(book.ink)
                    Text(subtitle)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
                    .onChange(of: isOn.wrappedValue) {
                        Task { await NotificationManager.refreshSchedules(dayClosed: store.dayClosed) }
                    }
            }
            PageRule()
        }
    }

    private func settingRow(_ label: String, value: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(label)
                    .font(BookType.entry())
                    .foregroundStyle(book.ink)
                Spacer()
                Text(value)
                    .font(BookType.meta())
                    .foregroundStyle(book.inkSub)
            }
            PageRule()
        }
    }
}

// MARK: - Delete-local-data confirmation (type DELETE)

private struct DeleteLocalDataSheet: View {
    let onConfirm: () -> Void
    @Environment(\.book) private var book
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var armed: Bool { typed == "DELETE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageTitle(kicker: "Irreversible", title: "Delete local data", size: 24)

            Text("This wipes every task, routine and check-off stored on this device. It can't be undone. Type DELETE to confirm.")
                .font(BookType.body(14))
                .foregroundStyle(book.inkSub)
                .fixedSize(horizontal: false, vertical: true)

            TextField("DELETE", text: $typed)
                .font(BookType.entry())
                .foregroundStyle(book.ink)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(book.card)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(armed ? book.fill : book.rule, lineWidth: 1))
                )

            Button("Delete everything") {
                onConfirm()
                dismiss()
            }
            .buttonStyle(PillButtonStyle(filled: true, fullWidth: true))
            .disabled(!armed)
            .opacity(armed ? 1 : 0.4)

            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle(filled: false, fullWidth: true))

            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground(book.paper)
    }
}
