import UIKit

/// A favorite in the sidebar's grid: the site icon on a rounded tile.
final class FavoriteTileCell: UICollectionViewCell, ThemeObserving {
    private let tile = UIView()
    private let favicon = FaviconView(size: 20)
    private var theme = ThemeCenter.shared.theme
    private var active = false
    private var pointerInside = false
    private let toolTipInteraction = UIToolTipInteraction()

    override init(frame: CGRect) {
        super.init(frame: frame)
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.layer.cornerRadius = 10
        tile.layer.cornerCurve = .continuous
        contentView.addSubview(tile)
        tile.addSubview(favicon)
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tile.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tile.topAnchor.constraint(equalTo: contentView.topAnchor),
            tile.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            favicon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            favicon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
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
        favicon.configure(label: model.title, url: model.favicon, loading: model.loading)
        active = model.active
        accessibilityLabel = "\(model.title), favorite"
        accessibilityTraits = model.active ? [.button, .selected] : .button
        toolTipInteraction.defaultToolTip = model.title
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
        tile.backgroundColor = active ? (hover ? theme.fieldHover : theme.rowActive).uiColor : (hover ? theme.fieldHover : theme.field).uiColor
        if active {
            Shadow.sm.apply(to: tile.layer, dark: theme.appearance == .dark)
        } else {
            tile.layer.shadowOpacity = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.layer.shadowPath = UIBezierPath(roundedRect: tile.bounds, cornerRadius: 10).cgPath
    }
}
