import UIKit

/// The library: Arc-style collections. A rail of sections sits beside a
/// searchable list. Shown in place of the sidebar on wide screens and as a
/// sheet on phones.
final class LibraryViewController: UIViewController, ThemeObserving {
    static let railWidth: CGFloat = 84
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp"]
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv"]

    private let session: BrowserSession
    weak var delegate: LibraryDelegate?
    private var section: LibrarySection = .archivedTabs
    private let rail = UIStackView()
    private var railItems: [LibrarySection: RailItemView] = [:]
    private let search = SearchFieldView(placeholder: LibrarySection.archivedTabs.searchPlaceholder)
    private let sectionLabel = SectionLabel(LibrarySection.archivedTabs.label)
    private let scroll = UIScrollView()
    private let list = UIStackView()
    private let closeButton = IconButton(.back, label: "Back to Sidebar")
    /// In a sheet the close button reads "Done".
    var presentedAsSheet = false {
        didSet { closeButton.setIcon(presentedAsSheet ? .close : .back, label: presentedAsSheet ? "Close Library" : "Back to Sidebar") }
    }

    init(session: BrowserSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        rail.axis = .vertical
        rail.spacing = 4
        for item in LibrarySection.allCases {
            let view = RailItemView(icon: item.icon, title: item.label, action: UIAction { [weak self] _ in self?.select(item) })
            railItems[item] = view
            rail.addArrangedSubview(view)
        }
        let railScroll = UIScrollView()
        railScroll.showsVerticalScrollIndicator = false
        railScroll.translatesAutoresizingMaskIntoConstraints = false
        rail.translatesAutoresizingMaskIntoConstraints = false
        railScroll.addSubview(rail)
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.libraryDidClose() }, for: .primaryActionTriggered)
        let closeRow = UIView()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeRow.addSubview(closeButton)
        let railColumn = UIStackView(arrangedSubviews: [railScroll, closeRow])
        railColumn.axis = .vertical
        railColumn.translatesAutoresizingMaskIntoConstraints = false

        search.textField.addAction(UIAction { [weak self] _ in self?.reload() }, for: .editingChanged)
        search.textField.returnKeyType = .done
        list.axis = .vertical
        list.spacing = 2
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        let pane = UIView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        search.translatesAutoresizingMaskIntoConstraints = false
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(search)
        pane.addSubview(sectionLabel)
        pane.addSubview(scroll)
        view.addSubview(railColumn)
        view.addSubview(pane)
        NSLayoutConstraint.activate([
            railColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            railColumn.topAnchor.constraint(equalTo: view.topAnchor),
            railColumn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            railColumn.widthAnchor.constraint(equalToConstant: Self.railWidth),
            rail.leadingAnchor.constraint(equalTo: railScroll.frameLayoutGuide.leadingAnchor, constant: 8),
            rail.trailingAnchor.constraint(equalTo: railScroll.frameLayoutGuide.trailingAnchor, constant: -8),
            rail.topAnchor.constraint(equalTo: railScroll.contentLayoutGuide.topAnchor, constant: 8),
            rail.bottomAnchor.constraint(equalTo: railScroll.contentLayoutGuide.bottomAnchor, constant: -8),
            closeRow.heightAnchor.constraint(equalToConstant: 44),
            closeButton.leadingAnchor.constraint(equalTo: closeRow.leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: closeRow.centerYAnchor),
            pane.leadingAnchor.constraint(equalTo: railColumn.trailingAnchor),
            pane.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pane.topAnchor.constraint(equalTo: view.topAnchor),
            pane.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            search.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 2),
            search.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -10),
            search.topAnchor.constraint(equalTo: pane.topAnchor, constant: 8),
            sectionLabel.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 14),
            sectionLabel.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sectionLabel.bottomAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 4),
            list.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -10),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -10),
            list.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor, constant: -10),
        ])
        ThemeCenter.shared.observe(self)
        select(.archivedTabs)
    }

    func themeDidChange(_ theme: CurioTheme) {
        if isViewLoaded { reload() }
    }

    func select(_ section: LibrarySection) {
        self.section = section
        for (item, view) in railItems { view.isSelected = item == section }
        search.textField.text = ""
        search.textField.placeholder = section.searchPlaceholder
        search.themeDidChange(ThemeCenter.shared.theme)
        sectionLabel.text = section.label
        reload()
    }

    /// Rebuilds the list for the current section and search.
    func reload() {
        guard isViewLoaded else { return }
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = (search.textField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rows: [UIView] = switch section {
        case .media: mediaRows(query)
        case .downloads: downloadRows(query)
        case .spaces: spaceRows(query)
        case .archivedTabs: archiveRows(query)
        default: []
        }
        if rows.isEmpty {
            let empty: EmptyStateView
            if !query.isEmpty && section.hasContent {
                empty = EmptyStateView(title: "No results", description: "Nothing in \(section.label) matches “\(query)”.", icon: .search)
            } else {
                empty = EmptyStateView(title: section.emptyCopy.title, description: section.emptyCopy.description, icon: section.icon)
            }
            list.addArrangedSubview(empty)
            empty.heightAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
        } else {
            rows.forEach { list.addArrangedSubview($0) }
            let spacer = UIView()
            spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
            list.addArrangedSubview(spacer)
        }
    }

    private static func matches(_ query: String, _ fields: [String]) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { word in fields.contains { $0.localizedStandardContains(word) } }
    }

    private func row(title: String, subtitle: String?, favicon: String?, label: String, icon: Icon? = nil, iconColor: UIColor? = nil,
                     action: @escaping () -> Void) -> ListRowControl {
        let control = ListRowControl(height: 44, action: UIAction { _ in action() })
        if let icon {
            let view = UIImageView(image: icon.image(14))
            view.tintColor = iconColor
            view.contentMode = .center
            view.widthAnchor.constraint(equalToConstant: 18).isActive = true
            control.row.setLeading(view)
        } else {
            let view = FaviconView(size: 16)
            view.configure(label: label, url: favicon)
            control.row.setLeading(view)
        }
        control.row.setTitle(title, subtitle: subtitle)
        return control
    }

    private func downloadRows(_ query: String) -> [UIView] {
        let theme = ThemeCenter.shared.theme
        return session.services.downloads.records.filter { Self.matches(query, [$0.displayName, $0.url]) }.map { record in
            let (icon, color, status): (Icon, UIColor, String) = switch record.state {
            case .completed: (.checkCircle, theme.success.uiColor, "Completed")
            case .failed: (.xCircle, theme.danger.uiColor, "Failed")
            case .inProgress: (.download, theme.accent.uiColor, "Downloading…")
            }
            return row(title: record.displayName, subtitle: "\(status) · \(Curio.displayHost(record.url))", favicon: nil,
                       label: record.displayName, icon: icon, iconColor: color) { [weak self] in
                if record.state == .completed, let url = record.fileURL { self?.delegate?.libraryPreview(url) }
            }
        }
    }

    private func mediaRows(_ query: String) -> [UIView] {
        let items = session.services.downloads.records.compactMap { record -> (String, URL, Bool)? in
            guard record.state == .completed, let url = record.fileURL else { return nil }
            let ext = url.pathExtension.lowercased()
            let image = Self.imageExtensions.contains(ext)
            guard image || Self.videoExtensions.contains(ext), Self.matches(query, [record.displayName, record.url]) else { return nil }
            return (record.displayName, url, image)
        }
        var rows: [UIView] = []
        var index = 0
        while index < items.count {
            let pair = items[index..<min(index + 2, items.count)].map { name, url, image in
                MediaTileView(name: name, url: url, image: image, action: UIAction { [weak self] _ in self?.delegate?.libraryPreview(url) }) as UIView
            }
            let row = UIStackView(arrangedSubviews: pair.count == 2 ? pair : pair + [UIView()])
            row.spacing = 8
            row.distribution = .fillEqually
            row.alignment = .top
            rows.append(row)
            index += 2
        }
        if !rows.isEmpty { list.spacing = 10 } else { list.spacing = 2 }
        return rows
    }

    private func spaceRows(_ query: String) -> [UIView] {
        list.spacing = 2
        let theme = ThemeCenter.shared.theme
        let workspace = session.workspace
        var rows: [UIView] = []
        for space in workspace.spaces {
            let spaceMatches = Self.matches(query, [space.name])
            let tabs = space.strip.orderedTabIDs.compactMap(space.strip.tab).filter { spaceMatches || Self.matches(query, [$0.displayTitle, $0.url]) }
            guard spaceMatches || !tabs.isEmpty else { continue }
            let header = ListRowControl(height: 34, action: UIAction { [weak self] _ in
                self?.session.switchSpace(space.id)
                self?.delegate?.libraryDidClose()
            })
            header.row.setLeading(ColorDotView(color: CurioTheme.swatch(space.color)))
            header.row.setTitle("\(space.icon)  \(space.name)")
            header.row.titleWeight = .semibold
            header.row.setSpacing(8)
            if space.id == workspace.activeSpaceID {
                let current = UILabel()
                current.text = "Current"
                current.font = CurioFont.xs()
                current.textColor = theme.accentText.uiColor
                header.row.trailingStack.addArrangedSubview(current)
            }
            let count = UILabel()
            count.text = "\(space.strip.count)"
            count.font = CurioFont.xs()
            count.textColor = theme.textFaint.uiColor
            header.row.trailingStack.addArrangedSubview(count)
            rows.append(header)
            for tab in tabs {
                let tabRow = row(title: tab.displayTitle, subtitle: Curio.displayHost(tab.url), favicon: tab.faviconURL, label: tab.displayTitle) { [weak self] in
                    self?.session.activateTab(tab.id)
                    self?.delegate?.libraryDidClose()
                }
                tabRow.row.setLeadingInset(16)
                rows.append(tabRow)
            }
        }
        return rows
    }

    private func archiveRows(_ query: String) -> [UIView] {
        list.spacing = 2
        let workspace = session.workspace
        return workspace.closedTabs.filter { Self.matches(query, [$0.tab.displayTitle, $0.tab.url]) }.map { closed in
            let host = Curio.displayHost(closed.tab.url)
            let subtitle = workspace.space(closed.space).map { "\(host) · \($0.name)" } ?? host
            let control = row(title: closed.tab.displayTitle, subtitle: subtitle, favicon: closed.tab.faviconURL, label: closed.tab.displayTitle) { [weak self] in
                self?.session.reopenArchivedTab(closed.tab.id)
                self?.delegate?.libraryDidClose()
            }
            control.toolTip = "Reopen Tab"
            control.accessibilityHint = "Reopens the tab"
            return control
        }
    }
}
