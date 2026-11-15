import XCTest
@testable import Curio

/// Split view logic, ported from the desktop's `curio-core`, `curio-tabs`
/// and `curio-spaces` tests with the same names.
final class SplitViewTests: XCTestCase {
    private func strip(_ count: Int) -> (TabStrip, [UUID]) {
        var strip = TabStrip()
        var ids: [UUID] = []
        for index in 0..<count {
            ids.append(strip.insert(Tab(url: "https://site\(index).test"), at: .sectionEnd(.unpinned)))
        }
        return (strip, ids)
    }

    // MARK: - TabSplit (curio-core)

    func testSplitStartsWithEqualUniquePanes() {
        let a = UUID(), b = UUID()
        let split = TabSplit(tabs: [a, b, a])
        XCTAssertEqual(split.tabs, [a, b])
        XCTAssertEqual(split.sizes, [0.5, 0.5])
        XCTAssertTrue(split.isValid)
        let many = TabSplit(tabs: (0..<6).map { _ in UUID() }, orientation: .vertical)
        XCTAssertEqual(many.tabs.count, TabSplit.maxPanes)
        XCTAssertTrue(many.isFull)
    }

    func testSplitResizeKeepsPanesAboveTheMinimum() {
        var split = TabSplit(tabs: [UUID(), UUID()])
        XCTAssertTrue(split.resize(divider: 0, by: 0.2))
        XCTAssertEqual(split.sizes[0], 0.7, accuracy: 1e-9)
        XCTAssertEqual(split.sizes[1], 0.3, accuracy: 1e-9)
        split.resize(divider: 0, by: 5)
        XCTAssertEqual(split.sizes[1], TabSplit.minSize, accuracy: 1e-9)
        XCTAssertFalse(split.resize(divider: 1, by: 0.1), "no divider after the last pane")
        XCTAssertFalse(split.resize(divider: 0, by: .nan))
    }

    func testRemovingAPaneGivesItsRoomToANeighbor() {
        let ids = [UUID(), UUID(), UUID()]
        var split = TabSplit(tabs: ids)
        split.sizes = [0.5, 0.25, 0.25]
        XCTAssertTrue(split.removeTab(ids[1]))
        XCTAssertEqual(split.tabs, [ids[0], ids[2]])
        XCTAssertEqual(split.sizes[0], 0.75, accuracy: 1e-9)
        XCTAssertTrue(split.removeTab(ids[0]))
        XCTAssertFalse(split.isValid)
    }

    func testSplitNormalizeRepairsBadSizes() {
        var split = TabSplit(tabs: [UUID(), UUID()])
        split.sizes = [2, 6]
        split.normalize()
        XCTAssertEqual(split.sizes[0], 0.25, accuracy: 1e-9)
        split.sizes = [.nan]
        split.normalize()
        XCTAssertEqual(split.sizes, [0.5, 0.5])
        var grown = split
        XCTAssertTrue(grown.addTab(UUID(), at: 1))
        XCTAssertEqual(grown.tabs[0], split.tabs[0])
        XCTAssertEqual(grown.tabs[2], split.tabs[1])
    }

    // MARK: - TabStrip (curio-tabs)

