import UIKit

/// "This page didn't finish loading" with a Try Again button.
final class StalledBannerView: UIView, ThemeObserving {
    private let icon = UIImageView(image: Icon.warning.image(13))
    private let label = UILabel()
    let retryButton = CurioButton("Try Again")

    init() {
        super.init(frame: .zero)
        label.text = "This page didn’t finish loading. Check your connection or the address."
        label.font = CurioFont.sm()
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        retryButton.setContentHuggingPriority(.required, for: .horizontal)
        retryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [icon, label, retryButton])
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 10).cgPath
    }

    func themeDidChange(_ theme: CurioTheme) {
        backgroundColor = theme.surfaceRaised.uiColor
        layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        Shadow.lg.apply(to: layer, dark: theme.appearance == .dark)
        icon.tintColor = theme.warning.uiColor
        label.textColor = theme.text.uiColor
    }
}
