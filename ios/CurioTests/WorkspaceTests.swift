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

    func testNewSpacesCycleColors() {
        var workspace = Workspace.firstRun()
        let id = workspace.createSpace(name: "Play", icon: "🎨", color: nil)
        XCTAssertEqual(workspace.space(id)?.color, AccentColor.lagoon.next)
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