    func testCreateSplitGathersTabsNextToTheFirst() throws {
        var (strip, ids) = strip(4)
        let split = try XCTUnwrap(strip.createSplit([ids[0], ids[3]]))
        XCTAssertEqual(strip.orderedTabIDs, [ids[0], ids[3], ids[1], ids[2]])
        XCTAssertEqual(strip.split(of: ids[3])?.id, split)
        // One row for the split, none for its second tab.
        let rows = strip.rows(alwaysShow: nil)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], .split(id: split, section: .unpinned, group: nil))
        // The single-page layout lists every pane as a tab.
        XCTAssertEqual(strip.rows(alwaysShow: nil, showingSplits: false).count, 4)
        XCTAssertNil(strip.createSplit([ids[1]]))
        XCTAssertNil(strip.createSplit([ids[1], UUID()]), "unknown tabs don't count")
    }

    func testASplitMadeInAFolderIsSavedInThatFolder() {
        var (strip, ids) = strip(3)
        let folder = strip.createGroup(name: "Research", color: .ocean, members: [ids[0]])
        strip.createSplit([ids[0], ids[2]])
        XCTAssertEqual(strip.group(folder)?.tabs, [ids[0], ids[2]])
        XCTAssertTrue(strip.isSaved(ids[2]), "the joined tab is kept like the folder's tabs")
        XCTAssertEqual(strip.tab(ids[2])?.homeURL, "https://site2.test")

        // Collapsed, the folder still shows the split of the active tab.
        strip.setGroupCollapsed(folder, true)
        let rows = strip.rows(alwaysShow: ids[2])
        XCTAssertTrue(rows.contains { row in
            if case .split(_, _, let group) = row { return group == folder }
            return false
        })
        XCTAssertEqual(strip.rows(alwaysShow: nil).count, 2, "folder header and the other tab")
    }

    func testMovingOnePaneMovesTheWholeSplit() {
        var (strip, ids) = strip(4)
        strip.createSplit([ids[1], ids[2]])
        XCTAssertTrue(strip.move(ids[2], to: .sectionStart(.unpinned)))
        XCTAssertEqual(strip.orderedTabIDs, [ids[1], ids[2], ids[0], ids[3]])

        // Into a folder, together.
        let folder = strip.createGroup(name: "F", color: .rose, members: [ids[3]])
        XCTAssertTrue(strip.move(ids[1], to: .inGroup(folder, 0)))
        XCTAssertEqual(strip.group(folder)?.tabs, [ids[1], ids[2], ids[3]])
        // Pinning one pane pins the split.
        XCTAssertTrue(strip.pin(ids[2]))
        XCTAssertTrue(strip.isPinned(ids[1]) && strip.isPinned(ids[2]))
        // Moving relative to its own pane does nothing.
        XCTAssertFalse(strip.move(ids[1], to: .afterTab(ids[2])))
    }

    func testTabsNeverLandInsideASplit() {
        var (strip, ids) = strip(3)
        strip.createSplit([ids[0], ids[1]])
        let between = strip.insert(Tab(), at: .afterTab(ids[0]))
        XCTAssertEqual(strip.orderedTabIDs, [ids[0], ids[1], between, ids[2]])
        // New tabs opened from a pane go after the split.
        XCTAssertEqual(strip.placementForNewTab(anchor: ids[0]), .afterTab(ids[1]))
        // A folder dropped onto the second pane lands after the split.
        let folder = strip.createGroup(name: "F", color: .sage, members: [ids[2]])
        strip.moveGroup(folder, to: .beforeItem(.tab(ids[1])))
        XCTAssertEqual(Array(strip.orderedTabIDs.prefix(2)), [ids[0], ids[1]])
    }

    func testClosingAPaneDissolvesASplitOfTwo() throws {
        var (strip, ids) = strip(3)
        let split = try XCTUnwrap(strip.createSplit([ids[0], ids[1], ids[2]]))
        strip.remove(ids[1])
        XCTAssertEqual(strip.split(split)?.tabs, [ids[0], ids[2]])
        strip.remove(ids[2])
        XCTAssertNil(strip.split(split))
        XCTAssertNil(strip.split(of: ids[0]))
    }

    func testRemoveFromSplitPutsTheTabAfterIt() throws {
        var (strip, ids) = strip(4)
        let split = try XCTUnwrap(strip.createSplit([ids[0], ids[1], ids[2]]))
        XCTAssertTrue(strip.removeFromSplit(ids[0]))
        XCTAssertEqual(strip.split(split)?.tabs, [ids[1], ids[2]])
        XCTAssertEqual(strip.orderedTabIDs, [ids[1], ids[2], ids[0], ids[3]])
        XCTAssertTrue(strip.removeFromSplit(ids[2]))
        XCTAssertNil(strip.split(split), "one tab left is no split")
        XCTAssertFalse(strip.removeFromSplit(ids[3]))
    }

    func testATabJoinsOnlyOneSplit() throws {
        var (strip, ids) = strip(4)
        let first = try XCTUnwrap(strip.createSplit([ids[0], ids[1]]))
        let second = try XCTUnwrap(strip.createSplit([ids[1], ids[2]], orientation: .vertical))
        XCTAssertNil(strip.split(first), "the first split lost a pane and dissolved")
        XCTAssertTrue(strip.addToSplit(second, tab: ids[3], at: 1))
        XCTAssertEqual(strip.split(second)?.tabs, [ids[1], ids[3], ids[2]])
        XCTAssertEqual(Array(strip.orderedTabIDs[1..<4]), [ids[1], ids[3], ids[2]])
        XCTAssertFalse(strip.addToSplit(second, tab: ids[3], at: 9), "already a pane")
    }

    func testSplitResizeFlipAndDissolve() throws {
        var (strip, ids) = strip(2)
        let split = try XCTUnwrap(strip.createSplit(ids))
        XCTAssertTrue(strip.resizeSplit(split, divider: 0, by: 0.1))
        XCTAssertTrue(strip.flipSplit(split))
        XCTAssertEqual(strip.split(split)?.orientation, .vertical)
        XCTAssertTrue(strip.equalizeSplit(split))
        XCTAssertEqual(strip.split(split)?.sizes, [0.5, 0.5])
        XCTAssertTrue(strip.dissolveSplit(split))
        XCTAssertEqual(strip.orderedTabIDs, ids, "tabs stay where they were")
    }

    func testSplitsMoveWithTheirFolder() throws {
        var (strip, ids) = strip(3)
        let folder = strip.createGroup(name: "F", color: .amber, members: [ids[0], ids[1]])
        strip.createSplit([ids[0], ids[1]])
        let taken = try XCTUnwrap(strip.takeGroup(folder))
        XCTAssertEqual(taken.splits.count, 1)
        XCTAssertTrue(strip.splits.isEmpty)
        var other = TabStrip()
        other.insertGroup(taken)
        XCTAssertNotNil(other.split(of: ids[1]))
    }

    func testFromPartsRepairsSplits() throws {
        let tabs = (0..<3).map { Tab(url: "https://\($0).test") }
        let ids = tabs.map(\.id)
        let good = TabSplit(tabs: [ids[0], ids[2]])
        let dangling = TabSplit(tabs: [ids[1], UUID()])
        var duplicate = TabSplit(tabs: [ids[0], ids[1]])
        // Sorts after `good`, so `good` keeps ids[0].
        duplicate.id = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        var broken = good
        broken.sizes = [-1, .infinity]
        let strip = TabStrip(tabs: tabs, groups: [], pinned: [], unpinned: ids.map(TabItem.tab), splits: [broken, dangling, duplicate])
        XCTAssertEqual(strip.splits.count, 1)
        XCTAssertEqual(strip.split(good.id)?.sizes, [0.5, 0.5], "unusable sizes reset to equal")
        XCTAssertEqual(strip.orderedTabIDs, [ids[0], ids[2], ids[1]])
        let data = try JSONEncoder().encode(strip)
        let back = try JSONDecoder().decode(TabStrip.self, from: data)
        XCTAssertEqual(back.split(good.id)?.tabs, [ids[0], ids[2]])
        XCTAssertEqual(back, strip)
    }

    func testOlderStripsLoadWithoutSplits() throws {
        let tab = Tab(url: "https://a.test")
        let json = """
        {"tabs":[{"id":"\(tab.id.uuidString)","url":"https://a.test"}],"groups":[],"pinned":[],
         "unpinned":[{"kind":"tab","id":"\(tab.id.uuidString)"}]}
        """
        let strip = try JSONDecoder().decode(TabStrip.self, from: Data(json.utf8))
        XCTAssertEqual(strip.orderedTabIDs, [tab.id])
        XCTAssertTrue(strip.splits.isEmpty)
    }

    func testSavedBlankPanesUseTheirFirstPageAsHome() {
        var (strip, ids) = strip(2)
        strip.createGroup(name: "Reading", color: .ocean, members: [ids[0]])
        let pane = strip.insert(Tab(), at: .afterTab(ids[0]))
        XCTAssertNotNil(strip.createSplit([ids[0], pane]))
        XCTAssertTrue(strip.isSaved(pane))
        XCTAssertNil(strip.tab(pane)?.homeURL)
        strip.setTabURL(pane, "https://first.test")
        strip.setTabURL(pane, "https://second.test")
        XCTAssertEqual(strip.tab(pane)?.homeURL, "https://first.test")
    }

    // MARK: - Fitting the page area (curio-ui)

    func testDividerFractionIgnoresTheGaps() throws {
        // Two panes in 808pt with an 8pt gap: 400pt each. The divider's
        // center (404pt) is halfway.
        let half = try XCTUnwrap(SplitRoom.dividerFraction(pointer: 404, length: 808, panes: 2, divider: 0))
        XCTAssertEqual(half, 0.5, accuracy: 1e-9)
        // Three panes: the second divider's center after two 200pt panes.
        let second = try XCTUnwrap(SplitRoom.dividerFraction(pointer: 412, length: 616, panes: 3, divider: 1))
        XCTAssertEqual(second, 2.0 / 3.0, accuracy: 1e-9)
        XCTAssertNil(SplitRoom.dividerFraction(pointer: 10, length: 8, panes: 2, divider: 0))
    }

    func testSplitsShowOnlyWhereThePanesFit() {
        let ipad = SplitRoom(supported: true, size: CGSize(width: 760, height: 1300))
        XCTAssertTrue(ipad.available)
        XCTAssertTrue(ipad.fits(panes: 3, orientation: .horizontal))
        XCTAssertFalse(ipad.fits(panes: 4, orientation: .horizontal), "four panes need more width")
        XCTAssertTrue(ipad.fits(panes: 4, orientation: .vertical))
        // A narrow window offers no split, and a phone never does.
        XCTAssertFalse(SplitRoom(supported: true, size: CGSize(width: 400, height: 900)).available)
        XCTAssertFalse(SplitRoom(supported: false, size: CGSize(width: 900, height: 400)).available)
        XCTAssertFalse(SplitRoom.none.available)
    }

    // MARK: - Workspace (curio-spaces)

    private func workspaceWithTabs() -> (Workspace, UUID, UUID, [UUID]) {
        var workspace = Workspace.firstRun()
        let (a, b) = (workspace.spaces[0].id, workspace.spaces[1].id)
        let ids = (0..<3).map { index in
            workspace.openTab(Tab(url: "https://\(index).test"), in: a, at: .sectionEnd(.unpinned), activate: false)!
        }
        workspace.activateTab(ids[0])
        return (workspace, a, b, ids)
    }

    func testASplitMovesToAnotherSpaceAsAWhole() throws {
        var (workspace, a, b, ids) = workspaceWithTabs()
        workspace.updateSpace(a) { space in
            if let split = space.strip.createSplit([ids[0], ids[2]], orientation: .vertical) {
                space.strip.resizeSplit(split, divider: 0, by: 0.2)
            }
        }
        workspace.activateTab(ids[2])
        XCTAssertTrue(workspace.moveTab(ids[2], toSpace: b))
        XCTAssertEqual(workspace.spaceOfTab(ids[0]), b)
        XCTAssertEqual(workspace.spaceOfTab(ids[2]), b)
        let moved = try XCTUnwrap(workspace.space(b)?.strip.split(of: ids[0]))
        XCTAssertEqual(moved.tabs, [ids[0], ids[2]])
        XCTAssertEqual(moved.orientation, .vertical)
        XCTAssertEqual(moved.sizes[0], 0.7, accuracy: 1e-9, "sizes kept")
        XCTAssertEqual(workspace.space(a)?.activeTab, ids[1])
    }

    func testClosingAPaneShowsThePaneBesideIt() {
        var (workspace, a, _, ids) = workspaceWithTabs()
        workspace.updateSpace(a) { $0.strip.createSplit([ids[0], ids[2]]) }
        // Order is now 0, 2, 1: the next tab in the list after 2 is 1.
        workspace.activateTab(ids[2])
        let closed = workspace.closeTab(ids[2])
        XCTAssertEqual(closed?.nextActive, ids[0], "the other pane, not the next tab")
        XCTAssertNil(workspace.activeSpace.strip.split(of: ids[0]))
    }

    func testMovingAFolderToAnotherSpaceTakesItsSplits() {
        var (workspace, a, b, ids) = workspaceWithTabs()
        var folder = UUID()
        workspace.updateSpace(a) { space in
            folder = space.strip.createGroup(name: "Docs", color: .ocean, members: [ids[0], ids[1]])
            space.strip.createSplit([ids[0], ids[1]], orientation: .vertical)
        }
        XCTAssertTrue(workspace.moveGroup(folder, from: a, to: b))
        XCTAssertEqual(workspace.space(b)?.strip.split(of: ids[0])?.orientation, .vertical)
        XCTAssertTrue(workspace.space(a)?.strip.splits.isEmpty ?? false)
    }

    func testSplitsSurviveARestartInTheirSpaceAndFolder() throws {
        var (workspace, a, _, ids) = workspaceWithTabs()
        var folder = UUID()
        workspace.updateSpace(a) { space in
            folder = space.strip.createGroup(name: "Research", color: .ocean, members: [ids[1]])
            if let split = space.strip.createSplit([ids[1], ids[2]], orientation: .vertical) {
                space.strip.resizeSplit(split, divider: 0, by: 0.1)
            }
        }
        let data = try JSONEncoder().encode(workspace)
        let restored = try JSONDecoder().decode(Workspace.self, from: data)
        let strip = try XCTUnwrap(restored.space(a)?.strip)
        let split = try XCTUnwrap(strip.split(of: ids[2]))
        XCTAssertEqual(split.tabs, [ids[1], ids[2]])
        XCTAssertEqual(split.orientation, .vertical)
        XCTAssertEqual(split.sizes[0], 0.6, accuracy: 1e-9)
        XCTAssertEqual(strip.group(folder)?.tabs, [ids[1], ids[2]])
        XCTAssertTrue(strip.isSaved(ids[2]))
    }
}
