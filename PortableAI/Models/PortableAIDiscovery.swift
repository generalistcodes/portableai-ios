import Combine
import Foundation
import Network

/// A PortableAI instance found via Bonjour (`_portableai._tcp`).
/// `host` is always a dotted IPv4 address — never IPv6 / zone IDs.
struct DiscoveredPortableAIServer: Identifiable, Hashable {
    /// Stable Bonjour service instance name.
    let id: String
    /// Human-readable label from TXT `hostname` (or related keys), else service name.
    let displayName: String
    /// Dotted IPv4 only (e.g. `192.168.1.42`).
    let host: String
    let port: Int

    /// Stable pairing identity — TXT hostname when present.
    var serverID: ServerID {
        PairingKeychain.normalizeID(displayName)
    }

    var baseURL: String {
        // Never emit zone IDs or IPv6 — host is validated as dotted IPv4 at resolve time.
        precondition(!host.contains("%") && !host.contains(":"), "discovered host must be clean IPv4")
        return "http://\(host):\(port)"
    }
}

/// Browses for `_portableai._tcp` using NWBrowser, then resolves addresses
/// with NetService so we can pick a clean IPv4 (no `%en0` zone IDs).
@MainActor
final class PortableAIDiscovery: ObservableObject {
    static let serviceType = "_portableai._tcp"

    @Published private(set) var servers: [DiscoveredPortableAIServer] = []
    @Published private(set) var isBrowsing = false
    @Published private(set) var isInitialSearch = false

    private var browser: NWBrowser?
    private var pendingResolvers: [String: BonjourIPv4Resolver] = [:]
    private var resolved: [String: DiscoveredPortableAIServer] = [:]
    private var emptyStateTask: Task<Void, Never>?

    func start() {
        stop()
        isBrowsing = true
        isInitialSearch = true

        emptyStateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self.isInitialSearch = false
        }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: parameters
        )

        browser.stateUpdateHandler = { [weak self] state in
            let discovery = self
            Task { @MainActor in
                guard let discovery else { return }
                switch state {
                case .ready:
                    discovery.isBrowsing = true
                case .failed(let error):
                    discovery.isBrowsing = false
                    discovery.isInitialSearch = false
                    NSLog("[PAI-DISCOVERY] browser failed: %@", String(describing: error))
                case .cancelled:
                    discovery.isBrowsing = false
                    discovery.isInitialSearch = false
                default:
                    break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovery = self
            Task { @MainActor in
                discovery?.handle(results: results)
            }
        }

        browser.start(queue: DispatchQueue(label: "app.portableai.discovery", qos: .userInitiated))
        self.browser = browser
        NSLog("[PAI-DISCOVERY] browsing for %@", Self.serviceType)
    }

    func refresh() {
        start()
    }

    func stop() {
        emptyStateTask?.cancel()
        emptyStateTask = nil
        browser?.cancel()
        browser = nil
        for resolver in pendingResolvers.values {
            resolver.cancel()
        }
        pendingResolvers.removeAll()
        resolved.removeAll()
        servers = []
        isBrowsing = false
        isInitialSearch = false
    }

    private func handle(results: Set<NWBrowser.Result>) {
        var liveIDs = Set<String>()
        NSLog("[PAI-DISCOVERY] browse results: %d", results.count)

        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            liveIDs.insert(name)
            let label = Self.displayName(from: result, fallback: name)
            resolveIfNeeded(
                serviceName: name,
                type: type,
                domain: domain.isEmpty ? "local." : domain,
                displayName: label
            )
        }

        let removed = Set(resolved.keys).subtracting(liveIDs)
        for id in removed {
            resolved.removeValue(forKey: id)
            pendingResolvers[id]?.cancel()
            pendingResolvers.removeValue(forKey: id)
        }
        publish()
    }

    private func resolveIfNeeded(
        serviceName: String,
        type: String,
        domain: String,
        displayName: String
    ) {
        if pendingResolvers[serviceName] != nil { return }
        if resolved[serviceName] != nil { return }

        let resolver = BonjourIPv4Resolver(
            name: serviceName,
            type: type.hasSuffix(".") ? type : type + ".",
            domain: domain.hasSuffix(".") ? domain : domain + "."
        )
        pendingResolvers[serviceName] = resolver

        resolver.resolve { [weak self] host, port in
            let discovery = self
            Task { @MainActor in
                guard let discovery else { return }
                discovery.pendingResolvers[serviceName] = nil
                guard let host, let port, Self.isCleanIPv4(host) else {
                    NSLog(
                        "[PAI-DISCOVERY] no usable IPv4 for %@ (host=%@)",
                        serviceName,
                        host ?? "nil"
                    )
                    return
                }
                discovery.resolved[serviceName] = DiscoveredPortableAIServer(
                    id: serviceName,
                    displayName: displayName,
                    host: host,
                    port: port
                )
                discovery.isInitialSearch = false
                discovery.publish()
            }
        }
    }

    private func publish() {
        servers = resolved.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        let summary = servers.map { "\($0.displayName)=\($0.baseURL)" }.joined(separator: ", ")
        NSLog(
            "[PAI-DISCOVERY] servers (%d): %@",
            servers.count,
            summary.isEmpty ? "(none)" : summary
        )
    }

    private static func displayName(from result: NWBrowser.Result, fallback: String) -> String {
        guard case .bonjour(let txt) = result.metadata else {
            return fallback
        }
        // Server advertises TXT `name` (see portableai mdns_broadcast.txt_records).
        for key in ["name", "hostname", "host"] {
            if let value = txtString(txt, key: key), !value.isEmpty {
                return value
            }
        }
        return fallback
    }

    private static func txtString(_ txt: NWTXTRecord, key: String) -> String? {
        guard let value = txt[key], !value.isEmpty else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dotted-quad only; rejects anything with `%` or `:`.
    static func isCleanIPv4(_ host: String) -> Bool {
        if host.contains("%") || host.contains(":") { return false }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let n = Int(part), (0...255).contains(n) else { return false }
            return true
        }
    }
}

