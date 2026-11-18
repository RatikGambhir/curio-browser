import XCTest
@testable import Curio

@MainActor
final class BrowserSessionIntegrationTests: XCTestCase {
    func testSavedTabReturnsHomeAndSurvivesAnImmediateSecondCloseAndRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = BrowserSession(services: makeServices(in: directory))
        let other = session.openInNewTab(Curio.newTabURL)
        let saved = session.openInNewTab(Curio.newTabURL)
        session.togglePin(saved)

        let home = "data:text/plain,Home"
        session.open(home, newTab: true)
        XCTAssertEqual(session.activeTabID, saved, "Opening from a blank tab should reuse it")
        XCTAssertEqual(session.workspace.tab(saved)?.homeURL, home)
        session.navigateActive("data:text/plain,Away")
        XCTAssertEqual(session.workspace.tab(saved)?.url, "data:text/plain,Away")
        XCTAssertTrue(try XCTUnwrap(session.activeLiveTab).isAwake)

        session.unloadOrArchiveTab(saved)
        session.unloadOrArchiveTab(saved)
        XCTAssertNil(session.liveTabs[saved])
        XCTAssertEqual(session.activeTabID, other)
        XCTAssertEqual(session.workspace.tab(saved)?.url, home)
        XCTAssertTrue(session.workspace.closedTabs.isEmpty)

