import Foundation

/// A named, colored folder of tabs inside a space.
nonisolated struct TabGroup: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var color: AccentColor
    var collapsed: Bool
    var tabs: [UUID]

    init(name: String = "New Group", color: AccentColor = .iris) {
        id = UUID()
        self.name = name
        self.color = color
        collapsed = false
        tabs = []
    }
}
