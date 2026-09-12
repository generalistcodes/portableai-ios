import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingForget = false

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
    }
}
