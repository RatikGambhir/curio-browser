import Foundation

/// A top-level entry of a section: a tab or a group.
nonisolated enum TabItem: Hashable, Codable, Sendable {
    case tab(UUID)
    case group(UUID)

    private enum CodingKeys: String, CodingKey { case kind, id }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        switch try c.decode(String.self, forKey: .kind) {
        case "group": self = .group(id)
        default: self = .tab(id)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tab(let id):
            try c.encode("tab", forKey: .kind)
            try c.encode(id, forKey: .id)
        case .group(let id):
            try c.encode("group", forKey: .kind)
            try c.encode(id, forKey: .id)
        }
    }
}
