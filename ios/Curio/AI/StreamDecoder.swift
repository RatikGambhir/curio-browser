import Foundation

/// Turns provider SSE events into `StreamEvent`s, tracking state across
/// events.
nonisolated struct StreamDecoder {
    private let kind: AIProviderKind
    private var stop: StopReason?
    private var done = false

    init(kind: AIProviderKind) {
        self.kind = kind
    }

    mutating func handle(_ event: SSEEvent) -> [StreamEvent] {
        switch kind {
        case .anthropic: handleAnthropic(event)
        case .openAI, .openAICompatible: handleOpenAI(event)
        }
    }

    /// The final event when the body ends without an explicit terminator.
    mutating func finish() -> StreamEvent? {
        switch kind {
        case .anthropic:
            defer { stop = nil }
            return stop.map(StreamEvent.done)
        case .openAI, .openAICompatible:
            if done { return nil }
            done = true
            return .done(stop ?? .endTurn)
        }
    }

    private mutating func handleAnthropic(_ event: SSEEvent) -> [StreamEvent] {
        guard let data = ProviderWire.json(event.data) else { return [] }
        let type = (data["type"] as? String) ?? event.event
        switch type {
        case "content_block_start":
            let block = data["content_block"] as? [String: Any] ?? [:]
            switch block["type"] as? String {
            case "thinking", "redacted_thinking": return [.thinking]
            case "text":
                if let text = block["text"] as? String, !text.isEmpty { return [.text(text)] }
                return []
            default: return []
            }
        case "content_block_delta":
            let delta = data["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta": return (delta["text"] as? String).map { [.text($0)] } ?? []
            case "thinking_delta", "signature_delta": return [.thinking]
            default: return []
            }
        case "message_delta":
            if let reason = (data["delta"] as? [String: Any])?["stop_reason"] as? String {
                stop = switch reason {
                case "end_turn", "stop_sequence": .endTurn
                case "max_tokens": .maxTokens
                case "refusal": .refusal
                default: .other(reason)
                }
            }
            return []
        case "message_stop":
            defer { stop = nil }
            return [.done(stop ?? .endTurn)]
        case "error":
            return [.error(ProviderWire.apiError(status: nil, body: data))]
        default:
            return []
        }
    }

    private mutating func handleOpenAI(_ event: SSEEvent) -> [StreamEvent] {
        if done { return [] }
        if event.data.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            done = true
            return [.done(stop ?? .endTurn)]
        }
        guard let data = ProviderWire.json(event.data) else { return [] }
        if data["error"] != nil {
            done = true
            return [.error(ProviderWire.apiError(status: nil, body: data))]
        }
        var out: [StreamEvent] = []
        let choice = (data["choices"] as? [[String: Any]])?.first ?? [:]
        let delta = choice["delta"] as? [String: Any] ?? [:]
        if let text = delta["content"] as? String, !text.isEmpty { out.append(.text(text)) }
        if delta["reasoning_content"] is String || delta["reasoning"] is String { out.append(.thinking) }
        if let reason = choice["finish_reason"] as? String {
            stop = switch reason {
            case "stop": .endTurn
            case "length": .maxTokens
            case "content_filter": .refusal
            default: .other(reason)
            }
        }
        return out
    }
}
