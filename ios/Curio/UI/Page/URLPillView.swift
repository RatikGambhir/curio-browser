import UIKit

/// The rounded address field on the chrome (horizontal toolbar and phone
/// bottom bar): icon, host, zoom, a trailing button and a loading bar.
final class URLPillView: TapControl, ThemeObserving {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let zoomLabel = UILabel()
    let trailingButton: IconButton
    private let loadingBar = LoadingBarView()
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false
    private var hasPage = false

    init(trailing: IconButton) {
        trailingButton = trailing
        super.init(frame: .zero)
        iconView.contentMode = .center
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        label.font = CurioFont.sm()
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        zoomLabel.font = CurioFont.xs()
        zoomLabel.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [iconView, label, zoomLabel, trailingButton])
        stack.spacing = 7
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        iconView.isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false
        addSubview(stack)
        addSubview(loadingBar)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            loadingBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            loadingBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            loadingBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        loadingBar.isHidden = true
        layer.cornerRadius = Metrics.fieldRadius
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = false
        accessibilityTraits = .button
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ nav: PageNav) {
        hasPage = nav.page != nil
        iconView.image = nav.addressIcon.image(11)
        label.text = nav.page?.host ?? "Search or enter address"
        label.accessibilityLabel = nav.page.map { "Address, \($0.host)" } ?? "Search or enter address"
        zoomLabel.text = nav.zoomLabel
        zoomLabel.isHidden = nav.zoomLabel == nil
        loadingBar.isHidden = !nav.loading
        restyle()
    }

    override var isHighlighted: Bool { didSet { restyle() } }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        iconView.tintColor = theme.textFaint.uiColor
        zoomLabel.textColor = theme.textFaint.uiColor
        label.textColor = hasPage ? theme.text.uiColor : theme.textFaint.uiColor
        backgroundColor = (pointerInside || isHighlighted ? theme.fieldHover : theme.field).uiColor
    }

    override var accessibilityElements: [Any]? {
        get { [label, trailingButton] }
        set { super.accessibilityElements = newValue }
    }
}
