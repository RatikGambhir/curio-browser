import Foundation

/// One page in history, aggregated across visits.
struct HistoryEntry: Equatable, Hashable {
    var url: String
    var title: String
    var visitCount: Int
    var lastVisit: Timestamp
}
