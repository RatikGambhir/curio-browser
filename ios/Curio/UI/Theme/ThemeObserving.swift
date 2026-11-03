import UIKit

/// A view or controller that restyles itself when the theme changes.
protocol ThemeObserving: AnyObject {
    func themeDidChange(_ theme: CurioTheme)
}
