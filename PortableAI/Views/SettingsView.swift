import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.themeColors) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingForget = false
    @State private var isSavingTheme = false

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

                Section("Server") {
                    LabeledContent("Address", value: appState.baseURL)
                }

                Section {
                    Button("Forget this server", role: .destructive) {
                        confirmingForget = true
                    }
                } footer: {
                    Text("You'll need to pair again with a new PIN from the laptop's Settings.")
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
                await appState.refreshTheme()
            }
            .confirmationDialog(
                "Forget this server?",
                isPresented: $confirmingForget,
                titleVisibility: .visible
            ) {
                Button("Forget", role: .destructive) {
                    appState.forgetPairing()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .preferredColorScheme(appState.theme.preferredColorScheme)
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
