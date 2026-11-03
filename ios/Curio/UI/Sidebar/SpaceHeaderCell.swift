import UIKit

/// The active space's icon and name, with its menu.
final class SpaceHeaderCell: UICollectionViewCell, ThemeObserving {
    private let iconLabel = UILabel()
    private let nameLabel = UILabel()
    let menuButton = IconButton(.ellipsis, size: .small, label: "Space Options")

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconLabel.font = .systemFont(ofSize: 15)
        iconLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.font = CurioFont.sm(.semibold)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.accessibilityTraits = .header
        menuButton.showsMenuAsPrimaryAction = true
        let stack = UIStackView(arrangedSubviews: [iconLabel, nameLabel, menuButton])
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ space: Space, menu: UIMenu) {
        iconLabel.text = space.icon
        nameLabel.text = space.name
        menuButton.menu = menu
    }

    func themeDidChange(_ theme: CurioTheme) {
        nameLabel.textColor = theme.text.uiColor
    }
}