        session.saveNow()
        let restarted = BrowserSession(services: makeServices(in: directory))
        XCTAssertEqual(restarted.activeTabID, other)
        XCTAssertTrue(restarted.isSaved(saved))
        XCTAssertEqual(restarted.workspace.tab(saved)?.url, home)
        XCTAssertEqual(restarted.workspace.tab(saved)?.homeURL, home)
        XCTAssertTrue(restarted.workspace.closedTabs.isEmpty)
    }

    func testAssistantReadsSleepingTabAndFindCyclesThroughMatches() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let services = makeServices(in: directory)
        let fixture = "data:text/html,%3Ctitle%3EField%20Notes%3C/title%3E%3Cp%3EOrbit%20orbit%3C/p%3E"
        var workspace = Workspace.firstRun()
        let tab = Tab(url: fixture)
        workspace.openTab(tab, in: workspace.activeSpaceID, at: .sectionStart(.unpinned), activate: false)
        services.workspaceStore.saveNow(workspace)
        let session = BrowserSession(services: services)
        let active = session.activeTabID
        XCTAssertNil(session.liveTabs[tab.id])

        let pages = await session.extractPages([tab.id])
        XCTAssertEqual(pages.map(\.title), ["Field Notes"])
        XCTAssertEqual(pages.map(\.url), [fixture])
        XCTAssertEqual(pages.map(\.text), ["Orbit orbit"])
        XCTAssertEqual(session.activeTabID, active)

        let live = try XCTUnwrap(session.liveTabs[tab.id])
        XCTAssertFalse(live.isActive)
        let first = await live.find("orbit", forward: true)
        let second = await live.find("orbit", forward: true)
        let wrapped = await live.find("orbit", forward: true)
        let missing = await live.find("comet", forward: true)
        XCTAssertEqual(first, FindResult(matches: 2, active: 1))
        XCTAssertEqual(second, FindResult(matches: 2, active: 2))
        XCTAssertEqual(wrapped, first)
        XCTAssertEqual(missing, FindResult())
    }

    func testFolderMovesWithItsTabsAndRestoresWithSessionRestoreOff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = BrowserSession(services: makeServices(in: directory))
        let source = session.workspace.activeSpaceID
        let destination = try XCTUnwrap(session.workspace.spaces.first { $0.id != source }).id

        let folder = session.newFolder()
        session.renameGroup(folder, to: "Reading List")
        session.setGroupColor(folder, .ocean)
        let saved = session.openInNewTab("data:text/plain,Saved")
        session.dropTab(saved, at: .inGroup(folder, nil))
        let regular = session.openInNewTab("data:text/plain,Regular")
        session.setGroupCollapsed(folder, true)
        XCTAssertEqual(session.workspace.activeSpace.strip.group(folder)?.tabs, [saved])
        XCTAssertNil(session.workspace.activeSpace.strip.location(of: regular)?.group)

        session.moveGroupToSpace(folder, from: source, to: destination)
        XCTAssertNil(session.workspace.space(source)?.strip.group(folder))
        XCTAssertEqual(session.workspace.spaceOfTab(saved), destination)
        XCTAssertEqual(session.workspace.spaceOfTab(regular), source)
        session.saveNow()

        var settings = Settings()
        settings.browsing.restoreSession = false
        JSONFile<Settings>(url: directory.appending(path: "settings.json")).saveNow(settings)
        let restored = BrowserSession(services: makeServices(in: directory))
        XCTAssertFalse(restored.settings.browsing.restoreSession)
        XCTAssertNil(restored.workspace.tab(regular))
        XCTAssertTrue(restored.workspace.closedTabs.isEmpty)
        let restoredFolder = try XCTUnwrap(restored.workspace.space(destination)?.strip.group(folder))
        XCTAssertEqual(restoredFolder.name, "Reading List")
        XCTAssertEqual(restoredFolder.color, .ocean)
        XCTAssertTrue(restoredFolder.collapsed)
        XCTAssertEqual(restoredFolder.tabs, [saved])
        XCTAssertEqual(restored.workspace.tab(saved)?.homeURL, "data:text/plain,Saved")
    }

    func testSplitKeepsFocusAndSizesWhenSpaceNarrowsAndAfterRestart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = BrowserSession(services: makeServices(in: directory))
        let wide = SplitRoom(supported: true, size: CGSize(width: 1100, height: 900))
        session.setSplitRoom(wide)
        let first = session.openInNewTab("data:text/plain,First")
        let second = session.openInNewTab("data:text/plain,Second", activate: false)
        session.splitWith(second, before: false)
        let splitID = try XCTUnwrap(session.activeSplit?.id)
        XCTAssertTrue(session.resizeSplit(splitID, divider: 0, by: 0.15))
        session.focusPane(first)
        let split = try XCTUnwrap(session.visibleSplit)
        XCTAssertEqual(split.tabs, [first, second])
        XCTAssertTrue(session.liveTabs[second]?.isActive == true)

        session.setSplitRoom(.none)
        XCTAssertEqual(session.visibleTabIDs, [first])
        XCTAssertNil(session.visibleSplit)
        XCTAssertEqual(session.activeSplit, split)
        XCTAssertFalse(try XCTUnwrap(session.liveTabs[second]).isActive)
        session.handleMemoryWarning()
        XCTAssertFalse(try XCTUnwrap(session.liveTabs[second]).isAwake)
        session.setSplitRoom(wide)
        XCTAssertEqual(session.visibleSplit, split)
        XCTAssertTrue(session.liveTabs[second]?.isAwake == true)
        XCTAssertEqual(session.activeTabID, first)

        session.saveNow()
        let restored = BrowserSession(services: makeServices(in: directory))
        restored.setSplitRoom(wide)
        XCTAssertEqual(restored.visibleSplit, split)
        XCTAssertEqual(restored.activeTabID, first)
        XCTAssertTrue(restored.liveTabs[second]?.isActive == true)
    }

    func testFavoriteRemembersItsHomeAcrossSpacesAndRemovalRestoresFocusInBoth() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = BrowserSession(services: makeServices(in: directory))
        let firstSpace = session.workspace.activeSpaceID
        let secondSpace = try XCTUnwrap(session.workspace.spaces.first { $0.id != firstSpace }).id
        let firstFallback = session.openInNewTab(Curio.newTabURL)
        let home = "data:text/plain,FavoriteHome"
        let favoriteTab = session.openInNewTab(home)
        let live = try XCTUnwrap(session.activeLiveTab)
        session.addFavorite(favoriteTab)
        XCTAssertEqual(session.activeTabID, favoriteTab)
        XCTAssertTrue(session.activeLiveTab === live)
        XCTAssertEqual(session.workspace.favorites.map(\.tab.id), [favoriteTab])
        XCTAssertNil(session.workspace.spaceOfTab(favoriteTab))

        session.switchSpace(secondSpace)
        let secondFallback = session.openInNewTab(Curio.newTabURL)
        XCTAssertEqual(session.visibleTabOrder.first, favoriteTab)
        session.activateTab(favoriteTab)
        session.navigateActive("data:text/plain,FavoriteAway")
        XCTAssertEqual(session.activeTab?.homeURL, home)
        session.resetFavorite(favoriteTab)
        XCTAssertEqual(session.activeTab?.url, home)
        XCTAssertEqual(session.workspace.activeSpaceID, secondSpace)

        session.saveNow()
        let restored = BrowserSession(services: makeServices(in: directory))
        let favorite = try XCTUnwrap(restored.workspace.favorites.first)
        XCTAssertEqual(favorite.tab.id, favoriteTab)
        XCTAssertEqual(favorite.tab.homeURL, home)
        XCTAssertEqual(restored.workspace.space(firstSpace)?.activeTab, favoriteTab)
        XCTAssertEqual(restored.workspace.space(secondSpace)?.activeTab, favoriteTab)
        restored.removeFavorite(favorite.id)
        XCTAssertTrue(restored.workspace.favorites.isEmpty)
        XCTAssertEqual(restored.workspace.space(firstSpace)?.activeTab, firstFallback)
        XCTAssertEqual(restored.workspace.space(secondSpace)?.activeTab, secondFallback)
        XCTAssertTrue(restored.workspace.closedTabs.isEmpty)
    }

    private func makeServices(in directory: URL) -> AppServices {
        AppServices(
            settings: SettingsStore(url: directory.appending(path: "settings.json")),
            workspaceStore: WorkspaceStore(url: directory.appending(path: "workspace.json")),
            history: HistoryStore(url: directory.appending(path: "history.json"))
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
