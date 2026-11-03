import Foundation

/// Requests from the assistant to the browser.
protocol AssistantDelegate: AnyObject {
    func assistantDidClose()
    func assistantOpenSettings()
    func assistantOpenURL(_ url: URL)
}
