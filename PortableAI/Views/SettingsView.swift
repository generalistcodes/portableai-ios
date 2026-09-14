import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.themeColors) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var serverPendingForget: PairedServerCredential?
    @State private var confirmingForgetAll = false
    @State private var isSavingTheme = false
    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: themeBinding) {
                        ForEach(AppTheme.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isSavingTheme)

                    if let themeError = appState.themeError {
                        Text(themeError)
                            .font(.footnote)
                            .foregroundStyle(theme.danger)
                    } else {
                        Text("Synced with the PortableAI server (web UI + other devices).")
                            .font(.footnote)
                            .foregroundStyle(theme.textMuted)
                    }
                }

                Section {
                    if appState.pairedServers.isEmpty {
                        Text("No remembered servers")
                            .foregroundStyle(theme.textMuted)
                    } else {
                        ForEach(appState.pairedServers) { server in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(server.displayName)
                                            .foregroundStyle(theme.textPrimary)
                                            .font(.body.weight(.medium))
                                        if server.serverID == appState.activeServerID {
                                            Text("Active")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(theme.accent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(theme.accent.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Text(server.baseURL)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(theme.textMuted)
                                }
                                Spacer(minLength: 0)
                                if server.serverID != appState.activeServerID {
                                    Button("Use") {
                                        Task { await appState.switchToPairedServer(server) }
                                    }
                                    .disabled(appState.isPairing)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Forget", role: .destructive) {
                                    serverPendingForget = server
                                }
                            }
                            .contextMenu {
                                if server.serverID != appState.activeServerID {
                                    Button("Switch to this server") {
                                        Task { await appState.switchToPairedServer(server) }
                                    }
                                }
                                Button("Forget", role: .destructive) {
                                    serverPendingForget = server
                                }
                            }
                        }
                    }

                    Button {
                        showAddServer = true
                    } label: {
                        Label("Find or pair another server", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Remembered servers")
                } footer: {
                    Text("Paired servers reconnect without a PIN. Forget removes only that laptop’s credential.")
                }

                if !appState.pairedServers.isEmpty {
                    Section {
                        Button("Forget all servers", role: .destructive) {
                            confirmingForgetAll = true
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.main)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.accent)
                }
            }
            .toolbarBackground(theme.sidebar, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task {
                appState.refreshPairedServersList()
                await appState.refreshTheme()
            }
            .confirmationDialog(
                forgetDialogTitle,
                isPresented: Binding(
                    get: { serverPendingForget != nil },
                    set: { if !$0 { serverPendingForget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    if let server = serverPendingForget {
                        appState.forgetServer(id: server.serverID)
                        if !appState.isPaired {
                            dismiss()
                        }
                    }
                    serverPendingForget = nil
                }
                Button("Cancel", role: .cancel) {
                    serverPendingForget = nil
                }
            }
            .confirmationDialog(
                "Forget all servers?",
                isPresented: $confirmingForgetAll,
                titleVisibility: .visible
            ) {
                Button("Forget all", role: .destructive) {
                    appState.forgetPairing()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showAddServer) {
                PairingView()
                    .environmentObject(appState)
                    .environment(\.themeColors, appState.colors)
            }
            .onChange(of: appState.isPaired) { _, paired in
                if paired { showAddServer = false }
            }
            .onChange(of: appState.activeServerID) { _, _ in
                showAddServer = false
            }
        }
        .preferredColorScheme(appState.theme.preferredColorScheme)
    }

    private var forgetDialogTitle: String {
        if let name = serverPendingForget?.displayName {
            return "Forget \(name)?"
        }
        return "Forget this server?"
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { appState.theme },
            set: { next in
                Task {
                    isSavingTheme = true
                    await appState.setTheme(next)
                    isSavingTheme = false
                }
            }
        )
    }
}
