import Foundation

/// Builds command bar results from the query, open tabs, history and
/// bookmarks, in the desktop's order.
struct CommandResults {
    let mode: CommandMode
    let engine: SearchEngine
    let tabs: [TabSuggestion]
    let history: HistoryStore
    let bookmarks: BookmarkStore

    /// Whether every whitespace-separated term of `query` is in `haystack`.
    static func matchesAll(_ query: String, _ haystack: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { haystack.localizedStandardContains($0) }
    }

    func items(for rawQuery: String) -> [CommandItem] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTab = mode == .newTab
        var items: [CommandItem] = []
        var seen = Set<String>()

        func pushCommands(limit: Int) {
            for command in CurioCommand.palette.filter({ query.isEmpty || Self.matchesAll(query, $0.title) }).prefix(limit) {
                items.append(CommandItem(key: "cmd:\(command.rawValue)", leading: .icon(command.icon), title: command.title,
                                         subtitle: nil, badge: "Command", target: .command(command)))
            }
        }

        if mode == .palette { pushCommands(limit: query.isEmpty ? CurioCommand.palette.count : 6) }

        switch Omnibox.classify(query, engine: engine) {
        case .url(let url):
            seen.insert(url)
            items.append(CommandItem(key: "primary", leading: .icon(.globe), title: Curio.displayHost(url), subtitle: url,
                                     badge: newTab ? "Open" : "Go", target: .navigate(url: url, newTab: newTab)))
        case .search(let q, let url):
            items.append(CommandItem(key: "primary", leading: .icon(.search), title: q, subtitle: "Search \(engine.label)",
                                     badge: "Search", target: .navigate(url: url, newTab: newTab)))
        case nil:
            break
        }

        if !query.isEmpty {
            for tab in tabs.filter({ Self.matchesAll(query, "\($0.title) \($0.url)") }).prefix(5) {
                seen.insert(tab.url)
                let host = Curio.displayHost(tab.url)
                items.append(CommandItem(key: "tab:\(tab.id)", leading: .site(favicon: tab.favicon, label: tab.title),
                                         title: tab.title.isEmpty ? host : tab.title, subtitle: "\(tab.space) · \(host)",
                                         badge: "Switch to Tab", target: .switchTab(tab.id)))
            }
        }

        if !query.isEmpty && (query.contains(" ") || query.hasSuffix("?")) && mode != .editURL {
            items.append(CommandItem(key: "ask", leading: .icon(.sparkles), title: query, subtitle: "Ask Curio",
                                     badge: "Ask", target: .askAI(query)))
        }

        if !query.isEmpty {
            for bookmark in bookmarks.search(query, limit: 4) where seen.insert(bookmark.url).inserted {
                let host = Curio.displayHost(bookmark.url)
                items.append(CommandItem(key: "bm:\(bookmark.url)", leading: .site(favicon: nil, label: host),
                                         title: bookmark.title.isEmpty ? host : bookmark.title, subtitle: bookmark.url,
                                         badge: "Bookmark", target: .navigate(url: bookmark.url, newTab: newTab)))
            }
        }

        let history = query.isEmpty ? self.history.recent(limit: 30) : self.history.search(query, limit: 8)
        for entry in history.filter({ seen.insert($0.url).inserted }).prefix(6) {
            let host = Curio.displayHost(entry.url)
            items.append(CommandItem(key: "hist:\(entry.url)", leading: .site(favicon: nil, label: host),
                                     title: entry.title.isEmpty ? host : entry.title, subtitle: entry.url,
                                     badge: query.isEmpty ? "Recent" : "History", target: .navigate(url: entry.url, newTab: newTab)))
        }

        if mode != .palette && !query.isEmpty { pushCommands(limit: 3) }
        return items
    }
}
