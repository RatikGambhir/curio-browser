import Foundation

/// Browsing history. Visits are kept in memory (newest last) and saved as
/// JSON after changes.
final class HistoryStore {
    /// Oldest visits are dropped beyond this many.
    private static let limit = 20_000

    private let file = JSONFile<[HistoryVisit]>("history.json")
    private var visits: [HistoryVisit]
    private var saveTask: Task<Void, Never>?

    init() {
        visits = file.load() ?? []
    }

    /// Records a visit. A repeat of the most recent visit (a reload or a
    /// restored tab) only refreshes its timestamp.
    func recordVisit(url: String, title: String) {
        if let last = visits.last, last.url == url {
            visits[visits.count - 1].visitedAt = .now
            if !title.isEmpty { visits[visits.count - 1].title = title }
        } else {
            visits.append(HistoryVisit(url: url, title: title, visitedAt: .now))
            if visits.count > Self.limit { visits.removeFirst(visits.count - Self.limit) }
        }
        scheduleSave()
    }

    /// Titles usually arrive after the navigation is recorded.
    func updateTitle(url: String, title: String) {
        guard let index = visits.lastIndex(where: { $0.url == url }) else { return }
        visits[index].title = title
        scheduleSave()
    }

    /// Searches by URL or title, ranking frequent and recent pages first.
    func search(_ query: String, limit: Int) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Double(Timestamp.now)
        let entries = aggregate().filter {
            query.isEmpty || $0.url.localizedStandardContains(query) || $0.title.localizedStandardContains(query)
        }
        func score(_ e: HistoryEntry) -> Double {
            Double(e.visitCount) / (1 + (now - Double(e.lastVisit)) / 86_400_000)
        }
        return Array(entries.sorted { score($0) > score($1) }.prefix(limit))
    }

    /// Most recent pages, newest first, one row per URL.
    func recent(limit: Int) -> [HistoryEntry] {
        Array(aggregate().sorted { $0.lastVisit > $1.lastVisit }.prefix(limit))
    }

    func clear() {
        visits.removeAll()
        scheduleSave()
    }

    private func aggregate() -> [HistoryEntry] {
        var byURL: [String: HistoryEntry] = [:]
        for visit in visits {
            if var entry = byURL[visit.url] {
                entry.visitCount += 1
                if visit.visitedAt >= entry.lastVisit {
                    entry.lastVisit = visit.visitedAt
                    if !visit.title.isEmpty { entry.title = visit.title }
                }
                byURL[visit.url] = entry
            } else {
                byURL[visit.url] = HistoryEntry(url: visit.url, title: visit.title, visitCount: 1, lastVisit: visit.visitedAt)
            }
        }
        return Array(byURL.values)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            file.save(visits)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        file.saveNow(visits)
    }
}
