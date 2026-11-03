import UIKit

/// A search field with a leading icon: inline (on the chrome) or floating
/// (the find bar).
final class SearchFieldView: UIView, ThemeObserving {
    let textField = UITextField()
    let trailingStack = UIStackView()
    private let iconView = UIImageView()
    private let floating: Bool

    init(placeholder: String, icon: Icon = .search, floating: Bool = false) {
        self.floating = floating
        super.init(frame: .zero)
        iconView.image = icon.image(13)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        textField.placeholder = placeholder
        textField.font = CurioFont.sm()
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = floating ? .never : .whileEditing
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .search
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 2
        let stack = UIStackView(arrangedSubviews: [iconView, textField, trailingStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = floating ? 6 : 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: floating ? 42 : 34),
        ])
        layer.cornerRadius = floating ? 12 : Metrics.fieldRadius
        layer.cornerCurve = .continuous
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        iconView.tintColor = theme.textFaint.uiColor
        textField.textColor = theme.text.uiColor
        textField.tintColor = theme.accent.uiColor
        textField.attributedPlaceholder = NSAttributedString(
            string: textField.placeholder ?? "",
            attributes: [.foregroundColor: theme.textFaint.uiColor]
        )
        if floating {
            backgroundColor = theme.surfaceRaised.uiColor
            layer.borderWidth = 1
            layer.borderColor = theme.surfaceBorder.uiColor.cgColor
            Shadow.lg.apply(to: layer, dark: theme.appearance == .dark)
        } else {
            backgroundColor = theme.field.uiColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if floating { layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 12).cgPath }
    }
}
