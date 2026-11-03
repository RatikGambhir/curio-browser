import UIKit

/// The command bar: one place to type a URL, search the web, jump to an open
/// tab, revisit history or bookmarks, run a browser command, or ask Curio.
/// Shown over the browser with a scrim.
final class CommandBarViewController: UIViewController, UITextFieldDelegate, UICollectionViewDelegate, ThemeObserving {
    private let session: BrowserSession
    private let mode: CommandMode
    private let initialText: String
    private let compact: Bool
    private let scrim = UIControl()
    private let container = UIView()
    private let modeIcon = UIImageView()
    private let field = UITextField()
    private let hint: KbdLabel
    private let headerDivider = DividerView()
    private let footerDivider = DividerView()
    private let footer = UILabel()
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, CommandItemID>!
    private var items: [CommandItem] = []
    private var selected = 0
    private var listHeight: NSLayoutConstraint?
    private lazy var results = CommandResults(
        mode: mode, engine: session.settings.browsing.searchEngine, tabs: session.tabSuggestions,
        history: session.services.history, bookmarks: session.services.bookmarks
    )
    var onExecute: ((CommandTarget) -> Void)?
    var onDismiss: (() -> Void)?

    init(session: BrowserSession, mode: CommandMode, text: String, compact: Bool) {
        self.session = session
        self.mode = mode
        initialText = text
        self.compact = compact
        let hintText = switch mode {
        case .newTab: "New Tab"
        case .editURL: "Go"
        case .palette: "Commands"
        }
        hint = KbdLabel(hintText)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.addAction(UIAction { [weak self] _ in self?.onDismiss?() }, for: .touchUpInside)
        scrim.accessibilityLabel = "Close"
        view.addSubview(scrim)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 16
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        view.addSubview(container)
        let clip = UIView()
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.layer.cornerRadius = 16
        clip.layer.cornerCurve = .continuous
        clip.clipsToBounds = true
        container.addSubview(clip)

        modeIcon.image = (mode == .newTab ? Icon.plus : mode == .editURL ? Icon.globe : Icon.command).image(14)
        modeIcon.setContentHuggingPriority(.required, for: .horizontal)
        field.text = initialText
        field.placeholder = "Search, enter a URL, or ask Curio…"
        field.font = CurioFont.base()
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.keyboardType = .webSearch
        field.returnKeyType = .go
        field.clearButtonMode = compact ? .whileEditing : .never
        field.delegate = self
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hint.setContentHuggingPriority(.required, for: .horizontal)
        field.accessibilityLabel = "Search or enter address"
        field.addAction(UIAction { [weak self] _ in self?.rebuild() }, for: .editingChanged)
        hint.isHidden = compact
        let header = UIStackView(arrangedSubviews: [modeIcon, field, hint])
        header.spacing = 10
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        var list = UICollectionLayoutListConfiguration(appearance: .plain)
        list.showsSeparators = false
        list.backgroundColor = .clear
        let layout = UICollectionViewCompositionalLayout { _, environment in
            let section = NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            return section
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.keyboardDismissMode = .onDrag
        let registration = UICollectionView.CellRegistration<CommandRowCell, CommandItemID> { [weak self] cell, indexPath, _ in
            guard let self, items.indices.contains(indexPath.item) else { return }
            cell.configure(items[indexPath.item], selected: indexPath.item == selected)
            cell.onHover = { [weak self] in self?.select(indexPath.item, scroll: false) }
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }

        footer.text = "↑↓ to navigate     ⏎ to open     esc to close"
        footer.font = CurioFont.xs()
        footer.isHidden = compact
        footerDivider.isHidden = compact
        let footerRow = UIStackView(arrangedSubviews: [footer])
        footerRow.isLayoutMarginsRelativeArrangement = true
        footerRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        footerRow.isHidden = compact

        let column = UIStackView(arrangedSubviews: [header, headerDivider, collectionView, footerDivider, footerRow])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(column)

        let keyboardTop = view.keyboardLayoutGuide.topAnchor
        var constraints = [
            scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrim.topAnchor.constraint(equalTo: view.topAnchor),
            scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            clip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            clip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            clip.topAnchor.constraint(equalTo: container.topAnchor),
            clip.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            column.topAnchor.constraint(equalTo: clip.topAnchor),
            column.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),
            footerRow.heightAnchor.constraint(equalToConstant: 30),
            container.bottomAnchor.constraint(lessThanOrEqualTo: keyboardTop, constant: -12),
        ]
        if compact {
            constraints += [
                container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
                container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
                container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            ]
        } else {
            constraints += [
                container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                container.widthAnchor.constraint(equalToConstant: 660).withPriority(.defaultHigh),
                container.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32),
                container.topAnchor.constraint(equalTo: view.topAnchor, constant: 0).withPriority(.defaultLow),
                container.heightAnchor.constraint(lessThanOrEqualToConstant: 520),
            ]
        }
        let listHeight = collectionView.heightAnchor.constraint(equalToConstant: 0).withPriority(.defaultHigh)
        self.listHeight = listHeight
        constraints.append(listHeight)
        NSLayoutConstraint.activate(constraints)
        if !compact {
            // 16% down the screen, like the desktop.
            let top = NSLayoutConstraint(item: container, attribute: .top, relatedBy: .equal, toItem: view, attribute: .bottom, multiplier: 0.16, constant: 0)
            top.priority = .defaultHigh
            top.isActive = true
        }
        ThemeCenter.shared.observe(self)
        rebuild()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        field.becomeFirstResponder()
        field.selectAll(nil)
    }

    /// Fades and drops the bar into place.
    func animateIn() {
        guard ThemeCenter.shared.motionEnabled else { return }
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: -8)
        scrim.alpha = 0
        let animator = UIViewPropertyAnimator(duration: 0.14, timingParameters: Metrics.easeOutQuint)
        animator.addAnimations {
            self.container.alpha = 1
            self.container.transform = .identity
            self.scrim.alpha = 1
        }
        animator.startAnimation()
    }

    func themeDidChange(_ theme: CurioTheme) {
        scrim.backgroundColor = theme.scrim.uiColor
        container.backgroundColor = theme.surfaceRaised.uiColor
        container.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        Shadow.xxl.apply(to: container.layer, dark: theme.appearance == .dark)
        modeIcon.tintColor = theme.accentText.uiColor
        field.textColor = theme.text.uiColor
        field.tintColor = theme.accent.uiColor
        field.attributedPlaceholder = NSAttributedString(string: field.placeholder ?? "", attributes: [.foregroundColor: theme.textFaint.uiColor])
        footer.textColor = theme.textFaint.uiColor
        if dataSource != nil { applySnapshot() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        container.layer.shadowPath = UIBezierPath(roundedRect: container.bounds, cornerRadius: 16).cgPath
    }

    // MARK: - Results

    private func rebuild() {
        items = results.items(for: field.text ?? "")
        selected = 0
        applySnapshot()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, CommandItemID>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map { CommandItemID(key: $0.key) })
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
        // The list is as tall as its results, up to the space available.
        listHeight?.constant = items.isEmpty ? 0 : CGFloat(items.count) * 46 + 12
    }

    private func select(_ index: Int, scroll: Bool) {
        guard items.indices.contains(index), index != selected else { return }
        let previous = selected
        selected = index
        var snapshot = dataSource.snapshot()
        let ids = [previous, index].filter { items.indices.contains($0) }.map { CommandItemID(key: items[$0].key) }
        snapshot.reconfigureItems(ids)
        dataSource.apply(snapshot, animatingDifferences: false)
        if scroll { collectionView.scrollToItem(at: IndexPath(item: index, section: 0), at: [], animated: false) }
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        select(((selected + delta) % items.count + items.count) % items.count, scroll: true)
    }

    private func execute(_ index: Int) {
        guard items.indices.contains(index) else { return }
        onExecute?(items[index].target)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        execute(indexPath.item)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        execute(selected)
        return false
    }

    // MARK: - Keyboard

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(moveUp)),
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(moveDown)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(moveDown)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(moveUp)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(dismissBar)),
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands
    }

    @objc private func moveUp() { move(-1) }
    @objc private func moveDown() { move(1) }
    @objc private func dismissBar() { onDismiss?() }
}
