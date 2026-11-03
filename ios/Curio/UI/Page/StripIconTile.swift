import UIKit

/// A favorite or pinned tab as a compact icon in the tab strip.
final class StripIconTile: TapControl, ThemeObserving {
    private let favicon = FaviconView(size: 16)
    private var active = false
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false

    init(model: TabViewModel) {
        super.init(frame: .zero)
        favicon.isUserInteractionEnabled = false
        addSubview(favicon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 30),
            favicon.centerXAnchor.constraint(equalTo: centerXAnchor),
            favicon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
        favicon.configure(label: model.title, url: model.favicon, loading: model.loading)
        active = model.active
        toolTip = model.title
        accessibilityLabel = model.title
        accessibilityTraits = active ? [.button, .selected] : .button
        restyle()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isHighlighted: Bool { didSet { restyle() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
    }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        if active {
            backgroundColor = theme.rowActive.uiColor
            Shadow.xs.apply(to: layer, dark: theme.appearance == .dark)
        } else {
            backgroundColor = pointerInside || isHighlighted ? theme.rowHover.uiColor : .clear
            layer.shadowOpacity = 0
        }
    }
}
