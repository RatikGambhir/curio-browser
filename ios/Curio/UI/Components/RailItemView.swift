import UIKit

/// A library rail button: icon above a short label.
final class RailItemView: TapControl, ThemeObserving {
    private let iconView = UIImageView()
    private let label = UILabel()
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false

    init(icon: Icon, title: String, action: UIAction) {
        super.init(frame: .zero)
        iconView.image = icon.image(20, weight: .regular)
        iconView.contentMode = .center
        label.text = title
        label.font = CurioFont.xs(.medium)
        label.textAlignment = .center
        label.numberOfLines = 2
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        addAction(action, for: .primaryActionTriggered)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isSelected: Bool { didSet { restyle() } }
    override var isHighlighted: Bool { didSet { restyle() } }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        iconView.tintColor = theme.accentText.uiColor
        layer.borderWidth = isSelected ? 1 : 0
        layer.borderColor = theme.rowActiveBorder.uiColor.cgColor
        if isSelected {
            backgroundColor = theme.rowActive.uiColor
            label.textColor = theme.rowActiveText.uiColor
        } else {
            backgroundColor = (pointerInside || isHighlighted) ? theme.rowHover.uiColor : .clear
            label.textColor = (pointerInside || isHighlighted) ? theme.text.uiColor : theme.textMuted.uiColor
        }
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
