import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isPaired: Bool
    @Published var baseURL: String
    @Published var pairingError: String?
    @Published var isPairing = false
    /// Shared with the web UI via `GET/POST /api/theme`.
    @Published var theme: AppTheme = .dark
    @Published var themeError: String?

    private var deviceToken: String?

    init() {
        let token = PairingKeychain.loadToken()
        let url = PairingKeychain.loadBaseURL()
        self.deviceToken = token
        self.baseURL = url ?? ""
        self.isPaired = token != nil && url != nil
    }

    var client: PortableAIClient {
        PortableAIClient(baseURL: baseURL, deviceToken: deviceToken)
    }

    var colors: ThemeColors { theme.colors }

    func pair(serverURL: String, pin: String, deviceName: String) async {
        isPairing = true
        pairingError = nil
        defer { isPairing = false }
        do {
            let token = try await PortableAIClient.claimPairing(
                baseURL: serverURL,
                pin: pin,
                deviceName: deviceName
            )
            PairingKeychain.save(token: token, baseURL: serverURL)
            self.deviceToken = token
            self.baseURL = serverURL
            self.isPaired = true
            await refreshTheme()
        } catch {
            pairingError = error.localizedDescription
        }
    }

    func forgetPairing() {
        PairingKeychain.clear()
        deviceToken = nil
        baseURL = ""
        isPaired = false
        theme = .dark
        themeError = nil
    }

    func refreshTheme() async {
        guard isPaired else { return }
        do {
            let remote = try await client.fetchTheme()
            theme = AppTheme.parse(remote)
            themeError = nil
        } catch {
            themeError = error.localizedDescription
        }
    }

    func setTheme(_ next: AppTheme) async {
        let previous = theme
        theme = next
        do {
            let saved = try await client.setTheme(next.rawValue)
            theme = AppTheme.parse(saved)
            themeError = nil
        } catch {
            theme = previous
            themeError = error.localizedDescription
        }
    }
}
