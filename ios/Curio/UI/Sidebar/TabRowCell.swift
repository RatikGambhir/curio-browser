import UIKit

/// A tab in the sidebar: icon (or spinner), title, and a close button that
/// shows on hover and for the active tab.
final class TabRowCell: UICollectionViewListCell {
    let row = ListRowView()
    private let favicon = FaviconView(size: 16)
    private let closeButton = IconButton(.close, size: .xsmall, label: "Close Tab")
    private var model: TabViewModel?
    private var pointerInside = false
    var onClose: ((TabViewModel) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.muted = true
        row.setLeading(favicon)
        row.trailingStack.addArrangedSubview(closeButton)
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
        ])
        closeButton.addAction(UIAction { [weak self] _ in
            guard let self, let model else { return }
            onClose?(model)
        }, for: .primaryActionTriggered)
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.row.isHovered = $0
            self?.updateCloseButton()
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ model: TabViewModel, grouped: Bool, height: CGFloat) {
        self.model = model
        row.setHeight(height)
        row.setTitle(model.title)
        row.isSelected = model.active
        row.titleWeight = model.active ? .medium : .regular
        row.setLeadingInset(grouped ? 22 : 8)
        row.setSpacing(10)
        favicon.configure(label: model.title, url: model.favicon, loading: model.loading)
        favicon.alpha = model.asleep && !model.active && !model.pinned ? 0.65 : 1
        closeButton.setIcon(model.pinned ? .minus : .close, label: model.pinned ? "Unload Tab" : "Close Tab")
        closeButton.tint = ThemeCenter.shared.theme.textFaint.uiColor
        accessibilityLabel = model.title
        accessibilityTraits = model.active ? [.button, .selected] : .button
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: model.pinned ? "Unload Tab" : "Close Tab") { [weak self] _ in
            guard let self, let model = self.model else { return false }
            onClose?(model)
            return true
        }]
        updateCloseButton()
    }

    private func updateCloseButton() {
        closeButton.alpha = (model?.active ?? false) || pointerInside ? 1 : 0
        closeButton.isUserInteractionEnabled = closeButton.alpha > 0
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        favicon.prepareForReuse()
        pointerInside = false
        row.isHovered = false
    }

    override var isHighlighted: Bool {
        didSet { row.isPressed = isHighlighted }
    }
}
