import UIKit

/// Holds the current theme and tells observers when it changes (a space
/// switch, a new accent, or light/dark).
final class ThemeCenter {
    static let shared = ThemeCenter()

    private(set) var theme = CurioTheme(accent: .iris, appearance: .light)
    private(set) var previous = CurioTheme(accent: .iris, appearance: .light)
    private let observers = NSHashTable<AnyObject>.weakObjects()
    /// Whether animations should be skipped (the setting or the system's
    /// Reduce Motion).
    var reduceMotion = false

    var motionEnabled: Bool { !reduceMotion && !UIAccessibility.isReduceMotionEnabled }

    /// Registers an observer and styles it right away.
    func observe(_ observer: ThemeObserving) {
        observers.add(observer)
        observer.themeDidChange(theme)
    }

    func apply(accent: AccentColor, appearance: Appearance) {
        let next = CurioTheme(accent: accent, appearance: appearance)
        guard next != theme else { return }
        previous = theme
        theme = next
        for case let observer as ThemeObserving in observers.allObjects {
            observer.themeDidChange(next)
        }
    }
}
