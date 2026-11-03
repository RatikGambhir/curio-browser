import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    /// Created once per launch and shared with the browser scene.
    let services = AppServices()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    /// The menu bar on iPad and keyboard shortcuts everywhere.
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        MainMenuBuilder(keybindings: services.settings.settings.keybindings).build(builder)
    }
}
