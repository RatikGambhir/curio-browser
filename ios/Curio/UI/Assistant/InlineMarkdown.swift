import UIKit

/// Renders inline Markdown (bold, italics, code spans, links) into an
/// attributed string in Curio's fonts and colors.
enum InlineMarkdown {
    static func render(_ text: String, font: UIFont, color: UIColor, codeBackground: UIColor, linkColor: UIColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        let parsed = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        let output = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if let intent = run.inlinePresentationIntent {
                var traits: UIFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                if intent.contains(.code) {
                    attributes[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular)
                    attributes[.backgroundColor] = codeBackground
                } else if !traits.isEmpty, let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                    attributes[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
                }
                if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = linkColor
            }
            output.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return output
    }
}
