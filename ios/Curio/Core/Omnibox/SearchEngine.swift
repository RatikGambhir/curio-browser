import Foundation

/// A web search provider used for address bar searches.
nonisolated enum SearchEngine: Hashable, Codable, Sendable {
    case google
    case duckDuckGo
    case bing
    case brave
    case kagi
    case ecosia
    /// A URL template with `%s` where the query goes.
    case custom(String)

    static let builtIn: [SearchEngine] = [.google, .duckDuckGo, .bing, .brave, .kagi, .ecosia]

    var label: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .kagi: "Kagi"
        case .ecosia: "Ecosia"
        case .custom: "Custom"
        }
    }

    private var template: String {
        switch self {
        case .google: "https://www.google.com/search?q=%s"
        case .duckDuckGo: "https://duckduckgo.com/?q=%s"
        case .bing: "https://www.bing.com/search?q=%s"
        case .brave: "https://search.brave.com/search?q=%s"
        case .kagi: "https://kagi.com/search?q=%s"
        case .ecosia: "https://www.ecosia.org/search?q=%s"
        case .custom(let template): template
        }
    }

    /// Only ASCII letters and digits are left unescaped.
    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// The search URL for `query`. A custom template without `%s` falls back
    /// to Google.
    func searchURL(for query: String) -> String {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? query
        guard template.contains("%s") else { return SearchEngine.google.searchURL(for: query) }
        return template.replacingOccurrences(of: "%s", with: encoded)
    }

    private enum CodingKeys: String, CodingKey { case kind, template }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "duck_duck_go": self = .duckDuckGo
        case "bing": self = .bing
        case "brave": self = .brave
        case "kagi": self = .kagi
        case "ecosia": self = .ecosia
        case "custom": self = .custom(try c.decodeIfPresent(String.self, forKey: .template) ?? "")
        default: self = .google
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let kind = switch self {
        case .google: "google"
        case .duckDuckGo: "duck_duck_go"
        case .bing: "bing"
        case .brave: "brave"
        case .kagi: "kagi"
        case .ecosia: "ecosia"
        case .custom: "custom"
        }
        try c.encode(kind, forKey: .kind)
        if case .custom(let template) = self { try c.encode(template, forKey: .template) }
    }
}
