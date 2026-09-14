import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isPaired: Bool
    @Published var baseURL: String
    @Published var activeServerID: ServerID?
    @Published var activeDisplayName: String = ""
    @Published var pairedServers: [PairedServerCredential] = []
    @Published var pairingError: String?
    @Published var isPairing = false
    /// Shared with the web UI via `GET/POST /api/theme`.
    @Published var theme: AppTheme = .dark
    @Published var themeError: String?

    private var deviceToken: String?

    init() {
        if let active = PairingKeychain.loadActiveCredential() {
            self.deviceToken = active.token
            self.baseURL = active.baseURL
            self.activeServerID = active.serverID
            self.activeDisplayName = active.displayName
            self.isPaired = true
        } else {
            self.deviceToken = nil
            self.baseURL = ""
            self.activeServerID = nil
            self.activeDisplayName = ""
            self.isPaired = false
        }
        self.pairedServers = PairingKeychain.listPairedServers()
    }

    var client: PortableAIClient {
        PortableAIClient(baseURL: baseURL, deviceToken: deviceToken)
    }

    var colors: ThemeColors { theme.colors }

    func refreshPairedServersList() {
        pairedServers = PairingKeychain.listPairedServers()
    }

    /// True when we already have a stored token for this server identity.
    func isRemembered(
        serverID: ServerID? = nil,
        displayName: String? = nil,
        baseURL: String? = nil
    ) -> Bool {
        PairingKeychain.findCredential(
            serverID: serverID,
            displayName: displayName,
            baseURL: baseURL
        ) != nil
    }

    /// Pair with a PIN and store under `serverID` (hostname / display name preferred).
    func pair(
        serverURL: String,
        pin: String,
        deviceName: String,
        serverID: ServerID? = nil,
        displayName: String? = nil
    ) async {
        isPairing = true
        pairingError = nil
        defer { isPairing = false }
        do {
            let token = try await PortableAIClient.claimPairing(
                baseURL: serverURL,
                pin: pin,
                deviceName: deviceName
            )
            let id = PairingKeychain.normalizeID(
                serverID
                    ?? displayName
                    ?? PairingKeychain.serverID(fromBaseURL: serverURL)
            )
            let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            PairingKeychain.saveCredential(
                for: id,
                token: token,
                baseURL: serverURL,
                displayName: (name?.isEmpty == false) ? name : id
            )
            applyActiveCredential(
                serverID: id,
                token: token,
                baseURL: serverURL,
                displayName: (name?.isEmpty == false) ? name! : id
            )
            await refreshTheme()
        } catch {
            pairingError = error.localizedDescription
        }
    }

    /// Use a stored credential for a discovered/known server — no PIN.
    /// Returns `true` on success. On revoked/unauthorized token, removes the
    /// credential and returns `false` so the caller can fall through to PIN.
    @discardableResult
    func connectWithStoredCredential(
        serverID: ServerID,
        baseURL: String,
        displayName: String
    ) async -> Bool {
        isPairing = true
        pairingError = nil
        defer { isPairing = false }

        guard var credential = PairingKeychain.findCredential(
            serverID: serverID,
            displayName: displayName,
            baseURL: baseURL
        ) else {
            return false
        }

        // Prefer the freshly resolved address (IP may have changed).
        credential.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if !displayName.isEmpty {
            credential.displayName = displayName
        }

        let probe = PortableAIClient(baseURL: credential.baseURL, deviceToken: credential.token)
        do {
            _ = try await probe.fetchTheme()
            PairingKeychain.saveCredential(
                for: credential.serverID,
                token: credential.token,
                baseURL: credential.baseURL,
                displayName: credential.displayName
            )
            applyActiveCredential(
                serverID: credential.serverID,
                token: credential.token,
                baseURL: credential.baseURL,
                displayName: credential.displayName
            )
            await refreshTheme()
            return true
        } catch let error as APIError where error.isUnauthorized {
            PairingKeychain.removeCredential(for: credential.serverID)
            refreshPairedServersList()
            pairingError = "This device was revoked on the server. Enter a new PIN to pair again."
            // If we just invalidated the active session, drop to unpaired.
            if activeServerID == credential.serverID {
                clearActiveSessionKeepingOthers()
            }
            return false
        } catch {
            pairingError = error.localizedDescription
            return false
        }
    }

    /// Switch to an already-paired server from Settings (uses its stored URL).
    func switchToPairedServer(_ credential: PairedServerCredential) async {
        _ = await connectWithStoredCredential(
            serverID: credential.serverID,
            baseURL: credential.baseURL,
            displayName: credential.displayName
        )
    }

    func forgetServer(id: ServerID) {
        let wasActive = activeServerID == PairingKeychain.normalizeID(id)
        PairingKeychain.removeCredential(for: id)
        refreshPairedServersList()

        if wasActive {
            if let next = PairingKeychain.listPairedServers().first {
                applyActiveCredential(
                    serverID: next.serverID,
                    token: next.token,
                    baseURL: next.baseURL,
                    displayName: next.displayName
                )
                Task { await refreshTheme() }
            } else {
                clearActiveSessionKeepingOthers()
            }
        }
    }

    /// Forget every remembered server (legacy "forget" behavior).
    func forgetPairing() {
        PairingKeychain.clear()
        clearActiveSessionKeepingOthers()
        pairedServers = []
    }

    func refreshTheme() async {
        guard isPaired else { return }
        do {
            let remote = try await client.fetchTheme()
            theme = AppTheme.parse(remote)
            themeError = nil
        } catch let error as APIError where error.isUnauthorized {
            // Server revoked this device — drop only the active credential.
            if let id = activeServerID {
                PairingKeychain.removeCredential(for: id)
                refreshPairedServersList()
                clearActiveSessionKeepingOthers()
            }
            themeError = "Device revoked — pair again with a new PIN."
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
        } catch let error as APIError where error.isUnauthorized {
            theme = previous
            if let id = activeServerID {
                PairingKeychain.removeCredential(for: id)
                refreshPairedServersList()
                clearActiveSessionKeepingOthers()
            }
            themeError = "Device revoked — pair again with a new PIN."
        } catch {
            theme = previous
            themeError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func applyActiveCredential(
        serverID: ServerID,
        token: String,
        baseURL: String,
        displayName: String
    ) {
        self.deviceToken = token
        self.baseURL = baseURL
        self.activeServerID = serverID
        self.activeDisplayName = displayName
        self.isPaired = true
        self.pairingError = nil
        refreshPairedServersList()
    }

    private func clearActiveSessionKeepingOthers() {
        deviceToken = nil
        baseURL = ""
        activeServerID = nil
        activeDisplayName = ""
        isPaired = false
        theme = .dark
        themeError = nil
        PairingKeychain.setActiveServerID(nil)
        refreshPairedServersList()
    }
}
