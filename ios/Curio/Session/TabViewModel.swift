import Foundation

/// What a sidebar row or strip tab needs to draw one tab.
struct TabViewModel: Equatable {
    var id: UUID
    var title: String
    var url: String
    var favicon: String?
    var active: Bool
    var pinned: Bool
    /// Pinned or in a folder: closing unloads the tab instead of removing it.
    var saved: Bool
    var loading: Bool
    /// The page is not loaded (asleep or never opened).
    var asleep: Bool

    /// The close button unloads the page (−) rather than closing the tab (×).
    var unloads: Bool { saved && !asleep }
}
