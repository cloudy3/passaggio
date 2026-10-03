import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A JSON schema the model's reply must match.
public struct StructuredOutput: Sendable {
    public var name: String
    public var schema: JSONValue

    public init(name: String, schema: JSONValue) {
        self.name = name
        self.schema = schema
    }
}

/// The one thing Passaggio needs from a language model: a JSON reply to a system
/// prompt plus user content, constrained to a schema.
public protocol LLMProvider: Sendable {
    var displayName: String { get }
    func generateJSON(system: String, user: String, output: StructuredOutput) async throws -> Data
}

public enum LLMProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case openAI
    case anthropic

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    /// Defaults checked against provider docs in October 2026. Editable in Settings.
    public var defaultModel: String {
        switch self {
        case .openAI: "gpt-6.1-sol"
        case .anthropic: "claude-opus-5"
        }
    }
}

// MARK: - OpenAI (Responses API)

public struct OpenAIProvider: LLMProvider {
    public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    public var apiKey: String
    public var model: String
    public var http: any HTTPClient

    public init(apiKey: String, model: String, http: any HTTPClient) {
        self.apiKey = apiKey
        self.model = model
        self.http = http
    }

    public var displayName: String { "OpenAI \(model)" }

    public func makeRequest(system: String, user: String, output: StructuredOutput) throws -> URLRequest {
        let body: JSONValue = [
            "model": .string(model),
            "instructions": .string(system),
            "input": .string(user),
            "store": false,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": .string(output.name),
                    "schema": output.schema,
                    "strict": true,
                ],
            ],
        ]
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try body.encoded()
        return request
    }

    public func generateJSON(system: String, user: String, output: StructuredOutput) async throws -> Data {
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey(provider: "OpenAI") }
        let data = try await http.sendChecked(try makeRequest(system: system, user: user, output: output))
        return try Self.extractJSON(from: data)
    }

    static func extractJSON(from data: Data) throws -> Data {
        let response = try JSONDecoder().decode(JSONValue.self, from: data)
        if response["status"]?.stringValue == "incomplete" {
            let reason = response["incomplete_details"]?["reason"]?.stringValue
            throw reason == "content_filter" ? APIError.refused("Content filter.") : APIError.truncated
        }
        for item in response["output"]?.arrayValue ?? [] where item["type"]?.stringValue == "message" {
            for part in item["content"]?.arrayValue ?? [] {
                switch part["type"]?.stringValue {
                case "output_text":
                    if let text = part["text"]?.stringValue { return Data(text.utf8) }
                case "refusal":
                    throw APIError.refused(part["refusal"]?.stringValue ?? "")
                default:
                    continue
                }
            }
        }
        throw APIError.emptyOutput
    }
}

// MARK: - Anthropic (Messages API)

public struct AnthropicProvider: LLMProvider {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    public var apiKey: String
    public var model: String
    public var http: any HTTPClient

    public init(apiKey: String, model: String, http: any HTTPClient) {
        self.apiKey = apiKey
        self.model = model
        self.http = http
    }

    public var displayName: String { "Anthropic \(model)" }

    /// Opus 5 and Fable models can decline via safety classifiers; `fallbacks: "default"`
    /// has the server retry on a recommended model instead of returning the refusal.
    var usesServerFallbacks: Bool {
        model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable") || model.hasPrefix("claude-mythos")
    }

    public func makeRequest(system: String, user: String, output: StructuredOutput) throws -> URLRequest {
        var body: [String: JSONValue] = [
            "model": .string(model),
            // Non-streaming, so kept well under the SDK-recommended ceiling for a single request.
            "max_tokens": 16000,
            "system": .string(system),
            "messages": [["role": "user", "content": .string(user)]],
            "output_config": [
                "format": ["type": "json_schema", "schema": output.schema],
            ],
        ]
        if usesServerFallbacks {
            body["fallbacks"] = "default"
        }

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if usesServerFallbacks {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONValue.object(body).encoded()
        return request
    }

    public func generateJSON(system: String, user: String, output: StructuredOutput) async throws -> Data {
        guard !apiKey.isEmpty else { throw APIError.missingAPIKey(provider: "Anthropic") }
        let data = try await http.sendChecked(try makeRequest(system: system, user: user, output: output))
        return try Self.extractJSON(from: data)
    }

    static func extractJSON(from data: Data) throws -> Data {
        let response = try JSONDecoder().decode(JSONValue.self, from: data)
        switch response["stop_reason"]?.stringValue {
        case "refusal":
            let explanation = response["stop_details"]?["explanation"]?.stringValue ?? ""
            throw APIError.refused(explanation)
        case "max_tokens":
            throw APIError.truncated
        default:
            break
        }
        // Thinking blocks precede the answer; the JSON is in the text block(s).
        let text = (response["content"]?.arrayValue ?? [])
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
        guard !text.isEmpty else { throw APIError.emptyOutput }
        return Data(text.utf8)
    }
}
