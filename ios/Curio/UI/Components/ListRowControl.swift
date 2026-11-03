import UIKit

/// A tappable `ListRowView` for lists outside collection views.
final class ListRowControl: TapControl {
    let row: ListRowView

    init(height: CGFloat? = nil, action: UIAction? = nil) {
        row = ListRowView(height: height)
        super.init(frame: .zero)
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if let action { addAction(action, for: .primaryActionTriggered) }
        isAccessibilityElement = true
        accessibilityTraits = .button
        HoverTracker(self) { [weak self] in self?.row.isHovered = $0 }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool {
        didSet { row.isPressed = isHighlighted }
    }

    override var isSelected: Bool {
        didSet {
            row.isSelected = isSelected
            accessibilityTraits = isSelected ? [.button, .selected] : .button
        }
    }

    override var accessibilityLabel: String? {
        get { [row.titleLabel.text, row.subtitleLabel.isHidden ? nil : row.subtitleLabel.text].compactMap(\.self).joined(separator: ", ") }
        set { super.accessibilityLabel = newValue }
    }
}
