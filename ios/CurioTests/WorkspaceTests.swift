import UIKit
import XCTest
@testable import Curio

final class WorkspaceTests: XCTestCase {
    func testFirstRunHasTwoSpaces() {
        let workspace = Workspace.firstRun()
        XCTAssertEqual(workspace.spaces.map(\.name), ["Personal", "Work"])
    }

    func testOpenCloseAndReopen() {
        var workspace = Workspace.firstRun()
        let personal = workspace.activeSpaceID
        let first = workspace.openTabInActiveSpace(Tab(url: "https://a.test"), activate: true)
        let second = workspace.openTabInActiveSpace(Tab(url: "https://b.test"), activate: true)
        XCTAssertEqual(workspace.activeSpace.strip.orderedTabIDs, [first, second])
        XCTAssertEqual(workspace.closeTab(second)?.nextActive, first)
        XCTAssertEqual(workspace.closedTabs.count, 1)

        workspace.switchSpace(workspace.spaces[1].id)
        XCTAssertEqual(workspace.reopenClosedTab(), second)
        XCTAssertEqual(workspace.activeSpaceID, personal)
        XCTAssertEqual(workspace.activeSpace.strip.orderedTabIDs, [first, second])
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

    func testRestoredClosedTabsAreNewestFirstAndKeepMissingSpaces() {
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
        orphan.tab = Tab(url: "https://orphan.test")
        orphan.space = UUID()
        orphan.closedAt = 9_000
        saved.append(orphan)

        let restored = Workspace(spaces: workspace.spaces, favorites: [], closed: saved)
        // Newest first; the two closed at 2_000 keep their saved order.
        XCTAssertEqual(restored.closedTabs.map(\.tab.id), [orphan.tab.id, ids[1], ids[2], ids[0]])
        XCTAssertEqual(restored.closedTabs.map(\.space), [orphan.space, personal, personal, personal])
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

    @MainActor
    func testArchiveSurvivesWorkspaceStoreRelaunchWithRestoreOnOrOff() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var workspace = Workspace.firstRun()
        let work = workspace.spaces[1].id
        let open = workspace.openTabInActiveSpace(Tab(url: "https://open.test"), activate: true)
        let pinned = Tab(url: "https://pinned.test")
        workspace.openTab(pinned, in: work, at: .sectionStart(.pinned), activate: false)
        let archived = workspace.openTabInActiveSpace(Tab(url: "https://archive.test"), activate: false)
        let removed = Tab(url: "https://deleted-space.test")
        let deletedSpace = workspace.createSpace(name: "Deleted", icon: "✦", gradient: nil)
        workspace.openTab(removed, in: deletedSpace, at: .sectionStart(.unpinned), activate: false)
        _ = workspace.closeTab(archived)
        _ = workspace.closeTab(removed.id)
        _ = workspace.deleteSpace(deletedSpace)
        workspace.switchSpace(work)
        WorkspaceStore(url: url).saveNow(workspace)

        let reopened = WorkspaceStore(url: url)
        let restored = reopened.load(restoreSession: true)
        XCTAssertEqual(restored, workspace)

        let fresh = reopened.load(restoreSession: false)
        XCTAssertEqual(fresh.activeSpaceID, workspace.spaces[0].id)
        XCTAssertNil(fresh.tab(open))
        XCTAssertTrue(fresh.space(work)?.strip.isPinned(pinned.id) == true)
        XCTAssertEqual(fresh.closedTabs.map(\.tab.id), [removed.id, archived])

        reopened.saveNow(fresh)
        XCTAssertEqual(WorkspaceStore(url: url).load(restoreSession: true).closedTabs, workspace.closedTabs)
    }

    @MainActor
    func testArchiveLoadsWhenTheRestOfTheWorkspaceIsUnreadable() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var workspace = Workspace.firstRun()
        let closed = workspace.openTabInActiveSpace(Tab(url: "https://archive.test"), activate: false)
        _ = workspace.closeTab(closed)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(workspace)) as? [String: Any])
        json["spaces"] = "invalid as a space list"
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let store = WorkspaceStore(url: url)
        for restoreSession in [true, false] {
            let recovered = store.load(restoreSession: restoreSession)
            XCTAssertEqual(recovered.spaces.map(\.name), ["Personal", "Work"])
            XCTAssertNil(recovered.space(workspace.activeSpaceID))
            XCTAssertEqual(recovered.closedTabs, workspace.closedTabs)
        }
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
        XCTAssertEqual(workspace.archivedTabs(matching: "work").first?.space?.name, "Work")
        XCTAssertEqual(workspace.archivedTabs(matching: "recipes").map(\.closed.tab.id), [personalTab])
        // Every word must match somewhere.
        XCTAssertEqual(workspace.archivedTabs(matching: "personal docs").count, 0)
        XCTAssertEqual(workspace.archivedTabs(matching: "work docs").map(\.closed.tab.id), [workTab.id])
    }

    func testClosedTabOutlivesItsSpaceAndReopensNextToTheActiveTab() {
        var workspace = Workspace.firstRun()
        let work = workspace.spaces[1].id
        var archived = Tab(url: "https://docs.test/curio")
        archived.title = "Reference"
        workspace.openTab(archived, in: work, at: .sectionStart(.pinned), activate: false)
        _ = workspace.closeTab(archived.id)
        XCTAssertNotNil(workspace.deleteSpace(work))

        XCTAssertEqual(workspace.archivedTabs(matching: "").map(\.closed.tab.id), [archived.id])
        XCTAssertNil(workspace.archivedTabs(matching: "").first?.space)
        XCTAssertEqual(workspace.archivedTabs(matching: "reference curio").map(\.closed.tab.id), [archived.id])
        XCTAssertTrue(workspace.archivedTabs(matching: "work").isEmpty)

        let active = workspace.openTabInActiveSpace(Tab(), activate: true)
        let next = workspace.openTabInActiveSpace(Tab(), activate: false)
        XCTAssertEqual(workspace.reopenClosed(archived.id), archived.id)
        XCTAssertEqual(workspace.activeSpace.strip.orderedTabIDs, [active, archived.id, next])
        XCTAssertEqual(workspace.activeTabID, archived.id)
        XCTAssertTrue(workspace.closedTabs.isEmpty)
    }

    func testReopenClosedTabUsesTheNewestTabEvenIfItsSpaceIsGone() {
        var workspace = Workspace.firstRun()
        let personal = workspace.activeSpaceID
        let work = workspace.spaces[1].id
        let pinned = Tab()
        workspace.openTab(pinned, in: personal, at: .sectionStart(.pinned), activate: true)
        let regular = workspace.openTabInActiveSpace(Tab(), activate: false)
        let older = Tab()
        workspace.openTab(older, in: personal, at: .afterTab(regular), activate: false)
        let newest = Tab()
        workspace.openTab(newest, in: work, at: .sectionStart(.unpinned), activate: false)
        _ = workspace.closeTab(older.id)
        _ = workspace.closeTab(newest.id)
        _ = workspace.deleteSpace(work)

        XCTAssertEqual(workspace.reopenClosedTab(), newest.id)
        XCTAssertEqual(workspace.activeSpace.strip.orderedTabIDs, [pinned.id, newest.id, regular])
        XCTAssertEqual(workspace.activeTabID, newest.id)
        XCTAssertEqual(workspace.closedTabs.map(\.tab.id), [older.id])
    }

    @MainActor
    func testArchiveRowForDeletedSpaceShowsOnlyHostAndReopensInActiveSpace() async throws {
        let app = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
        let session = BrowserSession(services: app.services)
        session.saveSpace(nil, name: "Archive Destination", icon: "✦", gradient: .default)
        let target = session.workspace.activeSpace
        session.saveSpace(nil, name: "Archive Test", icon: "✦", gradient: .default)
        let deletedSpace = session.workspace.activeSpaceID
        let id = session.openInNewTab("https://archive-row.test", activate: false)
        session.closeTab(id)
        session.switchSpace(target.id)
        session.deleteSpace(deletedSpace)

        try autoreleasepool {
            let library = LibraryViewController(session: session)
            library.loadViewIfNeeded()
            let rows = library.view.subviews.flatMap(\.subviews)
                .compactMap { $0 as? UIScrollView }.flatMap(\.subviews)
                .compactMap { $0 as? UIStackView }.flatMap(\.arrangedSubviews)
                .compactMap { $0 as? ListRowControl }
            let row = try XCTUnwrap(rows.first { $0.row.titleLabel.text == "archive-row.test" })
            XCTAssertEqual(row.row.subtitleLabel.text, "archive-row.test")
            XCTAssertTrue(row.row.trailingStack.arrangedSubviews.isEmpty)
            let tooltip = row.interactions.compactMap { $0 as? UIToolTipInteraction }.first
            XCTAssertEqual(tooltip?.defaultToolTip, "Reopen in \(target.name)")
            XCTAssertEqual(row.accessibilityHint, "Reopen in \(target.name)")
            XCTAssertTrue(row.accessibilityActivate())
            XCTAssertEqual(session.activeTabID, id)
            XCTAssertEqual(session.workspace.spaceOfTab(id), target.id)
            XCTAssertFalse(session.workspace.closedTabs.contains { $0.tab.id == id })
            session.closeTab(id)
        }
    }

    func testCodableRoundTripKeepsActiveSpace() throws {
        var workspace = Workspace.firstRun()
        workspace.switchSpace(workspace.spaces[1].id)
        workspace.openTabInActiveSpace(Tab(url: "https://a.test"), activate: true)
        let decoded = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        XCTAssertEqual(decoded.activeSpaceID, workspace.activeSpaceID)
        XCTAssertEqual(decoded.activeTabID, workspace.activeTabID)
    }

    func testANewTabFromAFolderTabOpensBelowTheFolder() {
        var workspace = Workspace.firstRun()
        let space = workspace.activeSpaceID
        let ids = (0..<3).compactMap { workspace.openTab(Tab(url: "https://\($0).test"), in: space, at: .sectionEnd(.unpinned), activate: false) }
        var folder: UUID?
        workspace.updateActiveSpace { folder = $0.strip.createGroup(name: "Reading", color: .sage, members: [ids[0]]) }
        workspace.activateTab(ids[0])

        let new = workspace.openTabInActiveSpace(Tab(url: "https://new.test"), activate: true)
        let strip = workspace.activeSpace.strip
        XCTAssertEqual(strip.group(folder!)?.tabs, [ids[0]])
        XCTAssertNil(strip.location(of: new)?.group)
        XCTAssertEqual(strip.orderedTabIDs[1], new, "right below the folder")
    }

    func testSettingAFavoriteURLLeavesItsHome() {
        var workspace = Workspace.firstRun()
        let id = workspace.openTabInActiveSpace(Tab(url: "https://fav.test"), activate: true)
        workspace.favoriteFromTab(id)
        XCTAssertTrue(workspace.setTabURL(id, "https://other.test"))
        XCTAssertEqual(workspace.tab(id)?.url, "https://other.test")
        XCTAssertEqual(workspace.tab(id)?.homeURL, "https://fav.test")
    }
}
