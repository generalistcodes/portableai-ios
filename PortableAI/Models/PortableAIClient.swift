import Foundation

/// Matches `GET /api/personas` elements from docs/API_CONTRACT.md
/// (sibling server repo). Parsed personas include `base_model` /
/// `system_preview` / `parameters`; unparseable Modelfiles omit those
/// and set `error` instead.
struct Persona: Decodable, Identifiable, Hashable {
    let id: String
    let display_name: String
    let is_default: Bool
    let icon: String
    let base_model: String?
    let system_preview: String?
    let parameters: [String: PersonaParameter]?
    let error: String?

    init(
        id: String,
        display_name: String,
        is_default: Bool = false,
        icon: String = "message",
        base_model: String? = nil,
        system_preview: String? = nil,
        parameters: [String: PersonaParameter]? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.display_name = display_name
        self.is_default = is_default
        self.icon = icon
        self.base_model = base_model
        self.system_preview = system_preview
        self.parameters = parameters
        self.error = error
    }

    /// Prefer server `display_name`; fall back to `id` if blank.
    var displayName: String {
        let trimmed = display_name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }

    var isDefault: Bool { is_default }

    /// Modelfile `FROM`, when the persona parsed cleanly.
    var baseModelLabel: String? {
        guard let base_model else { return nil }
        let trimmed = base_model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var systemImage: String {
        switch icon.lowercased() {
        case "shield": return "shield"
        case "person": return "person"
        case "lightbulb": return "lightbulb"
        default: return "bubble.left"
        }
    }

    static func == (lhs: Persona, rhs: Persona) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Modelfile `PARAMETER` values are typically numbers; accept string/bool
/// so an unusual Modelfile never breaks decoding.
enum PersonaParameter: Decodable, Equatable {
    case number(Double)
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported persona parameter value"
            )
        }
    }
}

struct ChatResponse: Decodable {
    let reply: String
    let latency_ms: Int
    let model_used: String
    let conversation_id: String
}

/// One line from `POST /api/chat` NDJSON (`application/x-ndjson`).
struct ChatStreamEvent: Decodable {
    let token: String?
    let done: Bool?
    let reply: String?
    let latency_ms: Int?
    let model_used: String?
    let conversation_id: String?
    let error: String?
}

/// Splits an NDJSON buffer the same way the web UI's `readNdjson` does:
/// complete lines are parsed; the unfinished trailing fragment is returned.
enum ChatNDJSON {
    static func drain(_ buffer: inout String) throws -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        let parts = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        buffer = parts.last.map(String.init) ?? ""
        for part in parts.dropLast() {
            let line = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            events.append(try decodeLine(line))
        }
        return events
    }

    static func flushRemainder(_ buffer: inout String) throws -> ChatStreamEvent? {
        let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        guard !line.isEmpty else { return nil }
        return try decodeLine(line)
    }

    static func decodeLine(_ line: String) throws -> ChatStreamEvent {
        guard let data = line.data(using: .utf8) else {
            throw APIError(message: "Invalid UTF-8 in chat stream")
        }
        return try JSONDecoder().decode(ChatStreamEvent.self, from: data)
    }
}

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    let role: String
    var content: String

    enum CodingKeys: String, CodingKey { case role, content }

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// List row from `GET /api/conversations` (no `messages`).
/// `archived` is `0`/`1` per API_CONTRACT.md, not a JSON bool.
struct ConversationSummary: Decodable, Identifiable, Hashable {
    let id: String
    let owner_id: String?
    let persona: String
    let model_used: String?
    let title: String?
    let created_at: Double
    let updated_at: Double
    let archived: Int

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "New chat" : trimmed
    }
}

/// Full conversation from GET one / export (includes `messages`).
struct ConversationDetail: Decodable {
    let id: String
    let owner_id: String?
    let persona: String
    let model_used: String?
    let title: String?
    let created_at: Double
    let updated_at: Double
    let archived: Int
    let messages: [ConversationMessage]

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "New chat" : trimmed
    }

    var chatMessages: [ChatMessage] {
        messages.map { ChatMessage(role: $0.role, content: $0.content) }
    }
}

