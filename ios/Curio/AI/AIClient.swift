import Foundation
import OSLog

/// HTTP transport for streaming chat requests over `URLSession`.
enum AIClient {
    private static let log = Logger(subsystem: Curio.bundleID, category: "ai")

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.httpAdditionalHeaders = ["User-Agent": "Curio/0.1.0 (iOS)"]
        return URLSession(configuration: configuration)
    }()

    /// Runs a request, delivering events through `send` until a terminal
    /// event. Throws `AIError` for failures before or during the stream.
    static func run(_ config: ProviderConfig, _ request: ChatRequest, send: (StreamEvent) -> Void) async throws {
        guard config.isReady else { throw AIError.missingAPIKey(config.kind.label) }
        let urlRequest = try makeRequest(config, request)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw AIError.cancelled
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            var body = Data()
            do {
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= 64 * 1024 { break }
                }
            } catch {}
            throw ProviderWire.httpError(status: status, body: String(decoding: body, as: UTF8.self))
        }

        var parser = SSEParser()
        var decoder = StreamDecoder(kind: config.kind)
        var line = Data()
        // Returns true once a terminal event was delivered.
        func deliver(_ events: [StreamEvent]) -> Bool {
            for event in events {
                send(event)
                switch event {
                case .done, .error: return true
                default: continue
                }
            }
            return false
        }
        // Lines are split by hand: `AsyncBytes.lines` drops the blank lines
        // that end SSE events.
        do {
            for try await byte in bytes {
                try Task.checkCancellation()
                if byte == UInt8(ascii: "\n") {
                    let text = String(decoding: line, as: UTF8.self)
                    line.removeAll(keepingCapacity: true)
                    if let event = parser.feed(text), deliver(decoder.handle(event)) { return }
                } else {
                    line.append(byte)
                }
            }
        } catch is CancellationError {
            throw AIError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw AIError.cancelled
        } catch {
            throw AIError.network(error.localizedDescription)
        }
        if !line.isEmpty, let event = parser.feed(String(decoding: line, as: UTF8.self)), deliver(decoder.handle(event)) {
            return
        }
        if let event = parser.finish(), deliver(decoder.handle(event)) { return }
        guard let final = decoder.finish() else {
            throw AIError.invalidResponse("the response ended before the answer was complete")
        }
        _ = deliver([final])
    }

    private static func makeRequest(_ config: ProviderConfig, _ request: ChatRequest) throws -> URLRequest {
        var base = config.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        let body: [String: Any]
        let path: String
        var headers = ["content-type": "application/json", "accept": "text/event-stream"]
        switch config.kind {
        case .anthropic:
            let fallbacks = ProviderWire.anthropicUsesFallbacks(baseURL: base, model: config.model)
            body = ProviderWire.anthropicBody(request, model: config.model, fallbacks: fallbacks)
            path = "/v1/messages"
            headers["anthropic-version"] = ProviderWire.anthropicVersion
            headers["x-api-key"] = config.apiKey ?? ""
            if fallbacks { headers["anthropic-beta"] = ProviderWire.anthropicFallbackBeta }
        case .openAI, .openAICompatible:
            body = ProviderWire.openAIBody(request, model: config.model)
            path = "/chat/completions"
            if let key = config.apiKey, !key.isEmpty { headers["authorization"] = "Bearer \(key)" }
        }
        guard let url = URL(string: base + path) else { throw AIError.network("invalid base URL \(base)") }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        for (field, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: field) }
        return urlRequest
    }

    /// Sends a tiny request to check that the provider, model and key work.
    static func verify(_ config: ProviderConfig) async throws {
        let request = ChatRequest(system: "", messages: [WireMessage(role: .user, content: "Reply with the single word: ok")])
        var failure: AIError?
        try await run(config, request) { event in
            if case .error(let error) = event { failure = error }
        }
        if let failure { throw failure }
    }

    static func logFailure(_ error: AIError, provider: AIProviderKind) {
        guard error != .cancelled else { return }
        log.warning("AI request to \(provider.label, privacy: .public) failed: \(error.message, privacy: .public)")
    }
}
