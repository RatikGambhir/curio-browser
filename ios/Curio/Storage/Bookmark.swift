import Foundation

/// A bookmarked page.
nonisolated struct Bookmark: Codable, Equatable, Sendable {
    var url: String
    var title: String
    var createdAt: Timestamp

    private enum CodingKeys: String, CodingKey { case url, title, createdAt = "created_at" }
}
