import Foundation

/// Request bodies and error parsing for each provider. Pure, so it is unit
/// tested; the transport lives in `AIClient`.
nonisolated enum ProviderWire {
    /// Anthropic Messages API version sent with every request.
    static let anthropicVersion = "2026-10-21"
    /// Beta header enabling server-side refusal fallbacks.
    static let anthropicFallbackBeta = "server-side-fallback-2026-07-01"
    static let anthropicMaxTokens = 32_000

    /// Drops leading assistant turns and empty messages, and merges
    /// consecutive messages from the same role.
    static func normalize(_ messages: [WireMessage]) -> [WireMessage] {
        var out: [WireMessage] = []
        for message in messages {
            if message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if out.isEmpty && message.role == .assistant { continue }
            if let last = out.last, last.role == message.role {
                out[out.count - 1].content += "\n\n" + message.content
            } else {
                out.append(message)
            }
        }
        return out
    }

    private static func wireMessages(_ request: ChatRequest) -> [[String: Any]] {
        normalize(request.messages).map { ["role": $0.role.rawValue, "content": $0.content] }
    }

    /// Whether server-side refusal fallbacks apply: first-party API requests
    /// to models that support them.
    static func anthropicUsesFallbacks(baseURL: String, model: String) -> Bool {
        var base = baseURL
        while base.hasSuffix("/") { base.removeLast() }
        let supported = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"].contains(model)
        return base == "https://api.anthropic.com" && supported
    }

    static func anthropicBody(_ request: ChatRequest, model: String, fallbacks: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": anthropicMaxTokens,
            "stream": true,
            "messages": wireMessages(request),
        ]
        if !request.system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { body["system"] = request.system }
        if fallbacks { body["fallbacks"] = "default" }
        return body
    }

    static func openAIBody(_ request: ChatRequest, model: String) -> [String: Any] {
        var messages: [[String: Any]] = []
        if !request.system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(["role": "system", "content": request.system])
        }
        messages += wireMessages(request)
        return ["model": model, "stream": true, "messages": messages]
    }

    /// Builds an error from an HTTP status and a body in Anthropic
    /// (`{"type":"error","error":{...}}`) or OpenAI (`{"error":{...}}`) shape.
    static func apiError(status: Int?, body: [String: Any]) -> AIError {
        let error = body["error"] as? [String: Any] ?? [:]
        let kind = (error["type"] as? String) ?? (error["code"] as? String) ?? ""
        let message = (error["message"] as? String) ?? (body["message"] as? String) ?? "The AI provider returned an error"
        if status == 401 || kind == "authentication_error" || kind == "invalid_api_key" { return .unauthorized(message) }
        if status == 429 || kind == "rate_limit_error" || kind == "rate_limit_exceeded" { return .rateLimited(message) }
        if status == 529 || status == 503 || kind == "overloaded_error" { return .overloaded(message) }
        return .api(status: status, kind: kind, message: message)
    }

    /// An error for a non-success response whose body may not be JSON.
    static func httpError(status: Int, body: String) -> AIError {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return apiError(status: status, body: json)
        }
        let snippet = String(body.prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
        return apiError(status: status, body: ["error": ["message": snippet.isEmpty ? "HTTP \(status)" : snippet]])
    }

    static func json(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
