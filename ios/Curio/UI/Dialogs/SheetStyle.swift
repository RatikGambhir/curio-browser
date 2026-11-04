import UIKit

/// Presents secondary screens the way each size class expects: a centered
/// form sheet on wide screens, a resizable sheet on phones.
enum SheetStyle {
    static func wrap(_ controller: UIViewController, compact: Bool, size: CGSize, detents: [UISheetPresentationController.Detent] = [.large()]) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: controller)
        let theme = ThemeCenter.shared.theme
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = theme.surface.uiColor
        appearance.shadowColor = theme.divider.uiColor
        appearance.titleTextAttributes = [.foregroundColor: theme.text.uiColor, .font: CurioFont.base(.semibold)]
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.tintColor = theme.accentText.uiColor
        if compact {
            navigation.modalPresentationStyle = .pageSheet
            if let sheet = navigation.sheetPresentationController {
                sheet.detents = detents
                sheet.prefersGrabberVisible = detents.count > 1
                sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            }
        } else {
            navigation.modalPresentationStyle = .formSheet
            navigation.preferredContentSize = size
        }
        return navigation
    }
}
