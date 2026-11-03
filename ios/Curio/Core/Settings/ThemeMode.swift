import Foundation

/// Light, dark, or following the system.
nonisolated enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var label: String { rawValue.capitalized }
}
