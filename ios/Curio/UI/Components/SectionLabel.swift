import UIKit

/// A small, faint section heading.
final class SectionLabel: UILabel, ThemeObserving {
    init(_ text: String) {
        super.init(frame: .zero)
        self.text = text
        font = CurioFont.xs(.semibold)
        adjustsFontForContentSizeCategory = true
        accessibilityTraits = .header
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        textColor = theme.textFaint.uiColor
    }
}
