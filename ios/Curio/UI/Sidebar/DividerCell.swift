import UIKit

/// The pinned/regular boundary line (a drop target for pinning) and the New
/// Tab row.
final class DividerCell: UICollectionViewListCell, ThemeObserving {
    private let line = UIView()
    let newTabRow = ListRowView()
    private let plus = UIImageView(image: Icon.plus.image(12))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        line.translatesAutoresizingMaskIntoConstraints = false
        newTabRow.translatesAutoresizingMaskIntoConstraints = false
        newTabRow.muted = true
        newTabRow.setTitle("New Tab")
        plus.contentMode = .center
        plus.widthAnchor.constraint(equalToConstant: 16).isActive = true
        newTabRow.setLeading(plus)
        newTabRow.onRestyle = { [weak self] theme, _ in self?.plus.tintColor = theme.textMuted.uiColor }
        contentView.addSubview(line)
        contentView.addSubview(newTabRow)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            line.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            line.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            line.heightAnchor.constraint(equalToConstant: 1),
            newTabRow.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 6),
            newTabRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            newTabRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            newTabRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
        ])
        HoverTracker(newTabRow) { [weak self] in self?.newTabRow.isHovered = $0 }
        isAccessibilityElement = true
        accessibilityLabel = "New Tab"
        accessibilityTraits = .button
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(hasPinned: Bool, height: CGFloat, dropHighlight: Bool = false) {
        newTabRow.setHeight(height)
        line.alpha = hasPinned ? 1 : 0.6
        let theme = ThemeCenter.shared.theme
        line.backgroundColor = (dropHighlight ? theme.accent : theme.divider).uiColor
    }

    func themeDidChange(_ theme: CurioTheme) {
        line.backgroundColor = theme.divider.uiColor
    }

    override var isHighlighted: Bool {
        didSet { newTabRow.isPressed = isHighlighted }
    }
}
