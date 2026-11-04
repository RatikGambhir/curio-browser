import UIKit

/// One space in the footer switcher: a dot in the space theme's accent, larger and
/// solid for the active space. Tabs can be dropped on it to move them.
final class SpaceDotButton: TapControl {
    let spaceID: UUID
    private let dot: ColorDotView
    private var active: Bool
    /// The space's context menu.
    var menuProvider: (() -> UIMenu)?

    init(space: Space, active: Bool, action: UIAction) {
        spaceID = space.id
        self.active = active
        dot = ColorDotView(color: CurioTheme.swatch(space.gradient), diameter: active ? 8 : 6)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 36),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        layer.cornerRadius = 6
        alpha = active ? 1 : 0.5
        addAction(action, for: .primaryActionTriggered)
        toolTip = space.name
        isAccessibilityElement = true
        accessibilityLabel = "\(space.name) space"
        accessibilityTraits = active ? [.button, .selected] : .button
        isContextMenuInteractionEnabled = true
        HoverTracker(self) { [weak self] inside in
            guard let self else { return }
            alpha = inside || self.active ? 1 : 0.5
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Expands the touch target to 44pt tall.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -2, dy: -4).contains(point)
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menuProvider else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menuProvider() }
    }

    func setDropHighlight(_ on: Bool) {
        backgroundColor = on ? ThemeCenter.shared.theme.accentSoft.uiColor : .clear
    }
}
