import XCTest

final class BrowserFlowTests: XCTestCase {
    @MainActor
    func testAddressBarNavigatesBackAndForwardInTheSameTab() {
        let app = launchBrowser()
        openPage("FirstPage", in: app)

        let back = app.buttons["browser.back"]
        let forward = app.buttons["browser.forward"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertFalse(back.isEnabled)
        XCTAssertFalse(forward.isEnabled)

        let address = app.descendants(matching: .any).matching(identifier: "browser.address").firstMatch
        address.tap()
        openPage("SecondPage", in: app)
        tapEnabled(back)
        assertPage("FirstPage", in: app)
        tapEnabled(forward)
        assertPage("SecondPage", in: app)
    }

    @MainActor
    func testClosedTabCanBeFoundAndReopenedAfterRelaunch() {
        let app = launchBrowser()
        openPage("KeepOpen", in: app)
        showSidebar(in: app)
        app.descendants(matching: .any).matching(identifier: "sidebar.newTab").firstMatch.tap()
        openPage("RestoreMe", in: app)
        showSidebar(in: app)

        let tab = app.collectionViews.cells.matching(NSPredicate(format: "label == %@", "RestoreMe")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        let close = tab.buttons["sidebar.tab.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(tab.waitForNonExistence(timeout: 5))

        // Backgrounding exercises the scene's immediate session save before relaunch.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.terminate()
        app.launch()
        assertPage("KeepOpen", in: app)

        showSidebar(in: app)
        app.buttons["sidebar.library"].tap()
        let row = app.buttons.matching(identifier: "library.archiveTab")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "RestoreMe,")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        let search = app.textFields["library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("irrelevant")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "irrelevant".count) + "RestoreMe")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        assertPage("RestoreMe", in: app)
    }

    @MainActor
    private func launchBrowser() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["CURIO_UI_TEST_ID"] = UUID().uuidString
        app.launch()
        return app
    }

    @MainActor
    private func openPage(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let field = app.textFields["commandBar.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), file: file, line: line)
        // Self-contained pages run through the real address bar and WebKit.
        field.typeText("data:text/html,%3Ctitle%3E\(title)%3C/title%3E\(title)\n")
        assertPage(title, in: app, file: file, line: line)
    }

    @MainActor
    private func assertPage(_ title: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.webViews.staticTexts[title].waitForExistence(timeout: 10), file: file, line: line)
    }

    @MainActor
    private func showSidebar(in app: XCUIApplication) {
        let drawerButton = app.buttons["browser.showTabs"]
        if drawerButton.isHittable { drawerButton.tap() }
        XCTAssertTrue(app.buttons["sidebar.library"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapEnabled(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.wait(for: \.isEnabled, toEqual: true, timeout: 5), file: file, line: line)
        element.tap()
    }
}
