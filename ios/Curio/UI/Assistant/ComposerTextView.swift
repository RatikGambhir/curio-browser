import UIKit

/// The message box: grows from one to eight lines, sends on Return
/// (Shift-Return adds a line on a hardware keyboard), and shows a
/// placeholder.
final class ComposerTextView: UITextView, UITextViewDelegate {
    private let placeholderLabel = UILabel()
    private var heightConstraint: NSLayoutConstraint!
    var onSubmit: (() -> Void)?
    var onChange: (() -> Void)?

    init(placeholder: String) {
        super.init(frame: .zero, textContainer: nil)
        font = CurioFont.sm()
        adjustsFontForContentSizeCategory = true
        backgroundColor = .clear
        textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        textContainer.lineFragmentPadding = 2
        returnKeyType = .send
        delegate = self
        isScrollEnabled = false
        accessibilityLabel = placeholder
        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.numberOfLines = 1
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        heightConstraint = heightAnchor.constraint(equalToConstant: 30)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            placeholderLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            heightConstraint,
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setColors(text: UIColor, placeholder: UIColor, tint: UIColor) {
        textColor = text
        placeholderLabel.textColor = placeholder
        tintColor = tint
    }

    func setText(_ value: String) {
        text = value
        textDidChange()
    }

    private func textDidChange() {
        placeholderLabel.isHidden = !text.isEmpty
        let line = (font ?? CurioFont.sm()).lineHeight
        let maxHeight = line * 8 + textContainerInset.top + textContainerInset.bottom
        let fitting = sizeThatFits(CGSize(width: bounds.width > 0 ? bounds.width : 300, height: .greatestFiniteMagnitude)).height
        heightConstraint.constant = min(max(fitting, line + textContainerInset.top + textContainerInset.bottom), maxHeight)
        isScrollEnabled = fitting > maxHeight
        onChange?()
    }

    func textViewDidChange(_ textView: UITextView) {
        textDidChange()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            onSubmit?()
            return false
        }
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        let newline = UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(insertNewline))
        newline.wantsPriorityOverSystemBehavior = true
        return [newline]
    }

    @objc private func insertNewline() {
        insertText("\n")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if heightConstraint.constant < 1 { textDidChange() }
    }
}
