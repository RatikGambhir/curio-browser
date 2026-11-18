import UIKit
import XCTest
@testable import Curio

final class BrowserChromeTests: XCTestCase {
    @MainActor
    func testBottomBarRoutesTheTrailingButtonAccordingToLoadingState() async {
        let bar = BottomBarView()
        var commands: [CurioCommand] = []
        bar.onCommand = { commands.append($0) }

        bar.update(PageNav(), assistantOpen: false)
        XCTAssertTrue(bar.pill.trailingButton.isHidden)
        XCTAssertFalse(bar.backButton.isEnabled)
        XCTAssertFalse(bar.forwardButton.isEnabled)

        let page = PageNav.PageInfo(url: "https://curio.test", host: "curio.test", title: "Curio")
        bar.update(PageNav(canGoBack: true, loading: true, page: page), assistantOpen: false)
        XCTAssertFalse(bar.pill.trailingButton.isHidden)
        XCTAssertTrue(bar.backButton.isEnabled)
        XCTAssertEqual(bar.pill.trailingButton.accessibilityLabel, "Stop")
        bar.pill.trailingButton.sendActions(for: .primaryActionTriggered)

        bar.update(PageNav(canGoForward: true, page: page), assistantOpen: false)
        XCTAssertFalse(bar.backButton.isEnabled)
        XCTAssertTrue(bar.forwardButton.isEnabled)
        XCTAssertEqual(bar.pill.trailingButton.accessibilityLabel, "Reload")
        bar.pill.trailingButton.sendActions(for: .primaryActionTriggered)

        XCTAssertEqual(commands, [.stopLoading, .reload])
    }

    @MainActor
    func testReusedTabRowPublishesTheCurrentCloseActionAndTab() async throws {
        let cell = TabRowCell(frame: .zero)
        var closed: [UUID] = []
        cell.onClose = { closed.append($0.id) }
        var tab = TabViewModel(id: UUID(), title: "Pinned page", url: Curio.newTabURL,
                               active: true, pinned: true, saved: true, loading: false, asleep: false)

        cell.configure(tab, grouped: false, height: 32)
        let unload = try XCTUnwrap(cell.accessibilityCustomActions?.first)
        XCTAssertEqual(unload.name, "Unload Tab")
        XCTAssertTrue(cell.accessibilityTraits.contains(.selected))

        tab.active = false
        tab.asleep = true
        cell.configure(tab, grouped: false, height: 32)
        XCTAssertEqual(cell.accessibilityCustomActions?.map(\.name), ["Archive Tab"])

        cell.prepareForReuse()
        let regular = TabViewModel(id: UUID(), title: "Regular page", url: Curio.newTabURL,
                                   active: false, pinned: false, saved: false, loading: false, asleep: false)
        cell.configure(regular, grouped: false, height: 32)
        XCTAssertEqual(cell.accessibilityLabel, regular.title)
        XCTAssertFalse(cell.accessibilityTraits.contains(.selected))
        let close = try XCTUnwrap(cell.accessibilityCustomActions?.first)
        XCTAssertEqual(close.name, "Close Tab")
        let handler = try XCTUnwrap(close.actionHandler)
        XCTAssertTrue(handler(close))
        XCTAssertEqual(closed, [regular.id])
    }
}
