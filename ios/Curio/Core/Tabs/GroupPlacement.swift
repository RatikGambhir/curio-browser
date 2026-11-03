import Foundation

/// Where a group is moved to.
nonisolated enum GroupPlacement: Equatable, Sendable {
    case sectionStart(TabSection)
    case sectionEnd(TabSection)
    case beforeItem(TabItem)
    case afterItem(TabItem)
}
