import Foundation

/// A single recorded visit.
nonisolated struct HistoryVisit: Codable, Equatable, Sendable {
    var url: String
    var title: String
    var visitedAt: Timestamp

    private enum CodingKeys: String, CodingKey { case url, title, visitedAt = "visited_at" }
}
