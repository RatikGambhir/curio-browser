import Foundation

/// A running chat request. Cancelling (or releasing) it stops the network
/// request; text already delivered is kept by the caller.
final class AIStream {
    private var task: Task<Void, Never>?

    /// Starts streaming. `onEvent` runs on the main actor and always ends
    /// with `.done` or `.error` unless the stream is cancelled.
    init(config: ProviderConfig, request: ChatRequest, onEvent: @escaping (StreamEvent) -> Void) {
        task = Task {
            do {
                try await AIClient.run(config, request, send: onEvent)
            } catch let error as AIError {
                AIClient.logFailure(error, provider: config.kind)
                if error != .cancelled && !Task.isCancelled { onEvent(.error(error)) }
            } catch {
                if !Task.isCancelled { onEvent(.error(.network(error.localizedDescription))) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
