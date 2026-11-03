import UIKit

/// A floating bar of assistant actions for the selected text.
final class SelectionActionsView: UIView, ThemeObserving {
    private let sparkle = UIImageView(image: Icon.sparkles.image(11))
    private let preview = UILabel()
    private let divider = DividerView(vertical: true)
    var onAction: ((QuickAction?) -> Void)?

    init() {
        super.init(frame: .zero)
        preview.font = CurioFont.xs()
        preview.lineBreakMode = .byTruncatingTail
        preview.widthAnchor.constraint(lessThanOrEqualToConstant: 170).isActive = true
        let quote = UIStackView(arrangedSubviews: [sparkle, preview])
        quote.spacing = 6
        quote.alignment = .center
        quote.isLayoutMarginsRelativeArrangement = true
        quote.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        let chips: [UIView] = [
            ChipButton("Explain", icon: .lightbulb, action: UIAction { [weak self] _ in self?.onAction?(.explainSelection) }),
            ChipButton("Summarize", icon: .fileText, action: UIAction { [weak self] _ in self?.onAction?(.summarizeSelection) }),
            ChipButton("Translate", icon: .translate, action: UIAction { [weak self] _ in self?.onAction?(.translateSelection(language: "")) }),
            ChipButton("Ask…", icon: .message, action: UIAction { [weak self] _ in self?.onAction?(nil) }),
        ]
        let stack = UIStackView(arrangedSubviews: [quote, divider] + chips)
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            divider.heightAnchor.constraint(equalToConstant: 18),
        ])
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows a short preview of the selection; narrow screens hide it.
    func update(selection: String, compact: Bool) {
        let words = selection.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        preview.text = "“\(words.prefix(42))”"
        preview.superview?.isHidden = compact
        divider.isHidden = compact
    }

    func themeDidChange(_ theme: CurioTheme) {
        backgroundColor = theme.surfaceRaised.uiColor
        layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        Shadow.xl.apply(to: layer, dark: theme.appearance == .dark)
        sparkle.tintColor = theme.accentText.uiColor
        preview.textColor = theme.textFaint.uiColor
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath
    }
}
