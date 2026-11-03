import UIKit

/// The rounded card the page and the assistant float on: a shadow outside, a
/// clipped `contentView` inside.
final class CardView: UIView, ThemeObserving {
    let contentView = UIView()
    private let radius: CGFloat
    /// The shadow; a floating card uses a deeper one.
    var shadow: Shadow {
        didSet { shadow.apply(to: layer, dark: ThemeCenter.shared.theme.appearance == .dark) }
    }
    private let usesSurface: Bool

    init(radius: CGFloat = Metrics.cardRadius, shadow: Shadow = .md, surface: Bool = false) {
        self.radius = radius
        self.shadow = shadow
        usesSurface = surface
        super.init(frame: .zero)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.layer.cornerRadius = radius
        contentView.layer.cornerCurve = .continuous
        contentView.layer.borderWidth = 1
        contentView.clipsToBounds = true
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        contentView.backgroundColor = (usesSurface ? theme.surfaceRaised : theme.card).uiColor
        contentView.layer.borderColor = (usesSurface ? theme.surfaceBorder : theme.cardBorder).uiColor.cgColor
        shadow.apply(to: layer, dark: theme.appearance == .dark)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }
}
