import UIKit

/// A command bar result row.
final class CommandRowCell: UICollectionViewListCell {
    private let row = ListRowView(height: 46)
    private let iconBox = UIView()
    private let iconView = UIImageView()
    private let favicon = FaviconView(size: 18)
    private let badge = UILabel()
    private let returnIcon = UIImageView(image: Icon.returnKey.image(10))
    var onHover: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        iconBox.layer.cornerRadius = 7
        iconBox.layer.cornerCurve = .continuous
        iconView.contentMode = .center
        iconView.translatesAutoresizingMaskIntoConstraints = false
        favicon.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)
        iconBox.addSubview(favicon)
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 26),
            iconBox.heightAnchor.constraint(equalToConstant: 26),
            iconView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            favicon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            favicon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
        ])
        row.setLeading(iconBox)
        row.setSpacing(12)
        row.layer.cornerRadius = 9
        row.selectedStyle = .subtle
        row.titleWeight = .medium
        badge.font = CurioFont.xs()
        badge.setContentHuggingPriority(.required, for: .horizontal)
        returnIcon.contentMode = .center
        returnIcon.setContentHuggingPriority(.required, for: .horizontal)
        returnIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.trailingStack.addArrangedSubview(badge)
        row.trailingStack.addArrangedSubview(returnIcon)
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        HoverTracker(self) { [weak self] inside in
            if inside { self?.onHover?() }
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ item: CommandItem, selected: Bool) {
        let theme = ThemeCenter.shared.theme
        row.setTitle(item.title, subtitle: item.subtitle)
        row.isSelected = selected
        switch item.leading {
        case .icon(let icon):
            iconView.image = icon.image(13)
            iconView.isHidden = false
            favicon.isHidden = true
            iconBox.backgroundColor = (selected ? theme.accentSoft : theme.rowHover).uiColor
            iconView.tintColor = (selected ? theme.accentText : theme.textMuted).uiColor
        case .site(let url, let label):
            iconView.isHidden = true
            favicon.isHidden = false
            favicon.configure(label: label, url: url)
            iconBox.backgroundColor = .clear
        }
        badge.text = item.badge
        badge.textColor = (selected ? theme.accentText : theme.textFaint).uiColor
        returnIcon.tintColor = theme.accentText.uiColor
        returnIcon.isHidden = !selected
        accessibilityLabel = [item.title, item.subtitle, item.badge].compactMap(\.self).joined(separator: ", ")
        accessibilityTraits = selected ? [.button, .selected] : .button
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        favicon.prepareForReuse()
    }
}
