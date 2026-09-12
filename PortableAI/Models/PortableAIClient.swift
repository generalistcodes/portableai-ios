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

struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    let role: String
    let content: String

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
    var errorDescription: String? { message }
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
            throw APIError(message: serverMessage ?? "Server returned \(http.statusCode)")
        }
        return data
    }

    // MARK: Pairing (no token needed yet -- this IS how we get one)

    static func claimPairing(baseURL: String, pin: String, deviceName: String) async throws -> String {
        let client = PortableAIClient(baseURL: baseURL, deviceToken: nil)
        let data = try await client.request(
            path: "/api/pairing/claim",
            method: "POST",
            body: ["pin": pin, "device_name": deviceName]
        )
        struct ClaimResponse: Decodable { let device_token: String }
        return try JSONDecoder().decode(ClaimResponse.self, from: data).device_token
    }

    // MARK: Personas

    func fetchPersonas() async throws -> [Persona] {
        let data = try await request(path: "/api/personas")
        return try JSONDecoder().decode([Persona].self, from: data)
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

    /// Sends a chat turn. Pass `modelOverride` to set `/api/chat`'s
    /// `model_override`; omit/nil uses the persona Modelfile `FROM`.
    func sendChat(
        persona: String,
        message: String,
        conversationId: String?,
        modelOverride: String? = nil
    ) async throws -> ChatResponse {
        var body: [String: Any] = ["persona": persona, "message": message]
        if let conversationId { body["conversation_id"] = conversationId }
        if let modelOverride { body["model_override"] = modelOverride }
        let data = try await request(path: "/api/chat", method: "POST", body: body)
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    /// Raw JSON bytes for a conversation, straight from the server's
    /// export endpoint -- used both for on-screen history and for
    /// pinning (PinnedChatsStore saves this exact data to disk).
    func fetchConversationExport(conversationId: String) async throws -> Data {
        try await request(path: "/api/conversations/\(conversationId)/export")
    }
}
