import Foundation

/// A saved chat with the assistant.
nonisolated struct Conversation: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var title = "New Chat"
    var scope: ConversationScope = .none
    var messages: [ChatMessage] = []
    var createdAt: Timestamp = .now
    var updatedAt: Timestamp = .now

    init() {}

    private enum CodingKeys: String, CodingKey { case id, title, scope, messages, createdAt = "created_at", updatedAt = "updated_at" }

    /// Titles the conversation from the first line of its first user message,
    /// truncated to 48 characters.
    mutating func retitleFromFirstMessage() {
        guard let first = messages.first(where: { $0.role == .user }) else { return }
        let line = (first.content.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? "")
            .trimmingCharacters(in: .whitespaces)
        var title = String(line.prefix(48))
        if line.count > 48 { title += "…" }
        if !title.isEmpty { self.title = title }
    }

    var summary: ConversationSummary {
        ConversationSummary(id: id, title: title, updatedAt: updatedAt, messageCount: messages.count)
    }
}
