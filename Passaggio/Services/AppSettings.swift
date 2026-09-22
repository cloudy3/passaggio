import Foundation
import Observation
import PassaggioCore

/// Non-secret preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var provider: LLMProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    var openAIModel: String {
        didSet { defaults.set(openAIModel, forKey: Keys.openAIModel) }
    }

    var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: Keys.anthropicModel) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = defaults.string(forKey: Keys.provider).flatMap(LLMProviderKind.init(rawValue:)) ?? .openAI
        openAIModel = defaults.string(forKey: Keys.openAIModel) ?? LLMProviderKind.openAI.defaultModel
        anthropicModel = defaults.string(forKey: Keys.anthropicModel) ?? LLMProviderKind.anthropic.defaultModel
    }

    func model(for kind: LLMProviderKind) -> String {
        let value = kind == .openAI ? openAIModel : anthropicModel
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? kind.defaultModel : trimmed
    }

    /// Builds the provider selected in Settings, reading its key from the Keychain.
    func makeLLMProvider(keychain: KeychainStore = KeychainStore()) throws -> any LLMProvider {
        switch provider {
        case .openAI:
            guard let key = keychain.read(.openAI) else { throw APIError.missingAPIKey(provider: "OpenAI") }
            return OpenAIProvider(apiKey: key, model: model(for: .openAI), http: URLSession.shared)
        case .anthropic:
            guard let key = keychain.read(.anthropic) else { throw APIError.missingAPIKey(provider: "Anthropic") }
            return AnthropicProvider(apiKey: key, model: model(for: .anthropic), http: URLSession.shared)
        }
    }

    /// Transcription always uses OpenAI; only the key matters.
    func makeTranscriptionClient(keychain: KeychainStore = KeychainStore()) throws -> OpenAITranscriptionClient {
        guard let key = keychain.read(.openAI) else { throw APIError.missingAPIKey(provider: "OpenAI") }
        return OpenAITranscriptionClient(apiKey: key, http: URLSession.shared)
    }

    private enum Keys {
        static let provider = "llmProvider"
        static let openAIModel = "openAIModel"
        static let anthropicModel = "anthropicModel"
    }
}
