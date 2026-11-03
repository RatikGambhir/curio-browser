import WebKit

/// Shared engine configuration: the isolated content world for Curio's
/// scripts, the session token, and web view setup.
final class WebEngine {
    /// Curio's scripts run here, invisible to page scripts.
    let world = WKContentWorld.world(name: "curio")
    /// A random per-launch token that bridge messages must carry.
    let token = UUID().uuidString
    let dataStore = WKWebsiteDataStore.default()

    /// Builds a configuration for one tab. `handler` receives bridge messages.
    func configuration(handler: WKScriptMessageHandler) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.defaultWebpagePreferences.preferredContentMode = .recommended
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: PageScripts.bridge(token: token),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: world
        ))
        controller.add(ScriptMessageProxy(handler), contentWorld: world, name: "curio")
        configuration.userContentController = controller
        return configuration
    }
}
