import UIKit

/// A text button: default, primary (accent), ghost, or danger.
final class CurioButton: UIButton, ThemeObserving {
    enum Style { case standard, primary, ghost, danger }
    enum Size { case xsmall, small, medium }

    private let style: Style
    private let buttonSize: Size
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false

    init(_ title: String?, icon: Icon? = nil, style: Style = .standard, size: Size = .small, action: UIAction? = nil) {
        self.style = style
        buttonSize = size
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = icon?.image(size == .xsmall ? 11 : 13)
        configuration.imagePadding = 6
        configuration.background.cornerRadius = 7
        configuration.contentInsets = switch size {
        case .xsmall: NSDirectionalEdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8)
        case .small: NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        case .medium: NSDirectionalEdgeInsets(top: 9, leading: 16, bottom: 9, trailing: 16)
        }
        let font = size == .xsmall ? CurioFont.xs(.medium) : CurioFont.sm(.medium)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
        self.configuration = configuration
        if title == nil { accessibilityLabel = icon?.rawValue }
        isPointerInteractionEnabled = true
        if let action { addAction(action, for: .primaryActionTriggered) }
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.setNeedsUpdateConfiguration()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setTitle(_ title: String) {
        configuration?.title = title
    }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration() {
        guard var configuration else { return }
        let active = pointerInside || isHighlighted
        switch style {
        case .primary:
            let base = theme.accent
            configuration.baseForegroundColor = .white
            configuration.background.backgroundColor = active ? HSLA.mix(base, HSLA(0, 0, 0), 0.08).uiColor : base.uiColor
            configuration.background.strokeWidth = 0
        case .danger:
            configuration.baseForegroundColor = .white
            configuration.background.backgroundColor = theme.danger.uiColor.withAlphaComponent(active ? 0.85 : 1)
            configuration.background.strokeWidth = 0
        case .ghost:
            configuration.baseForegroundColor = theme.text.uiColor
            configuration.background.backgroundColor = active ? theme.rowHover.uiColor : .clear
            configuration.background.strokeWidth = 0
        case .standard:
            configuration.baseForegroundColor = theme.text.uiColor
            configuration.background.backgroundColor = active ? theme.fieldHover.uiColor : theme.surfaceRaised.uiColor
            configuration.background.strokeColor = theme.surfaceBorder.uiColor
            configuration.background.strokeWidth = 1
        }
        self.configuration = configuration
        alpha = isEnabled ? 1 : 0.45
    }
}
