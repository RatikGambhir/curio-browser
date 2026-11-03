import Foundation

/// Errors from AI requests. Messages are safe to show and never include keys.
nonisolated enum AIError: Error, Equatable, Sendable {
    case missingAPIKey(String)
    case unauthorized(String)
    case rateLimited(String)
    case overloaded(String)
    case api(status: Int?, kind: String, message: String)
    case network(String)
    case invalidResponse(String)
    case cancelled

    var message: String {
        switch self {
        case .missingAPIKey(let provider): "Add your \(provider) API key in Settings › AI Assistant to start chatting."
        case .unauthorized(let m): "The API key was rejected: \(m)"
        case .rateLimited(let m): "Rate limited by the provider, try again shortly: \(m)"
        case .overloaded(let m): "The provider is overloaded, try again shortly: \(m)"
        case .api(_, _, let m): m
        case .network(let m): "Network error: \(m)"
        case .invalidResponse(let m): "Unexpected response: \(m)"
        case .cancelled: "Cancelled"
        }
    }

    /// Whether retrying the same request may succeed.
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .overloaded, .network: true
        case .api(let status?, _, _): status >= 500
        default: false
        }
    }
}
