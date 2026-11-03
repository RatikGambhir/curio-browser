import Foundation

/// Bookmarks, newest first.
final class BookmarkStore {
    private let file = JSONFile<[Bookmark]>("bookmarks.json")
    private var bookmarks: [Bookmark]

    init() {
        bookmarks = file.load() ?? []
    }

    func isBookmarked(_ url: String) -> Bool { bookmarks.contains { $0.url == url } }

    func add(url: String, title: String) {
        bookmarks.removeAll { $0.url == url }
        bookmarks.insert(Bookmark(url: url, title: title, createdAt: .now), at: 0)
        file.save(bookmarks)
    }

    func remove(url: String) {
        bookmarks.removeAll { $0.url == url }
        file.save(bookmarks)
    }

    /// Bookmarks whose title or URL contains `query`.
    func search(_ query: String, limit: Int) -> [Bookmark] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(bookmarks.filter {
            query.isEmpty || $0.url.localizedStandardContains(query) || $0.title.localizedStandardContains(query)
        }.prefix(limit))
    }
}
