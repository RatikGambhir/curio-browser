import UIKit

/// A fenced code block with its language and a copy button.
final class CodeBlockView: UIView {
    private let languageLabel = UILabel()
    private let codeLabel = UILabel()
    private let copyButton = IconButton(.copy, size: .xsmall, label: "Copy Code")
    private var code = ""

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        languageLabel.font = CurioFont.xs(.medium)
        codeLabel.numberOfLines = 0
        codeLabel.font = CurioFont.mono(12.5)
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(codeLabel)
        let header = UIStackView(arrangedSubviews: [languageLabel, UIView(), copyButton])
        header.alignment = .center
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            header.heightAnchor.constraint(equalToConstant: 26),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            codeLabel.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            codeLabel.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            codeLabel.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            codeLabel.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            scroll.heightAnchor.constraint(equalTo: codeLabel.heightAnchor),
        ])
        copyButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = code
            copyButton.setIcon(.checkCircle)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                self?.copyButton.setIcon(.copy)
            }
        }, for: .primaryActionTriggered)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(language: String, code: String, theme: CurioTheme) {
        self.code = code
        languageLabel.text = language.isEmpty ? "code" : language
        codeLabel.text = code
        backgroundColor = theme.appearance == .dark ? HSLA(0, 0, 0, 0.25).uiColor : HSLA(0, 0, 0, 0.035).uiColor
        layer.borderColor = theme.divider.uiColor.cgColor
        languageLabel.textColor = theme.textFaint.uiColor
        codeLabel.textColor = theme.text.uiColor
    }
}
