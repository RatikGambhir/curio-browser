import UIKit

/// A site on the new tab page: icon on a raised square with its name below.
final class SiteTileView: TapControl, ThemeObserving {
    private let box = UIView()
    private let favicon = FaviconView(size: 24)
    private let label = UILabel()
    private var pointerInside = false
    private var theme = ThemeCenter.shared.theme

    init(title: String, url: String, favicon iconURL: String?, action: UIAction) {
        super.init(frame: .zero)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.layer.cornerRadius = 14
        box.layer.cornerCurve = .continuous
        box.layer.borderWidth = 1
        box.isUserInteractionEnabled = false
        box.addSubview(favicon)
        favicon.configure(label: Curio.displayHost(url), url: iconURL)
        label.text = title
        label.font = CurioFont.xs()
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)
        addSubview(label)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            box.centerXAnchor.constraint(equalTo: centerXAnchor),
            box.widthAnchor.constraint(equalToConstant: 48),
            box.heightAnchor.constraint(equalToConstant: 48),
            favicon.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            favicon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            label.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        addAction(action, for: .primaryActionTriggered)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .link
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize { CGSize(width: 96, height: 10 + 48 + 8 + label.font.lineHeight + 10) }
    override var isHighlighted: Bool { didSet { restyle() } }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        box.backgroundColor = theme.surfaceRaised.uiColor
        box.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        label.textColor = theme.textMuted.uiColor
        backgroundColor = pointerInside || isHighlighted ? theme.rowHover.uiColor : .clear
    }
}
