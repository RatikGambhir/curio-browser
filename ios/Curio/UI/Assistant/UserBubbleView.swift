import UIKit

/// A user message: a tinted bubble on the right with the shared pages below.
final class UserBubbleView: UIView {
    private let bubble = UIView()
    private let text = MarkdownView()
    private let bubbleMask = CAShapeLayer()

    init(message: ChatMessage, theme: CurioTheme) {
        super.init(frame: .zero)
        bubble.backgroundColor = theme.userBubble.uiColor
        bubble.layer.mask = bubbleMask
        text.render(message.content, theme: theme, color: theme.userBubbleText.uiColor)
        text.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(text)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)
        let chips = FlowLayoutView()
        chips.spacing = 4
        chips.lineSpacing = 4
        chips.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chips)
        var views: [UIView] = message.context.prefix(6).map { ref in
            let favicon = FaviconView(size: 12)
            favicon.configure(label: Curio.displayHost(ref.url), url: ref.faviconURL)
            return ContextChipView(title: ref.title, leading: favicon, active: false, removable: false, tooltip: ref.url)
        }
        if message.context.count > 6 {
            let more = UILabel()
            more.text = "+\(message.context.count - 6)"
            more.font = CurioFont.xs()
            more.textColor = theme.textFaint.uiColor
            views.append(more)
        }
        chips.setItems(views)
        chips.isHidden = views.isEmpty
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.88),
            text.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            text.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            chips.topAnchor.constraint(equalTo: bubble.bottomAnchor, constant: views.isEmpty ? 0 : 6),
            chips.leadingAnchor.constraint(equalTo: leadingAnchor),
            chips.trailingAnchor.constraint(equalTo: trailingAnchor),
            chips.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        chips.centered = false
        chips.semanticContentAttribute = .forceRightToLeft
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Rounded 14pt, with a tighter 4pt corner at the bottom right.
    override func layoutSubviews() {
        super.layoutSubviews()
        let rect = bubble.bounds
        let r: CGFloat = 14
        let small: CGFloat = 4
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - small))
        path.addArc(withCenter: CGPoint(x: rect.maxX - small, y: rect.maxY - small), radius: small, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(withCenter: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .pi, endAngle: -.pi / 2, clockwise: true)
        path.close()
        bubbleMask.path = path.cgPath
    }
}
