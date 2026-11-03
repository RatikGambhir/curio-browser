import UIKit

/// A settings row: label and description on the left, a control on the
/// right (or below on narrow screens), with a divider under it.
final class SettingRowView: UIView, ThemeObserving {
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let divider = DividerView()
    private let stack = UIStackView()

    init(_ title: String, description: String? = nil, control: UIView?, stacked: Bool = false) {
        super.init(frame: .zero)
        titleLabel.text = title
        titleLabel.font = CurioFont.sm(.medium)
        titleLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.text = description
        descriptionLabel.font = CurioFont.xs()
        descriptionLabel.numberOfLines = 0
        descriptionLabel.adjustsFontForContentSizeCategory = true
        descriptionLabel.isHidden = description == nil
        let labels = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        labels.axis = .vertical
        labels.spacing = 2
        stack.axis = stacked ? .vertical : .horizontal
        stack.alignment = stacked ? .leading : .center
        stack.spacing = stacked ? 10 : 16
        stack.addArrangedSubview(labels)
        if let control {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.addArrangedSubview(control)
            if stacked {
                control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = control is UITextField || control is SearchFieldView || control is UIStackView
            }
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(divider)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -10),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        titleLabel.textColor = theme.text.uiColor
        descriptionLabel.textColor = theme.textFaint.uiColor
    }
}
