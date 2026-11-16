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
    // MARK: - Arc-style folders

    func testTabsInFoldersAreSavedWithAHomeURL() {
        var (strip, ids) = strip(3)
        let folder = strip.createGroup(name: "Reading", color: .sage, members: [ids[0]])
        XCTAssertTrue(strip.isSaved(ids[0]))
        XCTAssertFalse(strip.isSaved(ids[1]))
        XCTAssertEqual(strip.tab(ids[0])?.homeURL, "https://0.test")

        // Dragging a tab into the folder saves it too.
        XCTAssertTrue(strip.move(ids[1], to: .inGroup(folder, nil)))
        XCTAssertTrue(strip.isSaved(ids[1]))
        XCTAssertEqual(strip.tab(ids[1])?.homeURL, "https://1.test")

        // Taking it out of the folder forgets its home.
        XCTAssertTrue(strip.move(ids[1], to: .sectionEnd(.unpinned)))
        XCTAssertFalse(strip.isSaved(ids[1]))
        XCTAssertNil(strip.tab(ids[1])?.homeURL)
    }

    func testAHomeIsKeptWhileTheTabStaysSaved() {
        var (strip, ids) = strip(1)
        strip.createGroup(name: "Reading", color: .sage, members: [ids[0]])
        XCTAssertTrue(strip.setTabURL(ids[0], "https://elsewhere.test"))
        XCTAssertEqual(strip.tab(ids[0])?.homeURL, "https://0.test")
    }

    func testRemovingAFolderButKeepingTabsForgetsTheirHomes() {
        var (strip, ids) = strip(2)
        let folder = strip.createGroup(name: "Reading", color: .sage, members: ids)
        strip.deleteGroup(folder, keepTabs: true)
        for id in ids {
            XCTAssertFalse(strip.isSaved(id))
            XCTAssertNil(strip.tab(id)?.homeURL)
        }
    }

    func testSavedBlankTabsUseTheFirstPageAsHome() {
        var (strip, ids) = strip(1)
        let folder = strip.createGroup(name: "Reading", color: .sage, members: [ids[0]])
        let inFolder = strip.insert(Tab(), at: .afterTab(ids[0]))
        let dragged = strip.insert(Tab(), at: .sectionEnd(.unpinned))
        let pinned = strip.insert(Tab(), at: .sectionEnd(.unpinned))
        XCTAssertTrue(strip.move(dragged, to: .inGroup(folder, nil)))
        XCTAssertTrue(strip.pin(pinned))

        for id in [inFolder, dragged, pinned] {
            XCTAssertTrue(strip.isSaved(id))
            XCTAssertNil(strip.tab(id)?.homeURL)
            XCTAssertTrue(strip.setTabURL(id, "https://first.test"))
            XCTAssertTrue(strip.setTabURL(id, "https://second.test"))
            XCTAssertTrue(strip.setTabURL(id, Curio.newTabURL))
            XCTAssertEqual(strip.tab(id)?.homeURL, "https://first.test")
        }
    }

    func testRestoringABlankHomeUsesTheCurrentPageIfAvailable() {
        var navigated = Tab(url: "https://current.test")
        navigated.homeURL = Curio.newTabURL
        var blank = Tab()
        blank.homeURL = Curio.newTabURL
        var strip = TabStrip(tabs: [navigated, blank], groups: [], pinned: [.tab(navigated.id), .tab(blank.id)], unpinned: [])
        XCTAssertEqual(strip.tab(navigated.id)?.homeURL, "https://current.test")
        XCTAssertNil(strip.tab(blank.id)?.homeURL)
        XCTAssertTrue(strip.setTabURL(blank.id, "https://first.test"))
        XCTAssertEqual(strip.tab(blank.id)?.homeURL, "https://first.test")
    }

    func testAnEmptyFolderStaysUntilDeleted() {
        var (strip, ids) = strip(1)
        let folder = strip.createGroup(name: "Empty", color: .sage, members: [])
        XCTAssertEqual(strip.group(folder)?.tabs, [])
        XCTAssertTrue(strip.rows(alwaysShow: nil).contains(.group(id: folder, section: .unpinned)))

        strip.move(ids[0], to: .inGroup(folder, nil))
        _ = strip.remove(ids[0])
        XCTAssertNotNil(strip.group(folder), "closing a folder's last tab keeps the folder")
    }

    func testNewTabsOpenOutsideFolders() {
        var (strip, ids) = strip(3)
        let folder = strip.createGroup(name: "Reading", color: .sage, members: [ids[0]])
        strip.pin(ids[2])

        // From a regular tab: right after it.
        XCTAssertEqual(strip.placementForNewTab(anchor: ids[1]), .afterTab(ids[1]))
        // From a tab in a folder: right after the folder, not inside it.
        XCTAssertEqual(strip.placementForNewTab(anchor: ids[0]), .afterGroup(folder))
        let new = strip.insert(Tab(url: "https://new.test"), at: strip.placementForNewTab(anchor: ids[0]))
        XCTAssertFalse(strip.isSaved(new))
        XCTAssertNil(strip.location(of: new)?.group)
        // From a pinned tab or nothing: top of the regular tabs.
        for anchor in [ids[2], nil] {
            XCTAssertEqual(strip.placementForNewTab(anchor: anchor), .sectionStart(.unpinned))
        }
    }

    func testFoldersSurviveARoundTrip() throws {
        var (strip, ids) = strip(2)
        let full = strip.createGroup(name: "Reading", color: .rose, members: [ids[0]])
        strip.setGroupCollapsed(full, true)
        let empty = strip.createGroup(name: "Empty", color: .sage, members: [])
        strip.moveGroup(empty, to: .sectionStart(.unpinned))
        let decoded = try JSONDecoder().decode(TabStrip.self, from: JSONEncoder().encode(strip))
        XCTAssertEqual(decoded.group(full)?.name, "Reading")
        XCTAssertEqual(decoded.group(full)?.color, .rose)
        XCTAssertEqual(decoded.group(full)?.collapsed, true)
        XCTAssertEqual(decoded.group(full)?.tabs, [ids[0]])
        XCTAssertEqual(decoded.group(empty)?.tabs, [])
        XCTAssertEqual(decoded.items(.unpinned), strip.items(.unpinned))
        XCTAssertEqual(decoded.tab(ids[0])?.homeURL, "https://0.test")
    }
}
