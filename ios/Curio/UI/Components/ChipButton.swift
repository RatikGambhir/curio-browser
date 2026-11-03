import UIKit

/// A pill-shaped action, like the desktop's `Chip` (selection actions and the
/// assistant's suggestions).
final class ChipButton: UIButton, ThemeObserving {
    private let large: Bool
    private let outlined: Bool
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false

    init(_ title: String, icon: Icon? = nil, large: Bool = false, outlined: Bool = false, action: UIAction? = nil) {
        self.large = large
        self.outlined = outlined
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = icon?.image(large ? 14 : 12)
        configuration.imagePadding = large ? 8 : 6
        configuration.background.cornerRadius = large ? 9 : 8
        configuration.contentInsets = large
            ? NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
            : NSDirectionalEdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)
        let font = large ? CurioFont.sm() : CurioFont.xs(.medium)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = font
            return attributes
        }
        configuration.titleLineBreakMode = .byTruncatingTail
        if large { configuration.titleAlignment = .leading }
        self.configuration = configuration
        contentHorizontalAlignment = large ? .leading : .center
        isPointerInteractionEnabled = true
        if let action { addAction(action, for: .primaryActionTriggered) }
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.setNeedsUpdateConfiguration()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration() {
        guard var configuration else { return }
        let active = pointerInside || isHighlighted
        configuration.baseForegroundColor = active ? theme.accentText.uiColor : theme.text.uiColor
        configuration.imageColorTransformer = UIConfigurationColorTransformer { [theme, outlined] color in
            outlined ? theme.accentText.uiColor : color
        }
        if outlined {
            configuration.background.backgroundColor = active ? theme.accentSoft.uiColor : theme.surfaceRaised.uiColor
            configuration.background.strokeColor = active ? theme.accentSoft.uiColor : theme.surfaceBorder.uiColor
            configuration.background.strokeWidth = 1
        } else {
            configuration.background.backgroundColor = active ? theme.accentSoft.uiColor : .clear
        }
        self.configuration = configuration
    }
}
