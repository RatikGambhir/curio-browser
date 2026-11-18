import UIKit

/// A split view in the sidebar: one rounded, outlined box with a segment per
/// pane (favicon and title, divided by thin lines). The focused pane's
/// segment is highlighted, and the box gets a hover background while it
/// holds the active tab. Tapping a segment focuses that pane; ⌘-tap attaches
/// it to the assistant; a middle click closes it. Long-pressing a segment
/// shows its menu (built by the sidebar from `paneID(at:)`).
final class SplitRowCell: UICollectionViewListCell, ThemeObserving {
    private let box = UIView()
    private let stack = UIStackView()
    private var segments: [SplitSegmentView] = []
    private var models: [TabViewModel] = []
    private var leading: NSLayoutConstraint?
    private var height: NSLayoutConstraint?
    private var holdsActive = false
    private var equalWidths: [NSLayoutConstraint] = []
    var onSelect: ((UUID, UIKeyModifierFlags) -> Void)?
    var onClose: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        box.layer.cornerRadius = Metrics.rowRadius
        box.layer.cornerCurve = .continuous
        box.layer.borderWidth = 1
        box.clipsToBounds = true
        box.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(box)
        stack.axis = .horizontal
        stack.distribution = .fill
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        let leading = box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let height = box.heightAnchor.constraint(equalToConstant: 34)
        height.priority = .defaultHigh
        self.leading = leading
        self.height = height
        NSLayoutConstraint.activate([
            leading, height,
            box.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            box.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            box.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        isAccessibilityElement = true
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ models: [TabViewModel], grouped: Bool, height: CGFloat) {
        self.models = models
        leading?.constant = grouped ? 14 : 0
        self.height?.constant = height - 2
        holdsActive = models.contains { $0.active }
        while segments.count > models.count {
            segments.removeLast().removeFromSuperview()
        }
        stack.arrangedSubviews.filter { !($0 is SplitSegmentView) }.forEach { $0.removeFromSuperview() }
        while segments.count < models.count {
            let segment = SplitSegmentView()
            segment.onSelect = { [weak self, weak segment] flags in
                guard let id = segment?.tabID else { return }
                self?.onSelect?(id, flags)
            }
            segment.onClose = { [weak self, weak segment] in
                guard let id = segment?.tabID else { return }
                self?.onClose?(id)
            }
            segments.append(segment)
        }
        NSLayoutConstraint.deactivate(equalWidths)
        equalWidths = []
        for (index, (segment, model)) in zip(segments, models).enumerated() {
            if index > 0 { stack.addArrangedSubview(DividerView(vertical: true)) }
            stack.addArrangedSubview(segment)
            segment.configure(model)
            if index > 0 { equalWidths.append(segment.widthAnchor.constraint(equalTo: segments[0].widthAnchor)) }
        }
        NSLayoutConstraint.activate(equalWidths)
        let titles = models.map(\.title)
        let list = titles.count > 1 ? titles.dropLast().joined(separator: ", ") + " and " + (titles.last ?? "") : titles.joined()
        accessibilityLabel = "Split view: \(list)"
        accessibilityTraits = holdsActive ? [.button, .selected] : .button
        accessibilityCustomActions = models.map { model in
            UIAccessibilityCustomAction(name: "Show \(model.title)") { [weak self] _ in
                self?.onSelect?(model.id, [])
                return true
            }
        }
        restyle()
    }

    /// The pane under `point` (in the cell's coordinates).
    func paneID(at point: CGPoint) -> UUID? {
        let local = convert(point, to: stack)
        return segments.first { $0.frame.insetBy(dx: -1, dy: -4).contains(local) }?.tabID ?? models.first?.id
    }

    /// VoiceOver activation shows the focused pane, or the first.
    override func accessibilityActivate() -> Bool {
        guard let model = models.first(where: \.active) ?? models.first else { return false }
        onSelect?(model.id, [])
        return true
    }

    func themeDidChange(_ theme: CurioTheme) { restyle() }

    private func restyle() {
        let theme = ThemeCenter.shared.theme
        box.layer.borderColor = (holdsActive ? theme.rowActiveBorder : theme.divider).uiColor.cgColor
        box.backgroundColor = holdsActive ? theme.rowHover.uiColor : .clear
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        segments.forEach { $0.prepareForReuse() }
    }
}

/// One pane in a sidebar split row.
final class SplitSegmentView: UIView, ThemeObserving {
    private(set) var tabID: UUID?
    private let favicon = FaviconView(size: 14)
    private let title = UILabel()
    private var paneFocused = false
    private var hovered = false
    var onSelect: ((UIKeyModifierFlags) -> Void)?
    var onClose: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = CurioFont.sm()
        title.adjustsFontForContentSizeCategory = true
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [favicon, title])
        row.spacing = 7
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        addGestureRecognizer(tap)
        // A middle click closes the pane's tab, as on a tab row.
        let middle = UITapGestureRecognizer(target: self, action: #selector(middleClicked(_:)))
        middle.buttonMaskRequired = .button(3)
        addGestureRecognizer(middle)
        HoverTracker(self) { [weak self] in
            self?.hovered = $0
            self?.restyle()
        }
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ model: TabViewModel) {
        tabID = model.id
        paneFocused = model.active
        title.text = model.title
        title.font = CurioFont.sm(model.active ? .medium : .regular)
        favicon.configure(label: model.title, url: model.favicon, pageURL: model.url, loading: model.loading)
        favicon.alpha = model.asleep && !model.active ? 0.65 : 1
        restyle()
    }

    func prepareForReuse() {
        favicon.prepareForReuse()
        hovered = false
    }

    func themeDidChange(_ theme: CurioTheme) { restyle() }

    private func restyle() {
        let theme = ThemeCenter.shared.theme
        backgroundColor = paneFocused ? theme.rowActive.uiColor : (hovered ? theme.rowHover.uiColor : .clear)
        title.textColor = paneFocused ? theme.rowActiveText.uiColor : (hovered ? theme.text.uiColor : theme.textMuted.uiColor)
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended { onSelect?(tap.modifierFlags) }
    }

    @objc private func middleClicked(_ tap: UITapGestureRecognizer) {
        if tap.state == .ended { onClose?() }
    }
}
