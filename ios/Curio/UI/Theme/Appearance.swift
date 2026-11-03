import UIKit

/// Whether the interface renders light or dark.
nonisolated enum Appearance: Sendable {
    case light
    case dark

    /// Resolves the theme setting against the system appearance.
    static func resolve(_ mode: ThemeMode, system: UIUserInterfaceStyle) -> Appearance {
        switch mode {
        case .light: .light
        case .dark: .dark
        case .system: system == .dark ? .dark : .light
        }
    }

    var interfaceStyle: UIUserInterfaceStyle { self == .dark ? .dark : .light }
}
