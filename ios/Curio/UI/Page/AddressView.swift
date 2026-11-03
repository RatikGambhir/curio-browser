import UIKit

/// The page's address as the desktop shows it: lock or globe, the host, and
/// (when there is room) " / title", plus the zoom level.
final class AddressView: TapControl, ThemeObserving {
    private let iconView = UIImageView()
    private let hostLabel = UILabel()
    private let slashLabel = UILabel()
    private let titleLabel = UILabel()
    private let zoomLabel = UILabel()
    private let showsTitle: Bool
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false
    private var hasPage = false
    /// Tinted background like the URL pill, rather than hover-only.
    var filled = false { didSet { restyle() } }

    init(showsTitle: Bool) {
        self.showsTitle = showsTitle
        super.init(frame: .zero)
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        for label in [hostLabel, slashLabel, titleLabel, zoomLabel] {
            label.font = label === zoomLabel ? CurioFont.xs() : CurioFont.sm()
            label.adjustsFontForContentSizeCategory = true
            label.lineBreakMode = .byTruncatingTail
        }
        hostLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        slashLabel.text = "/"
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zoomLabel.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [iconView, hostLabel, slashLabel, titleLabel, zoomLabel])
        stack.spacing = 6
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityHint = "Edits the address"
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ nav: PageNav) {
        iconView.image = nav.addressIcon.image(11)
        hasPage = nav.page != nil
        if let page = nav.page {
            hostLabel.text = page.host
            titleLabel.text = page.title
            let showTitle = showsTitle && page.title != page.host
            slashLabel.isHidden = !showTitle
            titleLabel.isHidden = !showTitle
            accessibilityLabel = "Address, \(page.host)"
        } else {
            hostLabel.text = "Search or enter address"
            slashLabel.isHidden = true
            titleLabel.isHidden = true
            accessibilityLabel = "Search or enter address"
        }
        zoomLabel.text = nav.zoomLabel
        zoomLabel.isHidden = nav.zoomLabel == nil
        restyle()
    }

    override var isHighlighted: Bool { didSet { restyle() } }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        iconView.tintColor = theme.textFaint.uiColor
        hostLabel.textColor = hasPage ? theme.text.uiColor : theme.textFaint.uiColor
        slashLabel.textColor = theme.textFaint.uiColor
        titleLabel.textColor = theme.textMuted.uiColor
        zoomLabel.textColor = theme.textFaint.uiColor
        let active = pointerInside || isHighlighted
        backgroundColor = filled ? (active ? theme.fieldHover : theme.field).uiColor : (active ? theme.rowHover.uiColor : .clear)
    }
}
