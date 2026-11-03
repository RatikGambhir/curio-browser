import UIKit

/// A bordered text field in Curio's style, for settings and dialogs.
final class CurioTextField: UITextField, ThemeObserving {
    init(placeholder: String, text: String? = nil, secure: Bool = false) {
        super.init(frame: .zero)
        self.placeholder = placeholder
        self.text = text
        isSecureTextEntry = secure
        font = CurioFont.sm()
        adjustsFontForContentSizeCategory = true
        borderStyle = .none
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        clearButtonMode = .whileEditing
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func textRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: 10, dy: 4) }
    override func editingRect(forBounds bounds: CGRect) -> CGRect { bounds.insetBy(dx: 10, dy: 4) }

    func setPlaceholder(_ text: String) {
        placeholder = text
        themeDidChange(ThemeCenter.shared.theme)
    }

    func themeDidChange(_ theme: CurioTheme) {
        backgroundColor = theme.surfaceRaised.uiColor
        layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        textColor = theme.text.uiColor
        tintColor = theme.accent.uiColor
        attributedPlaceholder = NSAttributedString(string: placeholder ?? "", attributes: [.foregroundColor: theme.textFaint.uiColor])
    }
}
