import Foundation

/// Everything needed to call a provider.
nonisolated struct ProviderConfig: Sendable, CustomDebugStringConvertible {
    var kind: AIProviderKind
    var model: String
    var baseURL: String
    var apiKey: String?

    /// Whether a request can be attempted (a key is present when required).
    var isReady: Bool {
        !kind.requiresAPIKey || !(apiKey ?? "").isEmpty
    }

    /// Never prints the key.
    var debugDescription: String {
        "ProviderConfig(kind: \(kind), model: \(model), baseURL: \(baseURL), apiKey: \(apiKey == nil ? "nil" : "<redacted>"))"
    }
}

extension ProviderConfig {
    /// The active provider from settings and the Keychain.
    init(settings: AISettings, keychain: KeychainStore) {
        let kind = settings.provider
        self.init(kind: kind, model: settings.model(for: kind), baseURL: settings.baseURL(for: kind), apiKey: keychain.apiKey(for: kind))
    }
}
