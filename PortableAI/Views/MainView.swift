import SwiftUI

/// The app's actual root screen once paired: chat is the primary
/// surface. The sidebar slides in from the left over a dimmed
/// background (hand-rolled ZStack + offset).
struct MainView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.themeColors) private var theme
    @State private var isSidebarOpen = false
    @State private var personas: [Persona] = []
    @State private var conversations: [ConversationSummary] = []
    @State private var pinned: [ConversationDetail] = []
    @State private var loadError: String?
    @State private var conversationsError: String?

    @State private var selectedPersona: Persona?
    @State private var selectedConversationId: String?
    @State private var selectedPinnedId: String?
    @State private var chatMessages: [ChatMessage] = []
    @State private var chatConversationId: String?
    @State private var isOfflineSnapshot = false
    @State private var chatSessionKey = UUID()
    @State private var isLoadingConversation = false

    private let sidebarWidth: CGFloat = 300

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                Group {
                    if isLoadingConversation {
                        ProgressView("Loading chat…")
                            .tint(theme.accent)
                    } else if let selectedPersona {
                        ChatView(
                            persona: selectedPersona,
                            initialConversationId: chatConversationId,
                            initialMessages: chatMessages,
                            isOfflineSnapshot: isOfflineSnapshot
                        )
                        .id(chatSessionKey)
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
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isSidebarOpen.toggle()
                            }
                            if isSidebarOpen {
                                Task { await refreshSidebarLists() }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(navigationTitle)
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                            if let subtitle = navigationSubtitle {
                                Text(subtitle)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(theme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .toolbarBackground(theme.main, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(appState.theme.preferredColorScheme, for: .navigationBar)
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
                conversations: conversations,
                pinned: pinned,
                conversationsError: conversationsError,
                selectedPersonaId: Binding(
                    get: { selectedPersona?.id },
                    set: { _ in }
                ),
                selectedConversationId: $selectedConversationId,
                selectedPinnedId: $selectedPinnedId,
                onNewChat: { startFreshChat(with: defaultPersona()) },
                onSelectPersona: { startFreshChat(with: $0) },
                onSelectConversation: { summary in
                    Task { await openServerConversation(summary) }
                },
                onSelectPinned: { openPinned($0) },
                onDeleteConversation: { summary in
                    Task { await deleteConversation(summary) }
                },
                onClose: {
                    withAnimation(.easeInOut(duration: 0.25)) { isSidebarOpen = false }
                }
            )
            .frame(width: sidebarWidth)
            .offset(x: isSidebarOpen ? 0 : -sidebarWidth)
        }
        .tint(theme.accent)
        .background(theme.main)
        .onReceive(NotificationCenter.default.publisher(for: .portableAIPinnedChatsDidChange)) { _ in
            refreshPinned()
        }
        .task {
            await appState.refreshTheme()
            await loadPersonas()
            refreshPinned()
            await refreshConversations()
            if selectedPersona == nil {
                startFreshChat(with: defaultPersona())
            }
        }
    }

    private var navigationTitle: String {
        if isOfflineSnapshot {
            return selectedPersona?.displayName ?? "Pinned chat"
        }
        return selectedPersona?.displayName ?? "PortableAI"
    }

    private var navigationSubtitle: String? {
        if isOfflineSnapshot { return "Offline pin" }
        return selectedPersona?.baseModelLabel
    }

    private func defaultPersona() -> Persona? {
        personas.first(where: \.isDefault) ?? personas.first
    }

    private func personaMatching(id: String) -> Persona {
        if let match = personas.first(where: { $0.id == id }) {
            return match
        }
        return Persona(id: id, display_name: id)
    }

    private func startFreshChat(with persona: Persona?) {
        guard let persona else { return }
        selectedPersona = persona
        selectedConversationId = nil
        selectedPinnedId = nil
        chatConversationId = nil
        chatMessages = []
        isOfflineSnapshot = false
        chatSessionKey = UUID()
    }

    private func openServerConversation(_ summary: ConversationSummary) async {
        isLoadingConversation = true
        defer { isLoadingConversation = false }
        do {
            let detail = try await appState.client.fetchConversation(id: summary.id)
            selectedPersona = personaMatching(id: detail.persona)
            selectedConversationId = detail.id
            selectedPinnedId = nil
            chatConversationId = detail.id
            chatMessages = detail.chatMessages
            isOfflineSnapshot = false
            chatSessionKey = UUID()
        } catch {
            conversationsError = error.localizedDescription
        }
    }

    private func openPinned(_ detail: ConversationDetail) {
        selectedPersona = personaMatching(id: detail.persona)
        selectedConversationId = nil
        selectedPinnedId = detail.id
        chatConversationId = detail.id
        chatMessages = detail.chatMessages
        isOfflineSnapshot = true
        chatSessionKey = UUID()
    }

    private func deleteConversation(_ summary: ConversationSummary) async {
        do {
            try await appState.client.deleteConversation(id: summary.id)
            conversations.removeAll { $0.id == summary.id }
            if selectedConversationId == summary.id {
                startFreshChat(with: defaultPersona())
            }
        } catch {
            conversationsError = error.localizedDescription
        }
    }

    private func loadPersonas() async {
        do {
            personas = try await appState.client.fetchPersonas()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func refreshConversations() async {
        do {
            conversations = try await appState.client.fetchConversations()
            conversationsError = nil
        } catch {
            conversationsError = error.localizedDescription
        }
    }

    private func refreshPinned() {
        pinned = PinnedChatsStore.listPinnedSummaries()
    }

    private func refreshSidebarLists() async {
        refreshPinned()
        await refreshConversations()
    }
}
