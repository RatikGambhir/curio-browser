import Foundation

/// What is being dragged in the sidebar.
nonisolated enum SidebarDrag: Sendable {
    case tab(UUID)
    case group(UUID, space: UUID)
}
