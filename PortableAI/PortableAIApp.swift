import SwiftUI

@main
struct PortableAIApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isPaired {
                    MainView()
                } else {
                    PairingView()
                }
            }
            .environmentObject(appState)
            .environment(\.themeColors, appState.colors)
            .tint(appState.colors.accent)
            .preferredColorScheme(appState.theme.preferredColorScheme)
            .task(id: appState.isPaired) {
                if appState.isPaired {
                    await appState.refreshTheme()
                }
            }
        }
    }
}
