import UIKit

/// A two-line row with a site icon, used by history, downloads and the
/// library.
final class PageRowCell: UICollectionViewListCell {
    private let row = ListRowView(height: 44)
    private let favicon = FaviconView(size: 16)
    private let iconView = UIImageView()
    private let trailing = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        let leading = UIView()
        favicon.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .center
        leading.addSubview(favicon)
        leading.addSubview(iconView)
        NSLayoutConstraint.activate([
            leading.widthAnchor.constraint(equalToConstant: 18),
            leading.heightAnchor.constraint(equalToConstant: 18),
            favicon.centerXAnchor.constraint(equalTo: leading.centerXAnchor),
            favicon.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
            iconView.centerXAnchor.constraint(equalTo: leading.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: leading.centerYAnchor),
        ])
        row.setLeading(leading)
        trailing.spacing = 4
        row.trailingStack.addArrangedSubview(trailing)
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

    func configure(title: String, subtitle: String?, faviconLabel: String, favicon url: String?, icon: Icon? = nil,
                   iconColor: UIColor? = nil, trailing views: [UIView] = []) {
        row.setTitle(title, subtitle: subtitle)
        if let icon {
            iconView.image = icon.image(14)
            iconView.tintColor = iconColor
            iconView.isHidden = false
            favicon.isHidden = true
        } else {
            iconView.isHidden = true
            favicon.isHidden = false
            favicon.configure(label: faviconLabel, url: url)
        }
        trailing.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { trailing.addArrangedSubview($0) }
        accessibilityLabel = [title, subtitle].compactMap(\.self).joined(separator: ", ")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        favicon.prepareForReuse()
    }

    override var isHighlighted: Bool {
        didSet { row.isPressed = isHighlighted }
    }
}