struct ConversationMessage: Decodable {
    let role: String
    let content: String
    let latency_ms: Int?
    let created_at: Double?
}

/// Element of `GET /api/models` → `models` array.
struct InstalledModel: Decodable, Identifiable, Hashable {
    let name: String?
    let digest: String?
    let size_bytes: Int64?
    let size_human: String?
    let quantization: String?
    let parameter_size: String?
    let modified_at: String?

    var id: String { name ?? digest ?? UUID().uuidString }

    var displayLabel: String {
        guard let name, !name.isEmpty else { return "Unknown model" }
        var parts = [name]
        if let parameter_size, !parameter_size.isEmpty { parts.append(parameter_size) }
        if let quantization, !quantization.isEmpty { parts.append(quantization) }
        return parts.joined(separator: " · ")
    }
}

private struct ModelsListResponse: Decodable {
    let models: [InstalledModel]
    let models_path_hint: String?
    let error: String?
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func string(fromUnixSeconds unix: Double) -> String {
        let date = Date(timeIntervalSince1970: unix)
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct APIError: Error, LocalizedError {
    let message: String
    let statusCode: Int?

    init(message: String, statusCode: Int? = nil) {
        self.message = message
        self.statusCode = statusCode
    }

    var errorDescription: String? { message }

    /// Server rejected the device token (revoked / unknown).
    var isUnauthorized: Bool {
        statusCode == 401 || statusCode == 403
    }
}

/// Thin client for the PortableAI server's REST API. Every request after
/// pairing carries the device token as a Bearer header; the server treats
/// requests from its own machine (the desktop browser) as trusted without
/// one, but this app is never running on that machine, so it always sends it.
final class PortableAIClient {
    private let baseURL: String
    private let deviceToken: String?

    init(baseURL: String, deviceToken: String?) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.deviceToken = deviceToken
    }

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw APIError(message: "Invalid server URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = deviceToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No response from server")
        }
        guard (200...299).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let serverMessage = json?["error"] as? String
            throw APIError(
                message: serverMessage ?? "Server returned \(http.statusCode)",
                statusCode: http.statusCode
            )
        }
        return data
    }

    // MARK: Pairing (no token needed yet -- this IS how we get one)

    /// Claims a device token via `POST /api/pairing/claim`.
    /// - Exactly 6 digits → JSON `pin` (rotating single-use PIN).
    /// - Anything else → JSON `family_password` (persistent; omit `pin`).
    /// QR codes keep encoding `pair_pin` only — never the family password.
    static func claimPairing(baseURL: String, secret: String, deviceName: String) async throws -> String {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError(message: "PIN or password is required")
        }

        var body: [String: Any] = ["device_name": deviceName]
        if isRotatingPIN(trimmed) {
            body["pin"] = trimmed
        } else {
            body["family_password"] = trimmed
        }

        let client = PortableAIClient(baseURL: baseURL, deviceToken: nil)
        let data = try await client.request(
            path: "/api/pairing/claim",
            method: "POST",
            body: body
        )
        struct ClaimResponse: Decodable { let device_token: String }
        return try JSONDecoder().decode(ClaimResponse.self, from: data).device_token
    }

    /// Rotating PIN is always exactly 6 digits (matches QR `pair_pin`).
    static func isRotatingPIN(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy(\.isNumber)
    }

    /// Legacy name — prefer `claimPairing(baseURL:secret:deviceName:)`.
    static func claimPairing(baseURL: String, pin: String, deviceName: String) async throws -> String {
        try await claimPairing(baseURL: baseURL, secret: pin, deviceName: deviceName)
    }

    // MARK: Personas

    func fetchPersonas() async throws -> [Persona] {
        let data = try await request(path: "/api/personas")
        return try JSONDecoder().decode([Persona].self, from: data)
    }

    // MARK: Theme

    /// `GET /api/theme` → `{"theme":"dark"|"light"|"ube"}`
    func fetchTheme() async throws -> String {
        let data = try await request(path: "/api/theme")
        struct ThemeResponse: Decodable { let theme: String }
        return try JSONDecoder().decode(ThemeResponse.self, from: data).theme
    }

    /// `POST /api/theme` with `{"theme":"…"}`.
    func setTheme(_ theme: String) async throws -> String {
        let data = try await request(
            path: "/api/theme",
            method: "POST",
            body: ["theme": theme]
        )
        struct ThemeResponse: Decodable { let theme: String }
        return try JSONDecoder().decode(ThemeResponse.self, from: data).theme
    }

    // MARK: Models

    /// Installed Ollama models from `GET /api/models` (requires-token).
    func fetchInstalledModels() async throws -> [InstalledModel] {
        let data = try await request(path: "/api/models")
        let decoded = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return decoded.models.compactMap { model in
            guard let name = model.name, !name.isEmpty else { return nil }
            return model
        }
    }

    // MARK: Conversations

    /// Active (non-archived) conversations for this device, newest first.
    func fetchConversations() async throws -> [ConversationSummary] {
        let data = try await request(path: "/api/conversations")
        return try JSONDecoder().decode([ConversationSummary].self, from: data)
    }

    func fetchConversation(id: String) async throws -> ConversationDetail {
        let data = try await request(path: "/api/conversations/\(id)")
        return try JSONDecoder().decode(ConversationDetail.self, from: data)
    }

    func deleteConversation(id: String) async throws {
        _ = try await request(path: "/api/conversations/\(id)", method: "DELETE")
    }

    // MARK: Chat

    /// Sends a chat turn over `POST /api/chat`'s NDJSON stream (same shape
    /// as the web UI): zero or more `{"token"}` lines, then a final
    /// `{"done":true,"reply",…}`. `onToken` is called for each delta as it
    /// arrives so the UI can grow the assistant bubble live.
    ///
    /// Pre-stream errors (4xx/5xx plain JSON) throw `APIError`. A mid-stream
    /// `{"error"}` line also throws. Pass `modelOverride` for
    /// `model_override`; omit/nil uses the persona Modelfile `FROM`.
    func sendChat(
        persona: String,
        message: String,
        conversationId: String?,
        modelOverride: String? = nil,
        onToken: (@Sendable (String) -> Void)? = nil
    ) async throws -> ChatResponse {
        var body: [String: Any] = ["persona": persona, "message": message]
        if let conversationId { body["conversation_id"] = conversationId }
        if let modelOverride { body["model_override"] = modelOverride }

        guard let url = URL(string: baseURL + "/api/chat") else {
            throw APIError(message: "Invalid server URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = deviceToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "No response from server")
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        // Non-NDJSON = error (or legacy single JSON) — gather the body first.
        if !contentType.contains("ndjson") {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if !(200...299).contains(http.statusCode) {
                throw APIError(
                    message: (json?["error"] as? String) ?? "Server returned \(http.statusCode)",
                    statusCode: http.statusCode
                )
            }
            // Older servers returned one JSON object — keep working against them.
            return try JSONDecoder().decode(ChatResponse.self, from: data)
        }

        if !(200...299).contains(http.statusCode) {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw APIError(
                message: (json?["error"] as? String) ?? "Server returned \(http.statusCode)",
                statusCode: http.statusCode
            )
        }

        var finalEvent: ChatStreamEvent?
        var streamError: String?

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let event = try ChatNDJSON.decodeLine(trimmed)
            if let err = event.error {
                streamError = err
                break
            }
            if let token = event.token {
                onToken?(token)
            }
            if event.done == true {
                finalEvent = event
            }
        }

        if let streamError {
            throw APIError(message: streamError)
        }
        guard let finalEvent,
              let reply = finalEvent.reply,
              let latency = finalEvent.latency_ms,
              let model = finalEvent.model_used,
              let conversation = finalEvent.conversation_id
        else {
            throw APIError(message: "Lost connection to Ollama mid-request.")
        }

        return ChatResponse(
            reply: reply,
            latency_ms: latency,
            model_used: model,
            conversation_id: conversation
        )
    }

    /// Raw JSON bytes for a conversation, straight from the server's
    /// export endpoint -- used both for on-screen history and for
    /// pinning (PinnedChatsStore saves this exact data to disk).
    func fetchConversationExport(conversationId: String) async throws -> Data {
        try await request(path: "/api/conversations/\(conversationId)/export")
    }
}
