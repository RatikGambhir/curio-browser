import UIKit

/// A tab folder: chevron, colored folder icon, name and (collapsed) count.
final class GroupRowCell: UICollectionViewListCell {
    let row = ListRowView()
    private let chevron = UIImageView()
    private let folder = UIImageView()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        chevron.contentMode = .center
        folder.contentMode = .center
        let leading = UIStackView(arrangedSubviews: [chevron, folder])
        leading.spacing = 8
        leading.alignment = .center
        NSLayoutConstraint.activate([chevron.widthAnchor.constraint(equalToConstant: 16), folder.widthAnchor.constraint(equalToConstant: 18)])
        row.muted = true
        row.titleWeight = .medium
        row.setSpacing(8)
        row.setLeading(leading)
        countLabel.font = CurioFont.xs()
        row.trailingStack.addArrangedSubview(countLabel)
        row.onRestyle = { [weak self] theme, _ in
            self?.countLabel.textColor = theme.textFaint.uiColor
            self?.chevron.tintColor = theme.textMuted.uiColor
        }
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
        ])
        HoverTracker(self) { [weak self] in self?.row.isHovered = $0 }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ group: TabGroup, height: CGFloat) {
        row.setHeight(height)
        row.setTitle(group.name)
        chevron.image = (group.collapsed ? Icon.chevronRight : Icon.chevronDown).image(10, weight: .semibold)
        folder.image = (group.collapsed ? Icon.folder : Icon.folderFill).image(13)
        folder.tintColor = CurioTheme.swatch(group.color)
        countLabel.text = "\(group.tabs.count)"
        countLabel.isHidden = !group.collapsed
        chevron.tintColor = ThemeCenter.shared.theme.textMuted.uiColor
        countLabel.textColor = ThemeCenter.shared.theme.textFaint.uiColor
        accessibilityLabel = "\(group.name) folder, \(group.tabs.count) tabs"
        accessibilityValue = group.collapsed ? "Collapsed" : "Expanded"
    }

    override var isHighlighted: Bool {
        didSet { row.isPressed = isHighlighted }
    }
}
