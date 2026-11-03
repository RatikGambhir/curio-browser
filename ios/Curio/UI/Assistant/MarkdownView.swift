import UIKit

/// Renders a Markdown answer as native views. While streaming, only blocks
/// that changed are rebuilt.
final class MarkdownView: UIView, UITextViewDelegate {
    private let stack = UIStackView()
    private var blocks: [MarkdownBlock] = []
    private var theme = ThemeCenter.shared.theme
    private var textColor = ThemeCenter.shared.theme.text.uiColor
    var onLink: ((URL) -> Void)?

    init() {
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func render(_ markdown: String, theme: CurioTheme, color: UIColor) {
        let next = MarkdownParser.parse(markdown)
        let restyle = theme != self.theme || color != textColor
        self.theme = theme
        textColor = color
        let firstChange = restyle ? 0 : zip(blocks, next).prefix { $0 == $1 }.count
        guard restyle || firstChange < max(blocks.count, next.count) else { return }
        for view in stack.arrangedSubviews.dropFirst(firstChange) { view.removeFromSuperview() }
        for block in next.dropFirst(firstChange) { stack.addArrangedSubview(view(for: block)) }
        blocks = next
    }

    private func textView(_ text: NSAttributedString) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.attributedText = text
        view.delegate = self
        view.linkTextAttributes = [.foregroundColor: theme.accentText.uiColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.adjustsFontForContentSizeCategory = true
        return view
    }

    private func inline(_ text: String, font: UIFont, color: UIColor? = nil) -> NSAttributedString {
        InlineMarkdown.render(text, font: font, color: color ?? textColor,
                              codeBackground: theme.rowHover.uiColor, linkColor: theme.accentText.uiColor)
    }

    private func view(for block: MarkdownBlock) -> UIView {
        switch block {
        case .paragraph(let text):
            return textView(inline(text, font: CurioFont.sm()))
        case .heading(let level, let text):
            let size: CGFloat = level == 1 ? 18 : level == 2 ? 16 : 14
            let view = textView(inline(text, font: CurioFont.size(size, .semibold)))
            view.accessibilityTraits.insert(.header)
            return view
        case .code(let language, let code):
            let view = CodeBlockView()
            view.configure(language: language, code: code, theme: theme)
            return view
        case .quote(let text):
            let bar = UIView()
            bar.backgroundColor = theme.divider.uiColor
            bar.widthAnchor.constraint(equalToConstant: 3).isActive = true
            let body = textView(inline(text, font: CurioFont.sm(), color: theme.textMuted.uiColor))
            let row = UIStackView(arrangedSubviews: [bar, body])
            row.spacing = 10
            return row
        case .list(let ordered, let items, let start):
            let column = UIStackView()
            column.axis = .vertical
            column.spacing = 4
            for (offset, item) in items.enumerated() {
                let marker = UILabel()
                marker.text = ordered ? "\(start + offset)." : "•"
                marker.font = CurioFont.sm(ordered ? .medium : .bold)
                marker.textColor = theme.textMuted.uiColor
                marker.textAlignment = .right
                marker.widthAnchor.constraint(equalToConstant: ordered ? 22 : 12).isActive = true
                marker.setContentHuggingPriority(.required, for: .horizontal)
                let body = textView(inline(item, font: CurioFont.sm()))
                let row = UIStackView(arrangedSubviews: [marker, body])
                row.spacing = 8
                row.alignment = .firstBaseline
                column.addArrangedSubview(row)
            }
            return column
        case .table(let rows):
            let text = NSMutableAttributedString()
            for (index, row) in rows.enumerated() {
                let line = row.joined(separator: "   │   ")
                text.append(inline(line + (index < rows.count - 1 ? "\n" : ""), font: index == 0 ? CurioFont.sm(.semibold) : CurioFont.sm()))
            }
            let scroll = UIScrollView()
            scroll.showsHorizontalScrollIndicator = false
            let body = textView(text)
            body.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(body)
            NSLayoutConstraint.activate([
                body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
                body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
                scroll.heightAnchor.constraint(equalTo: body.heightAnchor),
            ])
            return scroll
        case .rule:
            let line = UIView()
            line.backgroundColor = theme.divider.uiColor
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            return line
        }
    }

    /// Links in answers open in a new tab.
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content else { return defaultAction }
        return UIAction { [weak self] _ in self?.onLink?(url) }
    }
}
