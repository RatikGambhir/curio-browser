import Foundation

/// A row of the flattened sidebar, in display order.
nonisolated enum TabRow: Hashable, Sendable {
    case tab(id: UUID, section: TabSection, group: UUID?)
    case group(id: UUID, section: TabSection)
    /// A split view, shown as one row in place of its tabs.
    case split(id: UUID, section: TabSection, group: UUID?)

    var section: TabSection {
        switch self {
        case .tab(_, let section, _), .group(_, let section), .split(_, let section, _): section
        }
    }
}
