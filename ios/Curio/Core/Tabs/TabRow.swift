import Foundation

/// A row of the flattened sidebar, in display order.
nonisolated enum TabRow: Hashable, Sendable {
    case tab(id: UUID, section: TabSection, group: UUID?)
    case group(id: UUID, section: TabSection)

    var section: TabSection {
        switch self {
        case .tab(_, let section, _), .group(_, let section): section
        }
    }
}
