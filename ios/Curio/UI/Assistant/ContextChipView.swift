import UIKit

/// A page attached to the next message, with a remove button.
final class ContextChipView: TapControl {
    private let label = UILabel()
    private let removeButton = UIButton(type: .system)
    private var stack = UIStackView()
    private var trailingInset: CGFloat = 6

    init(title: String, leading: UIView, active: Bool, removable: Bool, tooltip: String? = nil, onRemove: (() -> Void)? = nil) {
        super.init(frame: .zero)
        let theme = ThemeCenter.shared.theme
        label.text = title
        label.font = CurioFont.xs()
        label.lineBreakMode = .byTruncatingTail
        label.textColor = (active ? theme.accentText : theme.textMuted).uiColor
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
        removeButton.setImage(Icon.close.image(9, weight: .semibold), for: .normal)
        removeButton.tintColor = label.textColor
        removeButton.accessibilityLabel = "Remove \(title)"
        removeButton.isHidden = !removable
        if let onRemove { removeButton.addAction(UIAction { _ in onRemove() }, for: .primaryActionTriggered) }
        leading.tintColor = label.textColor
        trailingInset = removable ? 2 : 6
        stack = UIStackView(arrangedSubviews: [leading, label, removeButton])
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: removable ? -2 : -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        backgroundColor = (active ? theme.accentSoft : theme.surfaceRaised).uiColor
        layer.borderColor = (active ? theme.accentSoft : theme.surfaceBorder).uiColor.cgColor
        toolTip = tooltip
        accessibilityLabel = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Sized from the content stack (asking the chip itself would recurse).
    override var intrinsicContentSize: CGSize {
        let content = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: ceil(content.width) + 6 + trailingInset, height: 26)
    }
}
