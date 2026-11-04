import XCTest
@testable import Curio

final class WorkspaceTests: XCTestCase {
    func testFirstRunHasTwoSpaces() {
        let workspace = Workspace.firstRun()
        XCTAssertEqual(workspace.spaces.map(\.name), ["Personal", "Work"])
    }

    func testOpenCloseAndReopen() {
        var workspace = Workspace.firstRun()
        let first = workspace.openTabInActiveSpace(Tab(url: "https://a.test"), activate: true)
        let second = workspace.openTabInActiveSpace(Tab(url: "https://b.test"), activate: true)
        XCTAssertEqual(workspace.activeSpace.strip.orderedTabIDs, [first, second])
        XCTAssertEqual(workspace.closeTab(second)?.nextActive, first)
        XCTAssertEqual(workspace.closedTabs.count, 1)
        XCTAssertEqual(workspace.reopenClosedTab(), second)
        XCTAssertEqual(workspace.activeTabID, second)
    }

    func testActivatingATabSwitchesToItsSpace() {
        var workspace = Workspace.firstRun()
        let work = workspace.spaces[1].id
        let tab = Tab(url: "https://work.test")
        workspace.openTab(tab, in: work, at: .sectionEnd(.unpinned), activate: false)
        XCTAssertTrue(workspace.activateTab(tab.id))
        XCTAssertEqual(workspace.activeSpaceID, work)
    }

    func testFavoritesKeepTabIdentity() {
        var workspace = Workspace.firstRun()
        let id = workspace.openTabInActiveSpace(Tab(url: "https://fav.test"), activate: true)
        XCTAssertNotNil(workspace.favoriteFromTab(id))
        XCTAssertEqual(workspace.favorites.first?.tab.id, id)
        XCTAssertEqual(workspace.activeTabID, id)
        XCTAssertNil(workspace.spaceOfTab(id))
    }

    func testMoveTabToAnotherSpace() {
        var workspace = Workspace.firstRun()
        let work = workspace.spaces[1].id
        let id = workspace.openTabInActiveSpace(Tab(url: "https://a.test"), activate: true)
        XCTAssertTrue(workspace.moveTab(id, toSpace: work))
        XCTAssertEqual(workspace.spaceOfTab(id), work)
        XCTAssertNil(workspace.activeTabID)
    }

    func testLastSpaceCannotBeDeleted() {
        var workspace = Workspace(spaces: [], favorites: [])
        XCTAssertNil(workspace.deleteSpace(workspace.spaces[0].id))
    }

    func testFirstRunThemes() {
        let workspace = Workspace.firstRun()
        XCTAssertEqual(workspace.spaces.map(\.gradient), [.lavenderBlush, .skyHaze])
    }

    func testNewSpacesTakeTheNextThemeInTheSameTone() {
        var workspace = Workspace.firstRun()
        let id = workspace.createSpace(name: "Play", icon: "🎨", gradient: nil)
        XCTAssertEqual(workspace.space(id)?.gradient, .mintCream)
        workspace.setSpaceGradient(id, .ember)
        let next = workspace.createSpace(name: "Night", icon: "☾", gradient: nil)
        XCTAssertEqual(workspace.space(next)?.gradient, .midnightIndigo)
    }

    func testClosingATabRecordsWhenItWasClosed() {
        var workspace = Workspace.firstRun()
        let id = workspace.openTabInActiveSpace(Tab(url: "https://a.test"), activate: true)
        let before = Timestamp.now
        _ = workspace.closeTab(id)
        XCTAssertGreaterThanOrEqual(workspace.closedTabs.first?.closedAt ?? 0, before)
    }

