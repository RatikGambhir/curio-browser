import Foundation

/// Where tabs are shown.
nonisolated enum TabLayout: String, Codable, CaseIterable, Sendable {
    /// Arc-style vertical sidebar.
    case vertical
    /// A traditional tab strip above the page.
    case horizontal

    var label: String { rawValue.capitalized }
}
