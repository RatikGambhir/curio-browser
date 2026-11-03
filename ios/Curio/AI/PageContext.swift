import Foundation

/// Content extracted from one tab for the assistant.
nonisolated struct PageContext: Codable, Equatable, Sendable {
    var title = ""
    var url = ""
    /// `<meta name="description">` or Open Graph description.
    var description = ""
    /// Main readable text of the page.
    var text = ""
    /// Text the user had selected, if any.
    var selection = ""
    /// Site name, author, published date and similar metadata.
    var metadata: [[String]] = []

    init(title: String = "", url: String = "", text: String = "") {
        self.title = title
        self.url = url
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        selection = try c.decodeIfPresent(String.self, forKey: .selection) ?? ""
        metadata = (try? c.decodeIfPresent([[String]].self, forKey: .metadata)) ?? []
    }
}
