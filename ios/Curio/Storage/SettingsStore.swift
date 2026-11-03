import Foundation

/// The user's preferences, persisted as JSON, with change observers.
final class SettingsStore {
    private let file = JSONFile<Settings>("settings.json")
    private var observers: [(owner: WeakBox, handler: (Settings) -> Void)] = []

    private(set) var settings: Settings

    init() {
        settings = (file.load() ?? Settings()).sanitized()
    }

    /// Applies a change, saves, and notifies observers.
    func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        next = next.sanitized()
        guard next != settings else { return }
        settings = next
        file.save(next)
        observers.removeAll { $0.owner.value == nil }
        for observer in observers { observer.handler(next) }
    }

    /// Calls `handler` after every change while `owner` is alive.
    func observe(_ owner: AnyObject, _ handler: @escaping (Settings) -> Void) {
        observers.append((WeakBox(owner), handler))
    }
}
