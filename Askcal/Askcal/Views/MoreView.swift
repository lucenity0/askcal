//
//  MoreView.swift
//  Askcal
//
//  Settings: account, theme, your name (for the greeting), nudges.
//

import AuthenticationServices
import SwiftUI

struct MoreView: View {
    @Environment(AskcalStore.self) private var store
    @Environment(\.mono) private var mono
    @Environment(\.webAuthenticationSession) private var webAuth
    @AppStorage("themeMode") private var themeRaw = ThemeMode.light.rawValue
    @AppStorage("userName") private var userName = ""
    @AppStorage("morningDigest") private var morningDigest = true
    @AppStorage("eveningNudge") private var eveningNudge = true
    @State private var connectError: String?

    @State private var nameDraft = ""
    @State private var savingName = false
    @State private var nameStatus: SaveStatus = .idle
    @State private var showDeleteConfirm = false

    private enum SaveStatus { case idle, success, failure }

    var body: some View {
        PageScaffold {
            PageHeader(kicker: "Settings", title: "More")
            SectionUnderline()
        } content: {
                accountSection
                Divider().overlay(mono.border)

                // Theme switch
                HStack {
                    Text("Theme")
                        .font(MonoType.item())
                        .foregroundStyle(mono.textPrimary)
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    themeRaw = mode.rawValue
                                }
                            } label: {
                                Text(mode.label)
                                    .font(MonoType.meta(11))
                                    .foregroundStyle(themeRaw == mode.rawValue ? mono.fillText : mono.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(themeRaw == mode.rawValue ? mono.fill : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Capsule().strokeBorder(mono.border, lineWidth: 1))
                }
                Divider().overlay(mono.border)

                // Name — used by the greeting
                nameSection
                Divider().overlay(mono.border)

                // Nudges
                toggleRow("Morning digest", subtitle: "08:30 — your day is ready", isOn: $morningDigest)
                toggleRow("Evening nudge", subtitle: "21:00 — close the day", isOn: $eveningNudge)

                settingRow("Tracks", value: "\(TrackKey.allCases.count) tracks")
                settingRow("Version", value: "0.1.0")

                if !store.isLive {
                    Divider().overlay(mono.border)
                    localDataSection
                }
        }
        .onAppear { if nameDraft.isEmpty { nameDraft = userName } }
        .sheet(isPresented: $showDeleteConfirm) {
            DeleteLocalDataSheet { store.deleteLocalData(); nameDraft = userName }
                .environment(\.mono, mono)
        }
    }

    // MARK: - Name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your name")
                .font(MonoType.item())
                .foregroundStyle(mono.textPrimary)
            HStack(spacing: 10) {
                TextField("what should mornings call you?", text: $nameDraft)
                    .font(MonoType.body(14))
                    .foregroundStyle(mono.textPrimary)
                    .onChange(of: nameDraft) { nameStatus = .idle }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(mono.surface)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(mono.border, lineWidth: 1))
                    )
                Button {
                    saveName()
                } label: {
                    if savingName {
                        ProgressView().tint(mono.fillText).frame(width: 44)
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
                    .font(MonoType.meta(10)).foregroundStyle(mono.textSecondary)
            case .failure:
                Text("couldn't save — check your connection and try again.")
                    .font(MonoType.meta(10)).foregroundStyle(mono.textSecondary)
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
                .font(MonoType.item())
                .foregroundStyle(mono.textPrimary)
            Text("you're not signed in — tasks and routines live only on this device.")
                .font(MonoType.meta(10))
                .foregroundStyle(mono.textSecondary)
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
                        .font(MonoType.item())
                        .foregroundStyle(mono.textPrimary)
                    Text(store.isLive ? (store.accountEmail ?? "connected")
                                      : "demo data — connect to go live")
                        .font(MonoType.meta(10))
                        .foregroundStyle(mono.textSecondary)
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
                    .font(MonoType.meta(10))
                    .foregroundStyle(mono.textSecondary)
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
                        .font(MonoType.item())
                        .foregroundStyle(mono.textPrimary)
                    Text(subtitle)
                        .font(MonoType.meta(10))
                        .foregroundStyle(mono.textSecondary)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(MonoToggleStyle())
                    .onChange(of: isOn.wrappedValue) {
                        Task { await NotificationManager.refreshSchedules(dayClosed: store.dayClosed) }
                    }
            }
            Divider().overlay(mono.border)
        }
    }

    private func settingRow(_ label: String, value: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(label)
                    .font(MonoType.item())
                    .foregroundStyle(mono.textPrimary)
                Spacer()
                Text(value)
                    .font(MonoType.meta())
                    .foregroundStyle(mono.textSecondary)
            }
            Divider().overlay(mono.border)
        }
    }
}

// MARK: - Delete-local-data confirmation (type DELETE)

private struct DeleteLocalDataSheet: View {
    let onConfirm: () -> Void
    @Environment(\.mono) private var mono
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var armed: Bool { typed == "DELETE" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(kicker: "Irreversible", title: "Delete local data", titleSize: 24)

            Text("This wipes every task, routine and check-off stored on this device. It can't be undone. Type DELETE to confirm.")
                .font(MonoType.body(14))
                .foregroundStyle(mono.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("DELETE", text: $typed)
                .font(MonoType.item())
                .foregroundStyle(mono.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(mono.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(armed ? mono.fill : mono.border, lineWidth: 1))
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
        .presentationBackground(mono.bg)
    }
}
