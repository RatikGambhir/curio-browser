import UIKit

/// A tab in the horizontal tab strip.
final class StripTabView: TapControl, ThemeObserving, UIDragInteractionDelegate {
    let tabID: UUID
    private let favicon = FaviconView(size: 15)
    private let label = UILabel()
    private let closeButton = IconButton(.close, size: .xsmall, label: "Close Tab")
    private let groupBar = UIView()
    private var model: TabViewModel
    private var theme = ThemeCenter.shared.theme
    private var pointerInside = false
    var onClose: (() -> Void)?
    var menuProvider: (() -> UIMenu)?

    init(model: TabViewModel, groupColor: UIColor?) {
        tabID = model.id
        self.model = model
        super.init(frame: .zero)
        label.font = CurioFont.sm()
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [favicon, label, closeButton])
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        favicon.isUserInteractionEnabled = false
        label.isUserInteractionEnabled = false
        addSubview(stack)
        groupBar.translatesAutoresizingMaskIntoConstraints = false
        groupBar.backgroundColor = groupColor
        groupBar.isHidden = groupColor == nil
        addSubview(groupBar)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30),
            groupBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            groupBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            groupBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            groupBar.heightAnchor.constraint(equalToConstant: 2),
        ])
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .primaryActionTriggered)
        isContextMenuInteractionEnabled = true
        addInteraction(UIDragInteraction(delegate: self))
        isAccessibilityElement = true
        HoverTracker(self) { [weak self] in
            self?.pointerInside = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
        configure(model)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ model: TabViewModel) {
        self.model = model
        label.text = model.title
        favicon.configure(label: model.title, url: model.favicon, loading: model.loading)
        accessibilityLabel = model.title
        accessibilityTraits = model.active ? [.button, .selected] : .button
        restyle()
    }

    override var isHighlighted: Bool { didSet { restyle() } }

    func themeDidChange(_ theme: CurioTheme) {
        self.theme = theme
        restyle()
    }

    private func restyle() {
        closeButton.alpha = model.active || pointerInside ? 1 : 0
        if model.active {
            backgroundColor = theme.rowActive.uiColor
            label.textColor = theme.rowActiveText.uiColor
            Shadow.xs.apply(to: layer, dark: theme.appearance == .dark)
        } else {
            backgroundColor = pointerInside || isHighlighted ? theme.rowHover.uiColor : .clear
            label.textColor = theme.textMuted.uiColor
            layer.shadowOpacity = 0
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: 8).cgPath
    }

    override func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menuProvider else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menuProvider() }
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = SidebarDragBox(.tab(tabID))
        return [item]
    }
}
