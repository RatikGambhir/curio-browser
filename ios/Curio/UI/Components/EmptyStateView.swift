import UIKit

/// A centered icon, title and description for empty lists.
final class EmptyStateView: UIView, ThemeObserving {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let compact: Bool

    init(title: String, description: String? = nil, icon: Icon? = nil, compact: Bool = false) {
        self.compact = compact
        super.init(frame: .zero)
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel, descriptionLabel])
        stack.axis = .vertical
        stack.alignment = compact ? .leading : .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let inset: CGFloat = compact ? 10 : 20
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: compact ? 0 : -22),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: inset),
        ])
        iconView.image = icon?.image(36, weight: .light)
        iconView.isHidden = icon == nil || compact
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = compact ? .natural : .center
        titleLabel.font = compact ? CurioFont.xs() : CurioFont.base(.semibold)
        titleLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.text = description
        descriptionLabel.isHidden = description == nil
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textAlignment = .center
        descriptionLabel.font = CurioFont.sm()
        descriptionLabel.adjustsFontForContentSizeCategory = true
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        iconView.tintColor = theme.textFaint.uiColor
        titleLabel.textColor = compact ? theme.textFaint.uiColor : theme.text.uiColor
        descriptionLabel.textColor = theme.textMuted.uiColor
    }
}
