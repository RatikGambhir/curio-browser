import Foundation

/// A global favorite: a tab shown in every space that keeps its own page
/// state and remembers its saved address.
nonisolated struct Favorite: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var tab: Tab

    init(id: UUID = UUID(), tab: Tab) {
        self.id = id
        self.tab = tab
    }

    init(url: String, title: String) {
        var tab = Tab(url: url)
        tab.title = title
        tab.homeURL = url
        self.init(tab: tab)
    }
}
