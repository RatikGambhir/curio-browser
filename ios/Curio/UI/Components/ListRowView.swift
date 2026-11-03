import UIKit

/// A list row like the desktop's `ListItem`: optional leading view, a title
/// with optional subtitle, trailing views, and selected/hover styles.
final class ListRowView: UIView, ThemeObserving {
    enum SelectedStyle {
        /// The lifted white row of the sidebar.
        case raised
        /// Accent wash with accent text (settings navigation).
        case accent
        /// Accent wash only (command bar).
        case subtle
    }

    let leadingContainer = UIView()
    let titleLabel = UILabel()
    let subtitleLabel = UILabel()
    let trailingStack = UIStackView()
    private let stack = UIStackView()
    private let labels = UIStackView()
    private var theme = ThemeCenter.shared.theme
    private var heightConstraint: NSLayoutConstraint?
    private var leadingConstraint: NSLayoutConstraint?

    var isSelected = false { didSet { restyle() } }
    var isHovered = false { didSet { restyle() } }
    var isPressed = false { didSet { restyle() } }
    var selectedStyle: SelectedStyle = .raised { didSet { restyle() } }
    /// Muted rows use the muted text color until selected or hovered.
    var muted = false { didSet { restyle() } }
    var titleWeight: UIFont.Weight = .regular { didSet { titleLabel.font = CurioFont.sm(titleWeight) } }
    /// Fires when the row restyles, so owners can tint custom content.
    var onRestyle: ((CurioTheme, Bool) -> Void)?

    init(height: CGFloat? = nil) {
        super.init(frame: .zero)
        layer.cornerRadius = Metrics.rowRadius
        layer.cornerCurve = .continuous
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        labels.axis = .vertical
        labels.spacing = 0
        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(subtitleLabel)
        titleLabel.font = CurioFont.sm()
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.font = CurioFont.xs()
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.isHidden = true
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = 6
        leadingContainer.isHidden = true
        stack.addArrangedSubview(leadingContainer)
        stack.addArrangedSubview(labels)
        stack.addArrangedSubview(trailingStack)
        leadingContainer.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // The title column takes any spare width, so trailing accessories
        // keep their natural size.
        titleLabel.setContentHuggingPriority(UILayoutPriority(200), for: .horizontal)
        subtitleLabel.setContentHuggingPriority(UILayoutPriority(200), for: .horizontal)
        let leading = stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
        leadingConstraint = leading
        NSLayoutConstraint.activate([
            leading,
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if let height {
            let constraint = heightAnchor.constraint(equalToConstant: height)
            constraint.priority = .defaultHigh
            constraint.isActive = true
            heightConstraint = constraint
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setLeading(_ view: UIView?) {
        leadingContainer.subviews.forEach { $0.removeFromSuperview() }
        leadingContainer.isHidden = view == nil
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        leadingContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: leadingContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: leadingContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: leadingContainer.bottomAnchor),
        ])
    }

    func setTitle(_ title: String, subtitle: String? = nil) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
    }

    func setSpacing(_ spacing: CGFloat) { stack.spacing = spacing }
    func setLeadingInset(_ inset: CGFloat) { leadingConstraint?.constant = inset }
    func setHeight(_ height: CGFloat) { heightConstraint?.constant = height }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        let active = isHovered || isPressed
        var background: UIColor = .clear
        var text = muted ? theme.textMuted.uiColor : theme.text.uiColor
        layer.borderWidth = 0
        layer.shadowOpacity = 0
        if isSelected {
            switch selectedStyle {
            case .raised:
                background = theme.rowActive.uiColor
                text = theme.rowActiveText.uiColor
                layer.borderWidth = 1
                layer.borderColor = theme.rowActiveBorder.uiColor.cgColor
                Shadow.xs.apply(to: layer, dark: theme.appearance == .dark)
            case .accent:
                background = theme.accentSoft.uiColor
                text = theme.accentText.uiColor
            case .subtle:
                background = theme.accentSoft.uiColor
                text = theme.text.uiColor
            }
        } else if active {
            background = theme.rowHover.uiColor
            text = theme.text.uiColor
        }
        backgroundColor = background
        titleLabel.textColor = text
        subtitleLabel.textColor = theme.textFaint.uiColor
        onRestyle?(theme, isSelected)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if layer.shadowOpacity > 0 {
            layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Metrics.rowRadius).cgPath
        }
    }
}
