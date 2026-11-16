import CoreGraphics

/// The room the page area has for split views, reported by the browser
/// screen whenever its layout changes. Split View is offered when two panes
/// fit side by side; a split is shown only while all of its panes fit in its
/// orientation, otherwise the focused tab is shown alone (the split stays
/// saved and comes back when there is room again).
nonisolated struct SplitRoom: Equatable, Sendable {
    /// The narrowest a side-by-side pane gets.
    static let minPaneWidth: CGFloat = 240
    /// The shortest a stacked pane gets.
    static let minPaneHeight: CGFloat = 180
    /// The gap between panes (and the visible part of each divider).
    static let gap: CGFloat = 8

    /// The device can show split views at all: iPads, and large unfolded
    /// phone displays. Regular iPhones never can.
    var supported: Bool
    /// The page area's size.
    var size: CGSize

    static let none = SplitRoom(supported: false, size: .zero)

    /// Whether a new side-by-side split can be offered in menus, shortcuts
    /// and drop zones.
    var available: Bool { fits(panes: TabSplit.minPanes, orientation: .horizontal) }

    /// Whether `panes` panes fit in `orientation`.
    func fits(panes: Int, orientation: SplitOrientation) -> Bool {
        guard supported, panes >= 1 else { return false }
        let gaps = CGFloat(panes - 1) * Self.gap
        switch orientation {
        case .horizontal:
            return size.width >= CGFloat(panes) * Self.minPaneWidth + gaps && size.height >= Self.minPaneHeight
        case .vertical:
            return size.height >= CGFloat(panes) * Self.minPaneHeight + gaps && size.width >= Self.minPaneWidth
        }
    }

    func fits(_ split: TabSplit) -> Bool { fits(panes: split.tabs.count, orientation: split.orientation) }

    /// Where a point along the split's length falls, as a share of the room
    /// the panes have (the length less its gaps), measured from the middle of
    /// the gap after pane `divider`. `nil` when the split has no room.
    static func dividerFraction(pointer: CGFloat, length: CGFloat, panes: Int, divider: Int) -> Double? {
        let room = length - gap * CGFloat(max(panes - 1, 0))
        guard room > 1, pointer.isFinite else { return nil }
        let before = gap * CGFloat(divider) + gap / 2
        return Double((pointer - before) / room)
    }
}
