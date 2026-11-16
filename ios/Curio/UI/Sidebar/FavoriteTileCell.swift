import UIKit

/// A favorite in the sidebar's grid: the site icon on a rounded tile.
final class FavoriteTileCell: UICollectionViewCell, ThemeObserving {
    private static let tileRadius: CGFloat = 10
    private let tile = UIView()
    private let favicon = FaviconView(size: 18)
    private let plusIcon = UIImageView(image: Icon.plus.image())
    private let dashedBorder = CAShapeLayer()
    private var theme = ThemeCenter.shared.theme
    private var active = false
    private var isAddSlot = false
    private var pointerInside = false
    private let toolTipInteraction = UIToolTipInteraction()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.layer.cornerRadius = Self.tileRadius
        tile.layer.cornerCurve = .continuous
        contentView.addSubview(tile)
        tile.addSubview(favicon)
        plusIcon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(plusIcon)
        dashedBorder.fillColor = UIColor.clear.cgColor
        dashedBorder.lineWidth = 1
        dashedBorder.lineDashPattern = [3, 3]
        tile.layer.addSublayer(dashedBorder)
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tile.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            tile.heightAnchor.constraint(equalToConstant: 40),
            favicon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            favicon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            plusIcon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            plusIcon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
        ])
        addInteraction(toolTipInteraction)
        isAccessibilityElement = true
        accessibilityTraits = .button
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ model: TabViewModel) {
        isAddSlot = false
        favicon.configure(label: model.title, url: model.favicon, pageURL: model.url, loading: model.loading)
        active = model.active
        accessibilityLabel = "\(model.title), favorite"
        accessibilityTraits = model.active ? [.button, .selected] : .button
        toolTipInteraction.defaultToolTip = model.title
        restyle()
    }

    func configureAddSlot() {
        isAddSlot = true
        active = false
        favicon.prepareForReuse()
        accessibilityLabel = "Add current tab to Favorites"
        accessibilityTraits = .button
        toolTipInteraction.defaultToolTip = "Add Current Tab to Favorites"
        restyle()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        favicon.prepareForReuse()
    }

    override var isHighlighted: Bool { didSet { restyle() } }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        let hover = pointerInside || isHighlighted
        favicon.isHidden = isAddSlot
        plusIcon.isHidden = !isAddSlot
        dashedBorder.isHidden = !isAddSlot
        if isAddSlot {
            tile.backgroundColor = hover ? theme.rowHover.uiColor : .clear
            plusIcon.tintColor = (hover ? theme.textMuted : theme.textFaint).uiColor
            dashedBorder.strokeColor = theme.textFaint.withAlpha(0.28).uiColor.cgColor
            tile.layer.shadowOpacity = 0
            return
        }
        tile.backgroundColor = active ? (hover ? theme.fieldHover : theme.rowActive).uiColor : (hover ? theme.fieldHover : theme.field).uiColor
        if active {
            Shadow.sm.apply(to: tile.layer, dark: theme.appearance == .dark)
        } else {
            tile.layer.shadowOpacity = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layoutIfNeeded()
        tile.layer.shadowPath = UIBezierPath(roundedRect: tile.bounds, cornerRadius: Self.tileRadius).cgPath
        dashedBorder.frame = tile.bounds
        dashedBorder.path = UIBezierPath(
            roundedRect: dashedBorder.bounds.insetBy(dx: 0.5, dy: 0.5),
            cornerRadius: Self.tileRadius - 0.5
        ).cgPath
    }
}
