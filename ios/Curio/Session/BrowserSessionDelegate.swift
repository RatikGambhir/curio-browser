import UIKit

/// The UI side of the session: refreshes and requests the session cannot
/// handle on its own.
protocol BrowserSessionDelegate: AnyObject {
    func session(_ session: BrowserSession, didChange change: SessionChange)
    func session(_ session: BrowserSession, showToast message: String, title: String?, kind: ToastPresenter.Kind)
    func session(_ session: BrowserSession, confirmExternalOpen url: URL)
    func session(_ session: BrowserSession, present alert: UIAlertController)
    func session(_ session: BrowserSession, askAboutSelection action: QuickAction?)
}
