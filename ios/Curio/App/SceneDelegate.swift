import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var browser: BrowserViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene,
              let app = UIApplication.shared.delegate as? AppDelegate else { return }
        let window = UIWindow(windowScene: windowScene)
        let browser = BrowserViewController(services: app.services)
        window.rootViewController = browser
        window.makeKeyAndVisible()
        self.window = window
        self.browser = browser
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 320, height: 480)
        open(connectionOptions.urlContexts)
    }

    /// Web links handed to Curio by other apps open in a new tab.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        open(contexts)
    }

    private func open(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts where context.url.scheme?.hasPrefix("http") == true {
            browser?.session.openInNewTab(context.url.absoluteString)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        browser?.session.saveNow()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        browser?.session.saveNow()
    }
}
