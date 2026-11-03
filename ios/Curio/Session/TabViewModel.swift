import Foundation

/// What a sidebar row or strip tab needs to draw one tab.
struct TabViewModel: Equatable {
    var id: UUID
    var title: String
    var favicon: String?
    var active: Bool
    var pinned: Bool
    var loading: Bool
    /// The page is not loaded (asleep or never opened).
    var asleep: Bool
}
