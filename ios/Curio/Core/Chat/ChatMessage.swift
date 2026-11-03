import Foundation

/// One message in a conversation.
nonisolated struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var role: Role
    var content: String
    /// Pages shared with this message.
    var context: [ContextRef] = []
    var createdAt: Timestamp = .now
    /// A failure or note shown under the message.
    var error: String?

    init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    private enum CodingKeys: String, CodingKey { case id, role, content, context, createdAt = "created_at", error }
}
