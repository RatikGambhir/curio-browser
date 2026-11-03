import Foundation

/// A page that was shared with a message, kept for display.
nonisolated struct ContextRef: Codable, Equatable, Sendable {
    var title: String
    var url: String
    var faviconURL: String?

    private enum CodingKeys: String, CodingKey { case title, url, faviconURL = "favicon_url" }
}
