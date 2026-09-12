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
            .tint(Brand.accent)
        }
    }
}
