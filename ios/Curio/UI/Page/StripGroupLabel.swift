import UIKit

/// A group's colored label in the horizontal tab strip; tapping folds it.
final class StripGroupLabel: TapControl, ThemeObserving {
    let groupID: UUID
    private let label = UILabel()
    private let count = UILabel()
    private let color: UIColor

    init(group: TabGroup) {
        groupID = group.id
        color = CurioTheme.swatch(group.color)
        super.init(frame: .zero)
        let dot = ColorDotView(color: color, diameter: 7)
        label.text = group.name
        label.font = CurioFont.xs(.semibold)
        count.text = "\(group.tabs.count)"
        count.font = CurioFont.xs(.semibold)
        count.isHidden = !group.collapsed
        let stack = UIStackView(arrangedSubviews: [dot, label, count])
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        backgroundColor = color.withAlphaComponent(0.18)
        setContentHuggingPriority(.required, for: .horizontal)
        isAccessibilityElement = true
        accessibilityLabel = "\(group.name) group"
        accessibilityValue = group.collapsed ? "Collapsed" : "Expanded"
        accessibilityTraits = .button
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        label.textColor = theme.text.uiColor
        count.textColor = theme.textFaint.uiColor
    }
}
