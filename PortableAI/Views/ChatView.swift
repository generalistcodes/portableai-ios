import SwiftUI
import UIKit

struct ChatView: View {
    let persona: Persona
    /// When set, continue this conversation instead of starting fresh.
    let initialConversationId: String?
    let initialMessages: [ChatMessage]
    /// Pinned offline snapshot: show history with zero network; no send.
    let isOfflineSnapshot: Bool

    @EnvironmentObject var appState: AppState
    @Environment(\.themeColors) private var theme
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var conversationId: String?
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var isPinned = false
    @State private var modelOverride: String?
    @State private var installedModels: [InstalledModel] = []
    @State private var lastModelUsed: String?
    @State private var didLoadInitial = false
    @State private var copiedMessageId: UUID?

    init(
        persona: Persona,
        initialConversationId: String? = nil,
        initialMessages: [ChatMessage] = [],
        isOfflineSnapshot: Bool = false
    ) {
        self.persona = persona
        self.initialConversationId = initialConversationId
        self.initialMessages = initialMessages
        self.isOfflineSnapshot = isOfflineSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            if isOfflineSnapshot {
                Text("Offline pin — showing saved copy")
                    .font(.caption)
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(theme.sidebar)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            bubble(for: message)
                                .id(message.id)
                        }
                        if isSending {
                            ProgressView()
                                .tint(theme.accent)
                                .padding(.leading, 8)
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(theme.danger)
                                .padding(.horizontal, 8)
                        }
                        if let lastModelUsed {
                            Text("model_used: \(lastModelUsed)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.textMuted)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding()
                }
                .background(theme.main)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if !isOfflineSnapshot {
                Divider().overlay(theme.textMuted.opacity(0.25))

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message \(persona.displayName)", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(theme.input)
                        .foregroundStyle(theme.textPrimary)
                        .tint(theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .lineLimit(1...4)
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending
                                    ? theme.textMuted
                                    : theme.accent
                            )
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding()
                .background(theme.sidebar)
            }
        }
        .background(theme.main)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if !isOfflineSnapshot {
                        modelMenu
                    }
                    Button {
                        Task { await togglePin() }
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundStyle(isPinned ? theme.accent : theme.textMuted)
                    }
                    .disabled(conversationId == nil || isOfflineSnapshot)
                }
            }
        }
        .onAppear {
            guard !didLoadInitial else { return }
            didLoadInitial = true
            conversationId = initialConversationId
            messages = initialMessages
            if let conversationId {
                isPinned = PinnedChatsStore.isPinned(conversationId: conversationId)
            }
            if !isOfflineSnapshot {
                Task { await loadModels() }
            }
        }
        .onChange(of: conversationId) { _, newValue in
            if let newValue { isPinned = PinnedChatsStore.isPinned(conversationId: newValue) }
        }
    }

    private var modelMenu: some View {
        Menu {
            Button {
                modelOverride = nil
            } label: {
                Label(
                    "Persona default\(modelOverride == nil ? " ✓" : "")",
                    systemImage: "person.fill"
                )
            }
            if installedModels.isEmpty {
                Text("No installed models listed")
            } else {
                ForEach(installedModels) { model in
                    if let name = model.name {
                        Button {
                            modelOverride = name
                        } label: {
                            Text(model.displayLabel + (modelOverride == name ? " ✓" : ""))
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "cpu")
                .foregroundStyle(modelOverride == nil ? theme.textMuted : theme.accent)
        }
        .accessibilityLabel("Model")
    }

    private func loadModels() async {
        do {
            installedModels = try await appState.client.fetchInstalledModels()
        } catch {
            #if DEBUG
            print("[PAI] fetchInstalledModels: \(error.localizedDescription)")
            #endif
        }
    }

    private func togglePin() async {
        guard let conversationId else { return }
        if isPinned {
            PinnedChatsStore.unpin(conversationId: conversationId)
            isPinned = false
            NotificationCenter.default.post(name: .portableAIPinnedChatsDidChange, object: nil)
            return
        }
        do {
            let data = try await appState.client.fetchConversationExport(conversationId: conversationId)
            try PinnedChatsStore.pin(conversationId: conversationId, exportData: data)
            isPinned = true
            NotificationCenter.default.post(name: .portableAIPinnedChatsDidChange, object: nil)
        } catch {
            errorMessage = "Couldn't pin: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func bubble(for message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == "user" { Spacer(minLength: 40) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    // Explicit theme primary — never system `.primary` / `.secondary`
                    .foregroundStyle(theme.textPrimary)
                    .padding(10)
                    .background(message.role == "user" ? theme.userBubble : theme.assistantBubble)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                message.role == "user"
                                    ? theme.accent.opacity(0.35)
                                    : theme.bubbleBorder,
                                lineWidth: 1
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    UIPasteboard.general.string = message.content
                    copiedMessageId = message.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedMessageId == message.id { copiedMessageId = nil }
                    }
                } label: {
                    Label(
                        copiedMessageId == message.id ? "Copied" : "Copy",
                        systemImage: copiedMessageId == message.id ? "checkmark" : "doc.on.doc"
                    )
                    .font(.caption2)
                    .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
            }

            if message.role != "user" { Spacer(minLength: 40) }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isOfflineSnapshot else { return }
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: "user", content: text))

        isSending = true
        Task {
            do {
                let response = try await appState.client.sendChat(
                    persona: persona.id,
                    message: text,
                    conversationId: conversationId,
                    modelOverride: modelOverride
                )
                conversationId = response.conversation_id
                lastModelUsed = response.model_used
                messages.append(ChatMessage(role: "assistant", content: response.reply))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
