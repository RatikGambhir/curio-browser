import UIKit

/// Find in page: a floating field with the match count and previous, next
/// and close buttons.
final class FindBarView: UIView, UITextFieldDelegate {
    let field = SearchFieldView(placeholder: "Find in page", floating: true)
    private let status = UILabel()
    private let previousButton = IconButton(.chevronUp, size: .xsmall, label: "Previous Match")
    private let nextButton = IconButton(.chevronDown, size: .xsmall, label: "Next Match")
    private let closeButton = IconButton(.close, size: .xsmall, label: "Close Find")
    var onSearch: ((String, Bool) -> Void)?
    var onClose: (() -> Void)?

    init() {
        super.init(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        status.font = CurioFont.xs()
        status.setContentHuggingPriority(.required, for: .horizontal)
        for view in [status, previousButton, nextButton, closeButton] as [UIView] { field.trailingStack.addArrangedSubview(view) }
        field.textField.delegate = self
        field.textField.returnKeyType = .next
        field.textField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onSearch?(field.textField.text ?? "", true)
        }, for: .editingChanged)
        previousButton.addAction(UIAction { [weak self] _ in self?.search(forward: false) }, for: .primaryActionTriggered)
        nextButton.addAction(UIAction { [weak self] _ in self?.search(forward: true) }, for: .primaryActionTriggered)
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .primaryActionTriggered)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func search(forward: Bool) {
        onSearch?(field.textField.text ?? "", forward)
    }

    func show(_ result: FindResult) {
        let theme = ThemeCenter.shared.theme
        let empty = (field.textField.text ?? "").isEmpty
        status.text = empty ? "" : result.matches == 0 ? "No matches" : "\(result.active) of \(result.matches)"
        status.textColor = (result.matches == 0 && !empty ? theme.danger : theme.textFaint).uiColor
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        search(forward: true)
        return false
    }
}
