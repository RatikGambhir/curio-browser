import Foundation

/// Who wrote a chat message.
nonisolated enum Role: String, Codable, Sendable {
    case user
    case assistant
}
