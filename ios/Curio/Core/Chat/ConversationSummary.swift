import Foundation

/// A conversation in the history list.
nonisolated struct ConversationSummary: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var updatedAt: Timestamp
    var messageCount: Int
}
