import SwiftUI

/// The sidebar content itself -- MainView handles the slide-in/out
/// animation and dimmed-background overlay around this.
struct SidebarView: View {
    let personas: [Persona]
    @Binding var selectedPersona: Persona?
    var onSelectPersona: () -> Void

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
                    .foregroundStyle(Brand.textPrimary)
            }
            .padding()

            Button {
                selectedPersona = nil
                onSelectPersona()
            } label: {
                Label("New chat", systemImage: "plus.bubble")
                    .foregroundStyle(Brand.accent)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)

            Text("PERSONAS")
                .font(.caption)
                .foregroundStyle(Brand.textMuted)
                .padding(.horizontal)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(personas) { persona in
                        Button {
                            selectedPersona = persona
                            onSelectPersona()
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: persona.systemImage)
                                    .foregroundStyle(Brand.accent)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(persona.displayName)
                                            .foregroundStyle(Brand.textPrimary)
                                        if persona.isDefault {
                                            Text("Default")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(Brand.accent)
                                        }
                                    }
                                    if let model = persona.baseModelLabel {
                                        Text(model)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(Brand.textMuted)
                                    } else if let error = persona.error {
                                        Text(error)
                                            .font(.caption2)
                                            .foregroundStyle(.red.opacity(0.9))
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(
                                selectedPersona?.id == persona.id
                                    ? Brand.active
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }

                    if personas.isEmpty {
                        Text("No personas found.")
                            .font(.footnote)
                            .foregroundStyle(Brand.textMuted)
                            .padding()
                    }
                }
            }

            Spacer()
            Divider().overlay(Color.white.opacity(0.08))

            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(Brand.textMuted)
                    .padding()
            }
            .buttonStyle(.plain)
        }
        .frame(maxHeight: .infinity)
        .background(Brand.sidebar)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
