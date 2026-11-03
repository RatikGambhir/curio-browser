import Foundation

/// Which AI service Curio talks to.
nonisolated enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openAI = "open_ai"
    /// Any server implementing OpenAI's chat completions API (Ollama,
    /// LM Studio, OpenRouter, vLLM, ...).
    case openAICompatible = "open_ai_compatible"

    var label: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .openAICompatible: "OpenAI-compatible"
        }
    }

    /// The model used when none is chosen.
    var defaultModel: String {
        switch self {
        case .anthropic: "claude-opus-5-5"
        case .openAI: "gpt-5"
        case .openAICompatible: "llama3.1"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openAI: "https://api.openai.com/v1"
        case .openAICompatible: "http://localhost:11434/v1"
        }
    }

    /// Local OpenAI-compatible servers usually need no key.
    var requiresAPIKey: Bool { self != .openAICompatible }

    /// The Keychain account for this provider's key.
    var keychainAccount: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .openAI: "openai-api-key"
        case .openAICompatible: "openai-compatible-api-key"
        }
    }

    /// Models offered in the picker. Any other identifier can be typed.
    var suggestedModels: [String] {
        switch self {
        case .anthropic: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1"]
        case .openAI: ["gpt-5", "gpt-5-mini", "gpt-4.1"]
        case .openAICompatible: ["llama3.1", "qwen2.5", "mistral"]
        }
    }
}
