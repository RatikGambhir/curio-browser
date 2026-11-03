import Foundation

/// A curated accent palette shared by spaces and tab groups. The UI derives
/// light and dark tints from `rgb`.
nonisolated enum AccentColor: String, Codable, CaseIterable, Sendable {
    /// Curio's signature violet.
    case iris
    case ocean
    case lagoon
    case sage
    case citrine
    case amber
    case coral
    case rose
    case plum
    case graphite

    /// The base color as `0xRRGGBB`.
    var rgb: UInt32 {
        switch self {
        case .iris: 0x6E5BF5
        case .ocean: 0x2F7CF6
        case .lagoon: 0x12A5B5
        case .sage: 0x3E9E6B
        case .citrine: 0xC9A317
        case .amber: 0xE58A1F
        case .coral: 0xEC5F4E
        case .rose: 0xDF4A86
        case .plum: 0x9A4BD0
        case .graphite: 0x5E6673
        }
    }

    /// A display name for menus and settings.
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The accent following this one in palette order, wrapping around.
    var next: AccentColor {
        let all = AccentColor.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
