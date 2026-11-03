import Foundation

/// A tab removed from a strip, with a placement that would put it back.
nonisolated struct RemovedTab: Equatable, Sendable {
    var tab: Tab
    var restoreAt: TabPlacement
}
