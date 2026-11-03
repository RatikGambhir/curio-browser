import UIKit

/// Events from a tab's page to the browser.
protocol BrowserTabDelegate: AnyObject {
    func tabStateDidChange(_ tab: BrowserTab)
    func tab(_ tab: BrowserTab, didNavigateTo url: String)
    func tab(_ tab: BrowserTab, didFinishLoading url: String, title: String)
    func tab(_ tab: BrowserTab, openInNewTab url: String, background: Bool)
    func tab(_ tab: BrowserTab, wantsToOpenExternally url: URL)
    func tabSelectionDidChange(_ tab: BrowserTab)
    func tab(_ tab: BrowserTab, didScrollTo y: Double)
    func tab(_ tab: BrowserTab, didStartDownload url: String, fileName: String) -> UUID
    func tab(_ tab: BrowserTab, didFinishDownload id: UUID, fileName: String?, success: Bool)
    func tab(_ tab: BrowserTab, askAboutSelection action: QuickAction?)
    func tab(_ tab: BrowserTab, present alert: UIAlertController)
}
