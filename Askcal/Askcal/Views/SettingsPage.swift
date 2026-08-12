//
//  SettingsPage.swift
//  Askcal
//
//  Settings, against the actual backend.
//
//  The old More screen was a list of local toggles that changed nothing on the
//  server: nudge switches that only ever wrote to UserDefaults, a version
//  string, a name field. Meanwhile the things that decide what Askcal actually
//  does — whether mail gets classified at all, how eager it is to make work out
//  of it — were invisible, and one of them was silently off for weeks.
//
//  So this leads with the classifier's health. If mail is not being read, that
//  is the single most useful fact the app can tell you, and it should not take
//  a curl against /health to find out.
//
//  Nothing here writes the classifier credential. It lives in the environment
//  on the server, and a settings screen able to change it would mean a
//  subscription token travelling from a phone through the API into a database.
//

import AuthenticationServices
import SwiftUI

struct SettingsPage: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.book) private var book
    @Environment(\.webAuthenticationSession) private var webAuth

    @Binding var composing: ComposerIntent?

    @AppStorage("themeMode") private var themeRaw = ThemeMode.storageDefault
    @AppStorage("userName") private var userName = ""
    // The source of truth for the reminders, because the scheduler reads these.
    @AppStorage("morningDigest") private var morningDigest = true
    @AppStorage("morningHour") private var morningHour = 8
    @AppStorage("eveningNudge") private var eveningNudge = true
    @AppStorage("eveningHour") private var eveningHour = 21

    @State private var settings: AppSettings?
    @State private var loadError: String?
    @State private var nameDraft = ""
    @State private var savingName = false
    @State private var showDeleteConfirm = false

    private var themeSelection: Binding<ThemeMode> {
        Binding(
            get: { ThemeMode.stored(themeRaw) },
            set: { new in
                withAnimation(.easeInOut(duration: 0.25)) { themeRaw = new.rawValue }
            }
        )
    }

    var body: some View {
        NavigationStack {
            NotebookPage {
                PageTitle(kicker: "Settings", title: "Askcal")

                if store.isLive { classifierBlock }
                accountBlock
                appearanceBlock
                if store.isLive {
                    syncBlock
                    autoTaskBlock
                }
                remindersBlock
                referenceBlock
                if !store.isLive { localDataBlock }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .tracks: TracksView(composing: $composing)
                }
            }
            .task { await load() }
            .onAppear { if nameDraft.isEmpty { nameDraft = userName } }
            .sheet(isPresented: $showDeleteConfirm) {
                DeleteLocalDataSheet { store.deleteLocalData(); nameDraft = userName }
                    .environment(\.book, book)
            }
        }
    }

    private enum SettingsDestination: Hashable { case tracks }

    // MARK: - Is it actually working?

    @ViewBuilder
    private var classifierBlock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Rubric("classifier")

            if let c = settings?.classifier {
                HStack(alignment: .top, spacing: Space.lg) {
                    // Shape, not colour — the palette has one ink, so a filled
                    // mark is the only way to say "working" without inventing
                    // a green that exists nowhere else in the app.
                    Circle()
                        .fill(c.configured ? book.fill : .clear)
                        .overlay(Circle().strokeBorder(book.ruleStrong, lineWidth: Stroke.strong))
                        .frame(width: 10, height: 10)
                        .padding(.top, Space.sm)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(c.configured ? "Reading your mail" : "Not running")
                            .font(BookType.entry(16))
                            .foregroundStyle(book.ink)
                        Text("\(c.provider) · \(c.model)")
                            .font(BookType.meta(10))
                            .foregroundStyle(book.inkSub)
                        if let detail = c.detail {
                            Text(detail)
                                .font(BookType.body(13))
                                .foregroundStyle(book.inkDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, Space.xs)
                        }
                        if !c.configured {
                            Text("mail still arrives, but nothing ranks it and nothing becomes a task on its own.")
                                .font(BookType.body(13))
                                .foregroundStyle(book.inkSub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            } else if let loadError {
                Text(loadError)
                    .font(BookType.body(13))
                    .foregroundStyle(book.inkDim)
            } else {
                SkeletonRows(rows: 1)
            }
            PageRule()
        }
    }

    // MARK: - Sync

    @ViewBuilder
    private var syncBlock: some View {
        if let sync = settings?.sync {
            VStack(alignment: .leading, spacing: Space.lg) {
                Rubric("sync")
                factRow("Every", "\(sync.intervalMinutes) min")
                factRow("Looks back", "\(sync.windowDays) days")
                factRow("Last run", sync.lastSyncedAt.map {
                    $0.formatted(.relative(presentation: .named))
                } ?? "never")
                Button("Sync now") { Task { await store.syncInbox() } }
                    .buttonStyle(PillButtonStyle(filled: false))
                PageRule()
            }
        }
    }

    // MARK: - Auto-tasking

    @ViewBuilder
    private var autoTaskBlock: some View {
        if let auto = settings?.autoTask {
            VStack(alignment: .leading, spacing: Space.lg) {
                Rubric("making tasks by itself")
                Text("both gates compound: the score is already damped by confidence, so raising either makes it markedly more careful.")
                    .font(BookType.body(13))
                    .foregroundStyle(book.inkSub)
                    .fixedSize(horizontal: false, vertical: true)

                slider("How sure it must be",
                       value: auto.minConfidence,
                       range: 0.3...0.95,
                       step: 0.05,
                       format: { "\(Int($0 * 100))%" }) { new in
                    await patch(["autoTaskMinConfidence": new])
                }

                slider("How consequential",
                       value: Double(auto.minRegret),
                       range: 0...80,
                       step: 5,
                       format: { "\(Int($0)) / 100" }) { new in
                    await patch(["autoTaskMinRegret": Int(new)])
                }
                PageRule()
            }
        }
    }

    // MARK: - Reminders

    /// Local-first, deliberately.
    ///
    /// These are scheduled on the device by `NotificationManager`, which reads
    /// them from UserDefaults — so they have to work with no account and no
    /// network. Gating them on the settings fetch meant a backend that was down
    /// (or, as it turned out, simply not deployed yet) removed two switches
    /// that had worked offline for months. The server copy is a sync, not the
    /// source.
    @ViewBuilder
    private var remindersBlock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Rubric("reminders")
            reminderRow("Morning digest", "what today asks of you",
                        isOn: $morningDigest, hour: $morningHour,
                        onKey: "morningDigest", hourKey: "morningHour")
            reminderRow("Evening nudge", "how the day went",
                        isOn: $eveningNudge, hour: $eveningHour,
                        onKey: "eveningNudge", hourKey: "eveningHour")
            PageRule()
        }
    }

    private func reminderRow(
        _ title: String, _ note: String,
        isOn: Binding<Bool>, hour: Binding<Int>, onKey: String, hourKey: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(title)
                        .font(BookType.entry(16))
                        .foregroundStyle(book.ink)
                    Text(note)
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { isOn.wrappedValue },
                    set: { new in
                        // Applies immediately; the server is told afterwards
                        // and its failure does not undo the switch.
                        isOn.wrappedValue = new
                        Task {
                            await NotificationManager.refreshSchedules(
                                dayClosed: store.dayClosed
                            )
                            if store.isLive { await patch([onKey: new]) }
                        }
                    }
                ))
                .labelsHidden()
                .toggleStyle(PaperToggleStyle())
                .accessibilityLabel(title)
            }
            if isOn.wrappedValue {
                ChipPicker(
                    options: Array(stride(from: 5, through: 23, by: 1)),
                    title: { (h: Int) in String(format: "%02d:00", h) },
                    selection: Binding(
                        get: { hour.wrappedValue },
                        set: { new in
                            hour.wrappedValue = new
                            Task {
                                await NotificationManager.refreshSchedules(
                                    dayClosed: store.dayClosed
                                )
                                if store.isLive { await patch([hourKey: new]) }
                            }
                        }
                    ),
                    wraps: true,
                    bordered: false
                )
            }
        }
    }

    // MARK: - Account, appearance, reference

    private var accountBlock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Rubric("account")
            if store.isLive {
                factRow("Signed in", store.accountEmail ?? "—")
                Button("Disconnect") { store.disconnect() }
                    .buttonStyle(PillButtonStyle(filled: false))
            } else {
                Text("not connected. tasks live on this device only.")
                    .font(BookType.body(14))
                    .foregroundStyle(book.inkDim)
                Button("Connect Gmail") { connect() }
                    .buttonStyle(PillButtonStyle(filled: true))
            }
            nameField
            PageRule()
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("What mornings call you")
                .font(BookType.meta(10))
                .foregroundStyle(book.inkSub)
            HStack(spacing: Space.md) {
                TextField("your name", text: $nameDraft)
                    .font(BookType.body(15))
                    .foregroundStyle(book.ink)
                    .padding(Space.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.block)
                            .fill(book.card)
                            .overlay(RoundedRectangle(cornerRadius: Radius.block)
                                .strokeBorder(book.rule, lineWidth: Stroke.hair))
                    )
                Button("Save") { saveName() }
                    .buttonStyle(PillButtonStyle(filled: true))
                    .disabled(savingName || nameDraft.isEmpty || nameDraft == userName)
            }
        }
    }

    private var appearanceBlock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Rubric("appearance")
            HStack {
                Text("Theme")
                    .font(BookType.entry(16))
                    .foregroundStyle(book.ink)
                Spacer()
                ChipPicker(options: ThemeMode.allCases,
                           title: { (m: ThemeMode) in m.label },
                           selection: themeSelection)
            }
            PageRule()
        }
    }

    private var referenceBlock: some View {
        VStack(spacing: 0) {
            NavigationLink(value: SettingsDestination.tracks) {
                SettingsRow(title: "Tracks", value: "\(store.openTasks.count) open")
            }
            .buttonStyle(.plain)
            factRow("Version", Self.appVersion)
        }
    }

    @ViewBuilder
    private var localDataBlock: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            PageRule()
            Rubric("local data")
            Text("everything on this device: tasks and check-offs. can't be undone.")
                .font(BookType.body(13))
                .foregroundStyle(book.inkSub)
                .fixedSize(horizontal: false, vertical: true)
            Button("Delete everything", role: .destructive) { showDeleteConfirm = true }
                .buttonStyle(PillButtonStyle(filled: false))
        }
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: - Pieces

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(BookType.body(14))
                .foregroundStyle(book.inkDim)
            Spacer()
            Text(value)
                .font(BookType.meta(11))
                .foregroundStyle(book.inkSub)
        }
        .padding(.vertical, Space.sm)
    }

    private func slider(
        _ label: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        commit: @escaping (Double) async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                Text(label)
                    .font(BookType.body(14))
                    .foregroundStyle(book.inkDim)
                Spacer()
                Text(format(value))
                    .font(BookType.meta(11))
                    .foregroundStyle(book.ink)
            }
            Slider(
                value: Binding(get: { value }, set: { new in Task { await commit(new) } }),
                in: range,
                step: step
            )
            .tint(book.fill)
            .accessibilityLabel(label)
            .accessibilityValue(format(value))
        }
    }

    // MARK: - Wiring

    private func load() async {
        guard store.isLive else { return }
        do {
            let fetched = try await APIClient.shared.settings()
            settings = fetched
            morningDigest = fetched.reminders.morningDigest
            morningHour = fetched.reminders.morningHour
            eveningNudge = fetched.reminders.eveningNudge
            eveningHour = fetched.reminders.eveningHour
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "couldn't read your settings."
        }
    }

    /// Writes one change and takes the server's answer as the new truth, rather
    /// than assuming the write landed — a slider that springs back is honest
    /// about a failure in a way an optimistic one is not.
    private func patch(_ changes: [String: Any?]) async {
        do {
            settings = try await APIClient.shared.updateSettings(changes)
            Haptics.tick()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "couldn't save that."
        }
    }

    private func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        savingName = true
        Task {
            if store.isLive {
                userName = (try? await APIClient.shared.updateName(trimmed)) ?? trimmed
            } else {
                userName = trimmed
            }
            savingName = false
            Haptics.tick()
        }
    }

    private func connect() {
        Task {
            guard let url = APIClient.shared.authStartURL(scheme: "askcal") else { return }
            if let callback = try? await webAuth.authenticate(
                using: url, callbackURLScheme: "askcal", preferredBrowserSession: .shared
            ), let account = APIClient.shared.handleAuthCallback(callback) {
                await store.connected(email: account.email, name: account.name)
                await load()
            }
        }
    }
}

// MARK: - Delete-local-data confirmation (type DELETE)

struct DeleteLocalDataSheet: View {
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
