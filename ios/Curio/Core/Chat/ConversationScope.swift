import Foundation

/// What a conversation is about.
nonisolated enum ConversationScope: Equatable, Codable, Sendable {
    case none
    case tab(UUID)
    case tabs([UUID])
    case space(UUID)

    private enum CodingKeys: String, CodingKey { case kind, tab, tabs, space }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decodeIfPresent(String.self, forKey: .kind) {
        case "tab": self = .tab(try c.decode(UUID.self, forKey: .tab))
        case "tabs": self = .tabs(try c.decode([UUID].self, forKey: .tabs))
        case "space": self = .space(try c.decode(UUID.self, forKey: .space))
        default: self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode("none", forKey: .kind)
        case .tab(let id):
            try c.encode("tab", forKey: .kind)
            try c.encode(id, forKey: .tab)
        case .tabs(let ids):
            try c.encode("tabs", forKey: .kind)
            try c.encode(ids, forKey: .tabs)
        case .space(let id):
            try c.encode("space", forKey: .kind)
            try c.encode(id, forKey: .space)
        }
    }
}
