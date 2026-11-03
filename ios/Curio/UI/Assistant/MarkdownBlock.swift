import Foundation

/// A block of Markdown: what the assistant's answers are made of.
nonisolated enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String, text: String)
    case quote(String)
    case list(ordered: Bool, items: [String], start: Int)
    case table([[String]])
    case rule
}
