import UIKit

/// An assistant answer: a status line while it starts, the Markdown text, an
/// error with Retry, and a copy button once finished.
final class AssistantMessageView: UIView {
    private let statusRow = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    let markdown = MarkdownView()
    private let errorBox = UIView()
    private let errorLabel = UILabel()
    private let errorIcon = UIImageView(image: Icon.warning.image(11))
    private let retryButton = CurioButton("Retry", style: .ghost, size: .xsmall)
    private let copyButton = IconButton(.copy, size: .xsmall, label: "Copy Answer")
    private var content = ""
    var onRetry: (() -> Void)?

    init() {
        super.init(frame: .zero)
        spinner.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        statusLabel.font = CurioFont.sm()
        statusRow.addArrangedSubview(spinner)
        statusRow.addArrangedSubview(statusLabel)
        statusRow.spacing = 6
        errorLabel.font = CurioFont.xs()
        errorLabel.numberOfLines = 0
        let errorStack = UIStackView(arrangedSubviews: [errorIcon, errorLabel, retryButton])
        errorStack.spacing = 8
        errorStack.alignment = .center
        errorStack.translatesAutoresizingMaskIntoConstraints = false
        errorIcon.setContentHuggingPriority(.required, for: .horizontal)
        retryButton.setContentHuggingPriority(.required, for: .horizontal)
        errorBox.addSubview(errorStack)
        errorBox.layer.cornerRadius = 8
        errorBox.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate([
            errorStack.leadingAnchor.constraint(equalTo: errorBox.leadingAnchor, constant: 8),
            errorStack.trailingAnchor.constraint(equalTo: errorBox.trailingAnchor, constant: -8),
            errorStack.topAnchor.constraint(equalTo: errorBox.topAnchor, constant: 8),
            errorStack.bottomAnchor.constraint(equalTo: errorBox.bottomAnchor, constant: -8),
        ])
        retryButton.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .primaryActionTriggered)
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = content
            copyButton.setIcon(.checkCircle)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.copyButton.setIcon(.copy)
            }
        }, for: .primaryActionTriggered)
        let copyRow = UIStackView(arrangedSubviews: [copyButton, UIView()])
        let stack = UIStackView(arrangedSubviews: [statusRow, markdown, errorBox, copyRow])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ message: ChatMessage, streaming: Bool, status: AssistantStatus, isLast: Bool, theme: CurioTheme) {
        content = message.content
        let waiting = streaming && message.content.isEmpty
        statusRow.isHidden = !waiting
        if waiting {
            spinner.color = theme.accent.uiColor
            spinner.startAnimating()
            statusLabel.text = status.label
            statusLabel.textColor = theme.textMuted.uiColor
        } else {
            spinner.stopAnimating()
        }
        markdown.isHidden = message.content.isEmpty
        markdown.render(message.content, theme: theme, color: theme.text.uiColor)
        errorBox.isHidden = message.error == nil
        if let error = message.error {
            errorBox.backgroundColor = theme.danger.withAlpha(0.10).uiColor
            errorLabel.text = error
            errorLabel.textColor = theme.danger.uiColor
            errorIcon.tintColor = theme.danger.uiColor
            retryButton.isHidden = !(isLast && !streaming)
        }
        copyButton.superview?.isHidden = streaming || message.content.isEmpty
    }
}
