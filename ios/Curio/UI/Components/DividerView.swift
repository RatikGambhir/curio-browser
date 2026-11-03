import UIKit

/// A hairline divider in the theme's divider color.
final class DividerView: UIView, ThemeObserving {
    init(vertical: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let constraint = vertical ? widthAnchor.constraint(equalToConstant: 1) : heightAnchor.constraint(equalToConstant: 1)
        constraint.isActive = true
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        backgroundColor = theme.divider.uiColor
    }
}
