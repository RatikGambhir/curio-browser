import UIKit

/// A tab folder: chevron, colored folder icon, name and (collapsed) count.
/// While renaming, the name becomes a text field in place.
final class GroupRowCell: UICollectionViewListCell {
    let row = ListRowView()
    private let chevron = UIImageView()
    private let folder = UIImageView()
    private let countLabel = UILabel()
    private let nameField = FolderNameField()
    private var focusTask: Task<Void, Never>?
    private(set) var isEditingName = false
    /// The edited name was saved (Return or tapping away).
    var onCommitName: ((String) -> Void)?
    /// The edit was cancelled (Escape).
    var onCancelName: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundConfiguration = .clear()
        chevron.contentMode = .center
        folder.contentMode = .center
        let leading = UIStackView(arrangedSubviews: [chevron, folder])
        leading.spacing = 8
        leading.alignment = .center
        NSLayoutConstraint.activate([chevron.widthAnchor.constraint(equalToConstant: 16), folder.widthAnchor.constraint(equalToConstant: 18)])
        row.muted = true
        row.titleWeight = .medium
        row.setSpacing(8)
        row.setLeading(leading)
        countLabel.font = CurioFont.xs()
        row.trailingStack.addArrangedSubview(countLabel)
        row.onRestyle = { [weak self] theme, _ in
            self?.countLabel.textColor = theme.textFaint.uiColor
            self?.chevron.tintColor = theme.textMuted.uiColor
            self?.nameField.textColor = theme.text.uiColor
            self?.nameField.tintColor = theme.accent.uiColor
        }
        nameField.font = CurioFont.sm(.medium)
        nameField.isHidden = true
        // The field takes the title's frame; its own text width must never
        // squeeze the title.
        nameField.setContentHuggingPriority(UILayoutPriority(1), for: .horizontal)
        nameField.setContentCompressionResistancePriority(UILayoutPriority(1), for: .horizontal)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.onCommit = { [weak self] name in self?.onCommitName?(name) }
        nameField.onCancel = { [weak self] in self?.onCancelName?() }
        row.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameField.leadingAnchor.constraint(equalTo: row.titleLabel.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: row.titleLabel.trailingAnchor),
            nameField.centerYAnchor.constraint(equalTo: row.titleLabel.centerYAnchor),
        ])
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1),
        ])
        HoverTracker(self) { [weak self] in self?.row.isHovered = $0 }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ group: TabGroup, height: CGFloat, editing: Bool = false) {
        row.setHeight(height)
        row.setTitle(group.name)
        chevron.image = (group.collapsed ? Icon.chevronRight : Icon.chevronDown).image(10, weight: .semibold)
        folder.image = (group.collapsed ? Icon.folder : Icon.folderFill).image(13)
        folder.tintColor = CurioTheme.swatch(group.color)
        countLabel.text = "\(group.tabs.count)"
        countLabel.isHidden = !group.collapsed
        chevron.tintColor = ThemeCenter.shared.theme.textMuted.uiColor
        countLabel.textColor = ThemeCenter.shared.theme.textFaint.uiColor
        accessibilityLabel = "\(group.name) folder, \(group.tabs.count) tabs"
        accessibilityValue = group.collapsed ? "Collapsed" : "Expanded"
        nameField.textColor = ThemeCenter.shared.theme.text.uiColor
        nameField.tintColor = ThemeCenter.shared.theme.accent.uiColor
        setEditingName(editing, name: group.name)
    }

    /// Enters or leaves rename mode. Re-entering while already editing keeps
    /// what has been typed (the sidebar reconfigures rows often).
    private func setEditingName(_ editing: Bool, name: String) {
        guard editing != isEditingName else { return }
        isEditingName = editing
        nameField.isHidden = !editing
        row.titleLabel.alpha = editing ? 0 : 1
        row.isHovered = editing
        // VoiceOver reaches the field instead of the row while editing.
        isAccessibilityElement = !editing
        focusTask?.cancel()
        focusTask = nil
        if editing {
            nameField.prepare(name: name)
            focusName()
        } else {
            nameField.reset()
        }
    }

    /// Focuses the field, retrying briefly when it can't take focus yet: the
    /// row may still be off screen, or a context menu still dismissing.
    private func focusName() {
        guard !nameField.focusAndSelectAll() else { return }
        focusTask = Task { [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled, isEditingName else { return }
                if nameField.focusAndSelectAll() { return }
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil && isEditingName && !nameField.isFirstResponder { focusName() }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        focusTask?.cancel()
        focusTask = nil
        isEditingName = false
        nameField.reset()
        nameField.isHidden = true
        row.titleLabel.alpha = 1
        row.isHovered = false
        isAccessibilityElement = true
    }

    override var isHighlighted: Bool {
        didSet { row.isPressed = isHighlighted }
    }
}
