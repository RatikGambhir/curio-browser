import Foundation

/// Assistant preferences.
nonisolated struct AISettings: Codable, Equatable, Sendable {
    var provider: AIProviderKind = .anthropic
    var providers: [String: ProviderSettings] = [:]
    /// Attach the current tab as context when starting a message.
    var autoAttachCurrentTab = true
    /// Upper bound on page text sent per request, in characters.
    var maxContextChars = 60_000
    /// Language used by "Translate selection".
    var translateTo = "English"

    private enum CodingKeys: String, CodingKey {
        case provider, providers, autoAttachCurrentTab = "auto_attach_current_tab"
        case maxContextChars = "max_context_chars", translateTo = "translate_to"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AISettings()
        provider = (try? c.decodeIfPresent(AIProviderKind.self, forKey: .provider)) ?? d.provider
        providers = (try? c.decodeIfPresent([String: ProviderSettings].self, forKey: .providers)) ?? [:]
        autoAttachCurrentTab = try c.decodeIfPresent(Bool.self, forKey: .autoAttachCurrentTab) ?? d.autoAttachCurrentTab
        maxContextChars = try c.decodeIfPresent(Int.self, forKey: .maxContextChars) ?? d.maxContextChars
        translateTo = try c.decodeIfPresent(String.self, forKey: .translateTo) ?? d.translateTo
    }

    func settings(for provider: AIProviderKind) -> ProviderSettings {
        providers[provider.rawValue] ?? ProviderSettings()
    }

    mutating func update(_ provider: AIProviderKind, _ change: (inout ProviderSettings) -> Void) {
        var entry = settings(for: provider)
        change(&entry)
        providers[provider.rawValue] = entry
    }

    /// The effective model for `provider`.
    func model(for provider: AIProviderKind) -> String {
        let model = settings(for: provider).model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? provider.defaultModel : model
    }

    /// The effective base URL without a trailing slash. Only
    /// OpenAI-compatible servers take a custom address.
    func baseURL(for provider: AIProviderKind) -> String {
        var url = provider.defaultBaseURL
        if provider == .openAICompatible {
            let custom = settings(for: provider).baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { url = custom }
        }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
