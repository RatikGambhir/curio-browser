import UIKit

/// Holds the current theme and tells observers when it changes (a space
/// switch or a new space theme).
final class ThemeCenter {
    static let shared = ThemeCenter()

    private(set) var theme = CurioTheme(gradient: .default)
    private(set) var previous = CurioTheme(gradient: .default)
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

    func apply(gradient: SpaceGradient) {
        let next = CurioTheme(gradient: gradient)
        guard next != theme else { return }
        previous = theme
        theme = next
        for case let observer as ThemeObserving in observers.allObjects {
            observer.themeDidChange(next)
        }
    }
}
