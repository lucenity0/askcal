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
    @State private var accounts: [MailAccount] = []
    @State private var expanded: Set<UUID> = []
    @State private var labelDrafts: [UUID: String] = [:]
    @State private var linking = false
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
                mailboxBlock
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

    /// Every mailbox Askcal reads, and what each one usually carries.
    ///
    /// There used to be one, and it was the account you signed in with, so a
    /// college address and a personal one could not both be here. The track
    /// picker is the useful part: it tells the classifier what mail at that
    /// address normally is, which is most of what makes a second inbox worth
    /// connecting at all.
    @ViewBuilder
    private var mailboxBlock: some View {
        if store.isLive {
            VStack(alignment: .leading, spacing: Space.lg) {
                Rubric("mailboxes")

                ForEach(accounts) { account in
                    mailboxRow(account)
                }

                Button(linking ? "opening…" : "Connect another mailbox") { linkAnother() }
                    .buttonStyle(PillButtonStyle(filled: false))
                    .disabled(linking)

                PageRule()
            }
            .task { await loadAccounts() }
        }
    }

    /// One mailbox: a name, a switch, and everything else behind a tap.
    ///
    /// The address used to be the title, set in the big serif, so it wrapped
    /// across two lines and shouted the one thing you already know. It is a
    /// caption now. What you actually came here to change — what this mailbox
    /// is usually about — is what opens.
    @ViewBuilder
    private func mailboxRow(_ account: MailAccount) -> some View {
        let open = expanded.contains(account.id)

        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.md) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if open { expanded.remove(account.id) } else { expanded.insert(account.id) }
                    }
                } label: {
                    HStack(spacing: Space.md) {
                        Image(systemName: "chevron.right")
                            .font(BookType.icon(10))
                            .foregroundStyle(book.inkSub)
                            .rotationEffect(.degrees(open ? 90 : 0))
                        VStack(alignment: .leading, spacing: Space.hair) {
                            Text(account.title)
                                .font(BookType.entry(16))
                                .foregroundStyle(book.ink)
                            Text(mailboxCaption(account))
                                .font(BookType.meta(10))
                                .foregroundStyle(book.inkSub)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: Space.md)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(account.title)
                .accessibilityHint(open ? "Collapse" : "Expand")

                Toggle("", isOn: Binding(
                    get: { account.active },
                    set: { on in setAccount(account, active: on) }
                ))
                .labelsHidden()
                .toggleStyle(PaperToggleStyle())
                .accessibilityLabel("Read \(account.title)")
            }

            if open {
                mailboxDetail(account)
            }
        }
        .padding(.vertical, Space.md)
        .ruled()
    }

    @ViewBuilder
    private func mailboxDetail(_ account: MailAccount) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text("call it")
                    .font(BookType.meta(10))
                    .foregroundStyle(book.inkSub)
                TextField(
                    "college, work, personal…",
                    text: Binding(
                        get: { labelDrafts[account.id] ?? account.label ?? "" },
                        set: { labelDrafts[account.id] = $0 }
                    )
                )
                .font(BookType.body(15))
                .foregroundStyle(book.ink)
                .submitLabel(.done)
                .onSubmit {
                    setAccount(account, label: labelDrafts[account.id] ?? "")
                }
            }

            if !store.tracks.isEmpty {
                VStack(alignment: .leading, spacing: Space.sm) {
                    Text("mail here is usually about")
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                    // As many as apply. No address is one thing — this one
                    // carries coursework and fees and the occasional recruiter,
                    // and being made to pick the closest single track is how
                    // mail ends up somewhere it never belonged.
                    TagPicker(
                        options: store.tracks.map(\.id),
                        title: { store.trackLabel($0) },
                        selection: Binding(
                            get: { Set(account.tracks) },
                            set: { setAccount(account, tracks: Array($0)) }
                        )
                    )
                    Text("a leaning, not a rule — a bill here is still money.")
                        .font(BookType.meta(10))
                        .foregroundStyle(book.inkSub)
                }
            }

            // The sign-in account cannot be unlinked — it owns the calendar and
            // the session. Pausing it is the way to stop it being read.
            if !account.isPrimary {
                Button("Unlink this mailbox") { unlink(account) }
                    .font(BookType.meta(11))
                    .foregroundStyle(book.inkSub)
            }
        }
        .padding(.leading, Space.xl)
    }

    /// The address, plus anything wrong with it. Deliberately one quiet line:
    /// "signed in" on its own row was a second thing competing with the name.
    private func mailboxCaption(_ account: MailAccount) -> String {
        var parts = [account.email]
        if !account.connected { parts.append("needs reconnecting") }
        else if !account.active { parts.append("paused") }
        else if account.isPrimary { parts.append("signed in") }
        return parts.joined(separator: " · ")
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

    private func loadAccounts() async {
        guard store.isLive else { return }
        accounts = (try? await APIClient.shared.accounts()) ?? accounts
    }

    /// Connect another mailbox.
    ///
    /// The URL is asked for over the authenticated API rather than built here,
    /// so this app's access token never travels in a browser redirect. The
    /// callback carries no tokens at all — the session already exists, and
    /// minting a second one for a mailbox link would be a way to turn a link
    /// into a sign-in.
    private func linkAnother() {
        linking = true
        Task {
            defer { linking = false }
            do {
                let url = try await APIClient.shared.accountLinkURL()
                _ = try await webAuth.authenticate(
                    using: url, callbackURLScheme: "askcal",
                    preferredBrowserSession: .shared
                )
                await loadAccounts()
                // A new mailbox has mail in it already; pull before the user
                // goes looking for it.
                await store.refreshAll()
            } catch {
                // A cancelled consent screen throws too, and that is not a
                // failure worth putting on screen.
                if !(error is ASWebAuthenticationSessionError) {
                    loadError = (error as? LocalizedError)?.errorDescription
                        ?? "couldn't connect that mailbox."
                }
            }
        }
    }

    private func setAccount(
        _ account: MailAccount, label: String? = nil, active: Bool? = nil,
        tracks: [String]? = nil
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let previous = accounts[index]
        if let label { accounts[index].label = label.isEmpty ? nil : label }
        if let active { accounts[index].active = active }
        if let tracks { accounts[index].tracks = tracks }

        Task {
            do {
                let saved = try await APIClient.shared.updateAccount(
                    account.id, label: label, active: active, tracks: tracks
                )
                if let i = accounts.firstIndex(where: { $0.id == saved.id }) {
                    accounts[i] = saved
                }
            } catch {
                if let i = accounts.firstIndex(where: { $0.id == previous.id }) {
                    accounts[i] = previous
                }
                loadError = (error as? LocalizedError)?.errorDescription
                    ?? "couldn't save that."
            }
        }
    }

    private func unlink(_ account: MailAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let removed = accounts.remove(at: index)
        Task {
            do {
                try await APIClient.shared.unlinkAccount(removed.id)
                // Its mail is gone server-side; its tasks are not.
                await store.refreshAll()
            } catch {
                accounts.insert(removed, at: min(index, accounts.count))
                loadError = (error as? LocalizedError)?.errorDescription
                    ?? "couldn't unlink that."
            }
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
