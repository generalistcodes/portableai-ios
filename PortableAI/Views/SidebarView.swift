import SwiftUI

/// The sidebar content itself -- MainView handles the slide-in/out
/// animation and dimmed-background overlay around this.
struct SidebarView: View {
    let personas: [Persona]
    let conversations: [ConversationSummary]
    let pinned: [ConversationDetail]
    let conversationsError: String?
    @Binding var selectedPersonaId: String?
    @Binding var selectedConversationId: String?
    @Binding var selectedPinnedId: String?

    var onNewChat: () -> Void
    var onSelectPersona: (Persona) -> Void
    var onSelectConversation: (ConversationSummary) -> Void
    var onSelectPinned: (ConversationDetail) -> Void
    var onDeleteConversation: (ConversationSummary) -> Void
    var onClose: () -> Void

    @Environment(\.themeColors) private var theme
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("PortableAI")
                    .font(.title3.bold())
                    .foregroundStyle(theme.textPrimary)
            }
            .padding()

            Button {
                onNewChat()
                onClose()
            } label: {
                Label("New chat", systemImage: "plus.bubble")
                    .foregroundStyle(theme.accent)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                Section {
                    if let conversationsError {
                        Text(conversationsError)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.9))
                            .listRowBackground(Color.clear)
                    }
                    if conversations.isEmpty && conversationsError == nil {
                        Text("No chats yet.")
                            .font(.footnote)
                            .foregroundStyle(theme.textMuted)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(conversations) { conversation in
                        conversationButton(conversation)
                            .listRowBackground(
                                selectedConversationId == conversation.id && selectedPinnedId == nil
                                    ? theme.active
                                    : Color.clear
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Delete", role: .destructive) {
                                    onDeleteConversation(conversation)
                                }
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    onDeleteConversation(conversation)
                                }
                            }
                    }
                } header: {
                    Text("Chats")
                        .foregroundStyle(theme.textMuted)
                }

                if !pinned.isEmpty {
                    Section {
                        Text("Stored on this phone — works offline.")
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                            .listRowBackground(Color.clear)
                        ForEach(pinned, id: \.id) { item in
                            pinnedButton(item)
                                .listRowBackground(
                                    selectedPinnedId == item.id ? theme.active : Color.clear
                                )
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                    } header: {
                        Text("Pinned")
                            .foregroundStyle(theme.textMuted)
                    }
                }

                Section {
                    ForEach(personas) { persona in
                        personaButton(persona)
                            .listRowBackground(
                                selectedPersonaId == persona.id
                                    && selectedConversationId == nil
                                    && selectedPinnedId == nil
                                    ? theme.active
                                    : Color.clear
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    if personas.isEmpty {
                        Text("No personas found.")
                            .font(.footnote)
                            .foregroundStyle(theme.textMuted)
                            .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Personas")
                        .foregroundStyle(theme.textMuted)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 44)

            Divider().overlay(Color.white.opacity(0.08))

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(theme.textMuted)
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity)
        .background(theme.sidebar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func conversationButton(_ conversation: ConversationSummary) -> some View {
        Button {
            onSelectConversation(conversation)
            onClose()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.displayTitle)
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(personaLabel(for: conversation.persona))
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                            .lineLimit(1)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                        Text(RelativeTime.string(fromUnixSeconds: conversation.updated_at))
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pinnedButton(_ item: ConversationDetail) -> some View {
        Button {
            onSelectPinned(item)
            onClose()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pin.fill")
                    .foregroundStyle(theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(personaLabel(for: item.persona))
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                        Text(RelativeTime.string(fromUnixSeconds: item.updated_at))
                            .font(.caption2)
                            .foregroundStyle(theme.textMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func personaButton(_ persona: Persona) -> some View {
        Button {
            onSelectPersona(persona)
            onClose()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: persona.systemImage)
                    .foregroundStyle(theme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(persona.displayName)
                            .foregroundStyle(theme.textPrimary)
                        if persona.isDefault {
                            Text("Default")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                    }
                    if let model = persona.baseModelLabel {
                        Text(model)
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.textMuted)
                    } else if let error = persona.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.9))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func personaLabel(for personaId: String) -> String {
        if let match = personas.first(where: { $0.id == personaId }) {
            return match.displayName
        }
        return personaId
    }
}