// MARK: - NetService IPv4 resolve

/// Resolves a Bonjour service to a routable IPv4 address + port.
/// Prefer NetService over NWConnection here: forcing IPv4 on an NWConnection
/// to a `.service` endpoint often fails silently on iOS.
private final class BonjourIPv4Resolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private var completion: ((String?, Int?) -> Void)?
    private var finished = false

    init(name: String, type: String, domain: String) {
        self.service = NetService(domain: domain, type: type, name: name)
        super.init()
        service.delegate = self
    }

    func resolve(completion: @escaping (String?, Int?) -> Void) {
        self.completion = completion
        service.resolve(withTimeout: 5.0)
    }

    func cancel() {
        finish(host: nil, port: nil)
        service.stop()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let port = sender.port
        guard port > 0, let addresses = sender.addresses else {
            finish(host: nil, port: nil)
            return
        }

        var linkLocal: String?
        for address in addresses {
            guard let ipv4 = Self.ipv4Host(from: address) else { continue }
            if ipv4.hasPrefix("169.254.") {
                linkLocal = linkLocal ?? ipv4
                continue
            }
            finish(host: ipv4, port: port)
            return
        }

        // Last resort: link-local IPv4 (still clean dotted-quad, no zone ID).
        if let linkLocal {
            finish(host: linkLocal, port: port)
            return
        }
        finish(host: nil, port: nil)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        NSLog("[PAI-DISCOVERY] NetService didNotResolve %@: %@", sender.name, String(describing: errorDict))
        finish(host: nil, port: nil)
    }

    private func finish(host: String?, port: Int?) {
        guard !finished else { return }
        finished = true
        service.delegate = nil
        service.stop()
        let done = completion
        completion = nil
        done?(host, port)
    }

    /// Extract IPv4 dotted-quad from a `sockaddr` blob. Ignores IPv6 entirely.
    private static func ipv4Host(from address: Data) -> String? {
        address.withUnsafeBytes { raw -> String? in
            guard let base = raw.bindMemory(to: sockaddr.self).baseAddress else { return nil }
            guard base.pointee.sa_family == AF_INET else { return nil }

            var addr = raw.bindMemory(to: sockaddr_in.self).baseAddress!.pointee
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            let converted = withUnsafePointer(to: &addr.sin_addr) { ptr in
                inet_ntop(AF_INET, ptr, &buffer, socklen_t(INET_ADDRSTRLEN))
            }
            guard converted != nil else { return nil }
            let host = String(cString: buffer)
            guard PortableAIDiscovery.isCleanIPv4(host) else { return nil }
            return host
        }
    }
}
