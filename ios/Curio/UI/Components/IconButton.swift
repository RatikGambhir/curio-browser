import UIKit

/// A square, borderless icon button like the desktop's `IconButton`: muted
/// until hovered or pressed, accent-tinted when selected. Its touch target
/// is always at least 44pt.
final class IconButton: UIButton, ThemeObserving {
    enum Size {
        case xsmall, small, medium, large

        var edge: CGFloat {
            switch self {
            case .xsmall: 22
            case .small: 28
            case .medium: 32
            case .large: 36
            }
        }
        var radius: CGFloat {
            switch self {
            case .xsmall: 6
            case .small: 7
            case .medium: 8
            case .large: 9
            }
        }
        var symbol: CGFloat {
            switch self {
            case .xsmall: 11
            case .small: 14
            case .medium: 16
            case .large: 18
            }
        }
    }

    private let size: Size
    private var pointerInside = false
    private var theme = ThemeCenter.shared.theme
    /// Accent-tinted with a soft background, like a toggled tool.
    var isToggled = false { didSet { setNeedsUpdateConfiguration() } }
    /// Overrides the resting icon color.
    var tint: UIColor? { didSet { setNeedsUpdateConfiguration() } }

    init(_ icon: Icon, size: Size = .small, label: String, action: UIAction? = nil) {
        self.size = size
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.image = icon.image(size.symbol)
        configuration.contentInsets = .zero
        configuration.background.cornerRadius = size.radius
        self.configuration = configuration
        accessibilityLabel = label
        toolTip = label
        isPointerInteractionEnabled = true
        if let action { addAction(action, for: .primaryActionTriggered) }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.edge),
            heightAnchor.constraint(equalToConstant: size.edge),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.setNeedsUpdateConfiguration()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setIcon(_ icon: Icon, label: String? = nil) {
        configuration?.image = icon.image(size.symbol)
        if let label {
            accessibilityLabel = label
            toolTip = label
        }
    }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration() {
        guard var configuration else { return }
        let active = (pointerInside || isHighlighted) && isEnabled
        let foreground: UIColor = if isToggled {
            theme.accentText.uiColor
        } else if active {
            theme.text.uiColor
        } else {
            tint ?? theme.textMuted.uiColor
        }
        configuration.baseForegroundColor = foreground
        configuration.background.backgroundColor = (active || isToggled) ? theme.rowHover.uiColor : .clear
        self.configuration = configuration
        alpha = isEnabled ? (isHighlighted ? 0.7 : 1) : 0.35
    }

    /// Expands small buttons to a 44pt touch target.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = max(0, (Metrics.minTouch - bounds.width) / 2)
        let dy = max(0, (Metrics.minTouch - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy).contains(point)
    }
}