    func testRestoredClosedTabsAreNewestFirstAndSkipMissingSpaces() {
        var workspace = Workspace.firstRun()
        let personal = workspace.activeSpaceID
        let ids = (0 ..< 3).map { workspace.openTabInActiveSpace(Tab(url: "https://\($0).test"), activate: false) }
        ids.forEach { _ = workspace.closeTab($0) }
        var saved = workspace.closedTabs
        XCTAssertEqual(saved.map(\.tab.id), ids.reversed())
        saved[0].closedAt = 2_000
        saved[1].closedAt = 3_000
        saved[2].closedAt = 2_000
        var orphan = saved[0]
        orphan.space = UUID()
        orphan.closedAt = 9_000
        saved.append(orphan)

        let restored = Workspace(spaces: workspace.spaces, favorites: [], closed: saved)
        // Newest first; the two closed at 2_000 keep their saved order.
        XCTAssertEqual(restored.closedTabs.map(\.tab.id), [ids[1], ids[2], ids[0]])
        XCTAssertTrue(restored.closedTabs.allSatisfy { $0.space == personal })
    }

    func testRestoringKeepsAtMostTheLimit() {
        var workspace = Workspace.firstRun()
        let ids = (0 ..< Workspace.closedTabLimit).map { workspace.openTabInActiveSpace(Tab(url: "https://\($0).test"), activate: false) }
        ids.forEach { _ = workspace.closeTab($0) }
        let extra = workspace.closedTabs + workspace.closedTabs.prefix(5)
        XCTAssertEqual(Workspace(spaces: workspace.spaces, favorites: [], closed: extra).closedTabs.count, Workspace.closedTabLimit)
    }

    func testClosedTabsSurviveARestartNewestFirst() throws {
        var workspace = Workspace.firstRun()
        let first = workspace.openTabInActiveSpace(Tab(url: "https://first.test"), activate: false)
        let second = workspace.openTabInActiveSpace(Tab(url: "https://second.test"), activate: false)
        _ = workspace.closeTab(first)
        _ = workspace.closeTab(second)
        let data = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: data)
        XCTAssertEqual(decoded.closedTabs, workspace.closedTabs)
        XCTAssertEqual(decoded.closedTabs.map(\.tab.id), [second, first])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let closed = try XCTUnwrap(json["closed"] as? [[String: Any]])
        XCTAssertNotNil(closed.first?["closed_at"] as? Int64)
    }

    func testOldClosedTabsWithoutCloseTimeStillLoad() throws {
        var workspace = Workspace.firstRun()
        let id = workspace.openTabInActiveSpace(Tab(url: "https://old.test"), activate: false)
        _ = workspace.closeTab(id)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        var closed = try XCTUnwrap(json["closed"] as? [[String: Any]])
        closed[0]["closed_at"] = nil
        json["closed"] = closed
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Workspace.self, from: old)
        XCTAssertEqual(decoded.closedTabs.map(\.tab.id), [id])
        XCTAssertEqual(decoded.closedTabs.first?.closedAt, 0)
    }

    func testArchiveSearchMatchesTitleURLAndSpaceName() {
        var workspace = Workspace.firstRun()
        let work = workspace.spaces[1].id
        let personalTab = workspace.openTabInActiveSpace(Tab(url: "https://recipes.test"), activate: false)
        let workTab = Tab(url: "https://docs.test")
        workspace.openTab(workTab, in: work, at: .sectionEnd(.unpinned), activate: false)
        _ = workspace.closeTab(personalTab)
        _ = workspace.closeTab(workTab.id)

        XCTAssertEqual(workspace.archivedTabs(matching: "").map(\.closed.tab.id), [workTab.id, personalTab])
        XCTAssertEqual(workspace.archivedTabs(matching: "work").map(\.closed.tab.id), [workTab.id])
        XCTAssertEqual(workspace.archivedTabs(matching: "work").first?.space.name, "Work")
        XCTAssertEqual(workspace.archivedTabs(matching: "recipes").map(\.closed.tab.id), [personalTab])
        // Every word must match somewhere.
        XCTAssertEqual(workspace.archivedTabs(matching: "personal docs").count, 0)
        XCTAssertEqual(workspace.archivedTabs(matching: "work docs").map(\.closed.tab.id), [workTab.id])
    }

    func testCodableRoundTripKeepsActiveSpace() throws {
        var workspace = Workspace.firstRun()
        workspace.switchSpace(workspace.spaces[1].id)
        workspace.openTabInActiveSpace(Tab(url: "https://a.test"), activate: true)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(decoded.activeSpaceID, workspace.activeSpaceID)
        XCTAssertEqual(decoded.activeTabID, workspace.activeTabID)
    }
}
