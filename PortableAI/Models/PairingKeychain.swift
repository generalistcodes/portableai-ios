import Foundation
import Security

/// Stable identity for a PortableAI server (TXT hostname / display name,
/// or the host from a manually entered URL). Case-insensitive.
typealias ServerID = String

/// One remembered pairing credential, stored in the Keychain registry.
struct PairedServerCredential: Codable, Identifiable, Hashable {
    var id: String { serverID }
    let serverID: ServerID
    let token: String
    var baseURL: String
    var displayName: String
    let pairedAt: Date
}

/// Multi-server Keychain storage. Each PortableAI instance is keyed by
/// `serverID` so switching laptops never requires re-entering a PIN.
enum PairingKeychain {
    private static let service = "app.portableai.pairing"
    private static let registryAccount = "pairedServers.v2"
    private static let activeServerAccount = "activeServerID"

    // Legacy single-credential accounts (migrated once into the registry).
    private static let legacyTokenAccount = "deviceToken"
    private static let legacyURLAccount = "serverBaseURL"

    // MARK: - Public API

    static func saveCredential(
        for serverID: ServerID,
        token: String,
        baseURL: String,
        displayName: String? = nil
    ) {
        let id = normalizeID(serverID)
        guard !id.isEmpty else { return }

        var registry = loadRegistry()
        let name = (displayName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? registry[id]?.displayName ?? id

        registry[id] = PairedServerCredential(
            serverID: id,
            token: token,
            baseURL: normalizeBaseURL(baseURL),
            displayName: name,
            pairedAt: registry[id]?.pairedAt ?? Date()
        )
        saveRegistry(registry)
        setActiveServerID(id)
    }

    static func loadCredential(for serverID: ServerID) -> PairedServerCredential? {
        let id = normalizeID(serverID)
        return loadRegistry()[id]
    }

    static func listPairedServers() -> [PairedServerCredential] {
        migrateLegacyIfNeeded()
        return loadRegistry().values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func removeCredential(for serverID: ServerID) {
        let id = normalizeID(serverID)
        var registry = loadRegistry()
        registry.removeValue(forKey: id)
        saveRegistry(registry)

        if activeServerID() == id {
            if let next = registry.keys.sorted().first {
                setActiveServerID(next)
            } else {
                delete(account: activeServerAccount)
            }
        }
    }

    static func clear() {
        delete(account: registryAccount)
        delete(account: activeServerAccount)
        delete(account: legacyTokenAccount)
        delete(account: legacyURLAccount)
    }

    static func activeServerID() -> ServerID? {
        migrateLegacyIfNeeded()
        if let id = get(account: activeServerAccount), !id.isEmpty {
            return id
        }
        return listPairedServers().first?.serverID
    }

    static func setActiveServerID(_ serverID: ServerID?) {
        guard let serverID else {
            delete(account: activeServerAccount)
            return
        }
        set(account: activeServerAccount, value: normalizeID(serverID))
    }

    static func loadActiveCredential() -> PairedServerCredential? {
        migrateLegacyIfNeeded()
        guard let id = activeServerID() else { return nil }
        return loadCredential(for: id)
    }

    /// Match a discovered/manual server against stored credentials.
    static func findCredential(
        serverID: ServerID? = nil,
        displayName: String? = nil,
        baseURL: String? = nil
    ) -> PairedServerCredential? {
        let servers = listPairedServers()
        if let serverID, let match = loadCredential(for: serverID) {
            return match
        }
        if let displayName {
            let needle = normalizeID(displayName)
            if let match = servers.first(where: { normalizeID($0.displayName) == needle || $0.serverID == needle }) {
                return match
            }
        }
        if let baseURL, let host = hostKey(from: baseURL) {
            return servers.first { hostKey(from: $0.baseURL) == host }
        }
        return nil
    }

    static func normalizeID(_ raw: String) -> ServerID {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func serverID(fromBaseURL urlString: String) -> ServerID {
        if let host = hostKey(from: urlString), !host.isEmpty {
            return host
        }
        return normalizeID(urlString)
    }

    // MARK: - Legacy compatibility (single token era)

    /// Old call sites -- write into the multi-server registry using the URL host as ID.
    static func save(token: String, baseURL: String) {
        let id = serverID(fromBaseURL: baseURL)
        saveCredential(for: id, token: token, baseURL: baseURL, displayName: id)
    }

    static func loadToken() -> String? {
        loadActiveCredential()?.token
    }

    static func loadBaseURL() -> String? {
        loadActiveCredential()?.baseURL
    }

    // MARK: - Registry persistence

    private static func migrateLegacyIfNeeded() {
        let existing = loadRegistryRaw()
        if existing != nil { return }

        guard let token = get(account: legacyTokenAccount),
              let url = get(account: legacyURLAccount),
              !token.isEmpty, !url.isEmpty
        else { return }

        let id = serverID(fromBaseURL: url)
        let credential = PairedServerCredential(
            serverID: id,
            token: token,
            baseURL: normalizeBaseURL(url),
            displayName: id,
            pairedAt: Date()
        )
        saveRegistry([id: credential])
        setActiveServerID(id)
        delete(account: legacyTokenAccount)
        delete(account: legacyURLAccount)
    }

    private static func loadRegistry() -> [ServerID: PairedServerCredential] {
        migrateLegacyIfNeeded()
        return loadRegistryRaw() ?? [:]
    }

    private static func loadRegistryRaw() -> [ServerID: PairedServerCredential]? {
        guard let raw = get(account: registryAccount),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([ServerID: PairedServerCredential].self, from: data)
        else { return nil }
        return decoded
    }

    private static func saveRegistry(_ registry: [ServerID: PairedServerCredential]) {
        guard let data = try? JSONEncoder().encode(registry),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        set(account: registryAccount, value: raw)
    }

    private static func normalizeBaseURL(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    private static func hostKey(from urlString: String) -> String? {
        var raw = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") {
            raw = "http://\(raw)"
        }
        guard let components = URLComponents(string: raw),
              let host = components.host?.lowercased(),
              !host.isEmpty
        else { return nil }
        // Strip IPv6 zone ID if it ever leaked in.
        return host.split(separator: "%").first.map(String.init) ?? host
    }

    // MARK: - Keychain primitives

    private static func set(account: String, value: String) {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
