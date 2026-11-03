import XCTest
@testable import Curio

final class TabStripTests: XCTestCase {
    private func strip(_ count: Int) -> (TabStrip, [UUID]) {
        var strip = TabStrip()
        var ids: [UUID] = []
        for index in 0..<count {
            ids.append(strip.insert(Tab(url: "https://\(index).test"), at: .sectionEnd(.unpinned)))
        }
        return (strip, ids)
    }

    func testInsertAndOrder() {
        let (strip, ids) = strip(3)
        XCTAssertEqual(strip.orderedTabIDs, ids)
        XCTAssertEqual(strip.count, 3)
    }

    func testPinMovesToPinnedAndRemembersHome() {
        var (strip, ids) = strip(3)
        XCTAssertTrue(strip.pin(ids[2]))
        XCTAssertTrue(strip.isPinned(ids[2]))
        XCTAssertEqual(strip.orderedTabIDs.first, ids[2])
        XCTAssertEqual(strip.tab(ids[2])?.homeURL, "https://2.test")
        XCTAssertTrue(strip.unpin(ids[2]))
        XCTAssertNil(strip.tab(ids[2])?.homeURL)
        XCTAssertEqual(strip.items(.unpinned).first, .tab(ids[2]))
    }

    func testRemoveAndRestorePlacement() {
        var (strip, ids) = strip(3)
        let removed = strip.remove(ids[1])
        XCTAssertEqual(removed?.restoreAt, .afterTab(ids[0]))
        if let removed { strip.insert(removed.tab, at: removed.restoreAt) }
        XCTAssertEqual(strip.orderedTabIDs, ids)
    }

    func testMoveRelativeToSelfIsNoOp() {
        var (strip, ids) = strip(2)
        XCTAssertFalse(strip.move(ids[0], to: .beforeTab(ids[0])))
    }

    func testGroupsCollapseButKeepActiveTabVisible() {
        var (strip, ids) = strip(3)
        let group = strip.createGroup(name: "Reading", color: .sage, members: [ids[0], ids[1]])
        XCTAssertEqual(strip.group(group)?.tabs, [ids[0], ids[1]])
        strip.setGroupCollapsed(group, true)
        let rows = strip.rows(alwaysShow: ids[1])
        XCTAssertTrue(rows.contains(.tab(id: ids[1], section: .unpinned, group: group)))
        XCTAssertFalse(rows.contains(.tab(id: ids[0], section: .unpinned, group: group)))
    }

    func testDeleteGroupKeepingTabsSplicesThemIn() {
        var (strip, ids) = strip(3)
        let group = strip.createGroup(name: "G", color: .iris, members: [ids[1], ids[2]])
        XCTAssertTrue(strip.deleteGroup(group, keepTabs: true).isEmpty)
        XCTAssertEqual(strip.orderedTabIDs, ids)
        XCTAssertTrue(strip.groups.isEmpty)
    }

    func testNeighborForClosePrefersNextThenPrevious() {
        let (strip, ids) = strip(3)
        XCTAssertEqual(strip.neighborForClose(ids[1]), ids[2])
        XCTAssertEqual(strip.neighborForClose(ids[2]), ids[1])
    }

    func testCorruptPartsAreRepaired() {
        let tab = Tab(url: "https://a.test")
        let orphan = Tab(url: "https://b.test")
        let strip = TabStrip(tabs: [tab, orphan], groups: [], pinned: [.tab(tab.id), .tab(UUID())], unpinned: [.tab(tab.id)])
        XCTAssertEqual(strip.orderedTabIDs, [tab.id, orphan.id])
    }

    func testCodableRoundTrip() throws {
        var (strip, ids) = strip(3)
        strip.pin(ids[0])
        strip.createGroup(name: "G", color: .rose, members: [ids[2]])
        let data = try JSONEncoder().encode(strip)
        let decoded = try JSONDecoder().decode(TabStrip.self, from: data)
        XCTAssertEqual(decoded.orderedTabIDs, strip.orderedTabIDs)
        XCTAssertEqual(decoded.rows(alwaysShow: nil), strip.rows(alwaysShow: nil))
    }
}
