import Foundation

/// Which collection owns a tab.
nonisolated enum TabOwner: Equatable, Sendable {
    case space(UUID)
    case favorite(UUID)
}
