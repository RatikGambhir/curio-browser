import UIKit

/// A keyboard shortcut hint ("⌘T").
final class KbdLabel: UIView, ThemeObserving {
    private let label = UILabel()

    init(_ keys: String) {
        super.init(frame: .zero)
        label.text = keys
        label.font = CurioFont.xs()
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        layer.cornerRadius = 4
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setKeys(_ keys: String) { label.text = keys }

    func themeDidChange(_ theme: CurioTheme) {
        backgroundColor = theme.rowHover.uiColor
        label.textColor = theme.textFaint.uiColor
    }
}
