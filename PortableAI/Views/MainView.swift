import SwiftUI

/// The app's actual root screen once paired: chat is the primary
/// surface, matching how ChatGPT/Claude's iOS apps work, rather than a
/// persona-picker list you have to navigate away from. The sidebar
/// slides in from the left over a dimmed background -- SwiftUI has no
/// built-in drawer component, so this is a hand-rolled ZStack + offset
/// animation, the standard way to build one.
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var isSidebarOpen = false
    @State private var personas: [Persona] = []
    @State private var selectedPersona: Persona?
    @State private var loadError: String?

    private let sidebarWidth: CGFloat = 280

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                Group {
                    if let selectedPersona {
                        ChatView(persona: selectedPersona)
                            .id(selectedPersona.id) // fresh chat state per persona switch
                    } else if let loadError {
                        ContentUnavailableView(
                            "Couldn't reach the server",
                            systemImage: "wifi.slash",
                            description: Text(loadError)
                        )
                    } else {
                        ContentUnavailableView(
                            "Pick a persona",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Open the menu and choose who to chat with.")
                        )
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { isSidebarOpen.toggle() }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(Brand.accent)
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(selectedPersona?.displayName ?? "PortableAI")
                                .font(.headline)
                            if let model = selectedPersona?.baseModelLabel {
                                Text(model)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .disabled(isSidebarOpen)
            .overlay(
                Color.black.opacity(isSidebarOpen ? 0.3 : 0)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) { isSidebarOpen = false }
                    }
                    .allowsHitTesting(isSidebarOpen)
            )

            SidebarView(
                personas: personas,
                selectedPersona: $selectedPersona,
                onSelectPersona: {
                    withAnimation(.easeInOut(duration: 0.25)) { isSidebarOpen = false }
                }
            )
            .frame(width: sidebarWidth)
            .offset(x: isSidebarOpen ? 0 : -sidebarWidth)
        }
        .tint(Brand.accent)
        .task {
            await loadPersonas()
            // Contract: treat `is_default` as the sidebar default landing persona.
            if selectedPersona == nil {
                selectedPersona = personas.first(where: \.isDefault) ?? personas.first
            }
        }
    }

    private func loadPersonas() async {
        do {
            personas = try await appState.client.fetchPersonas()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
