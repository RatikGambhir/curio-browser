import UIKit

/// Curio's settings. Wide screens show the section list beside the
/// content; phones drill down from a list.
final class SettingsViewController: UIViewController {
    private let session: BrowserSession
    private var section: SettingsSection
    private let compact: Bool
    private let nav = UIStackView()
    private var navRows: [SettingsSection: ListRowControl] = [:]
    private let contentScroll = UIScrollView()
    private var content: SettingsSectionView?

    init(session: BrowserSession, section: SettingsSection?, compact: Bool) {
        self.session = session
        self.section = section ?? .general
        self.compact = compact
        super.init(nibName: nil, bundle: nil)
        title = "Settings"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = ThemeCenter.shared.theme.surface.uiColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
            self?.view.endEditing(true)
            self?.dismiss(animated: true)
        })
        nav.axis = .vertical
        nav.spacing = 2
        for item in SettingsSection.allCases {
            let row = ListRowControl(height: compact ? 44 : 32, action: UIAction { [weak self] _ in self?.open(item) })
            row.row.muted = true
            row.row.selectedStyle = .accent
            row.row.setSpacing(8)
            let icon = UIImageView(image: item.icon.image(13))
            icon.contentMode = .center
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            row.row.setLeading(icon)
            row.row.onRestyle = { theme, selected in icon.tintColor = (selected ? theme.accentText : theme.textMuted).uiColor }
            row.row.setTitle(item.label)
            if compact {
                let chevron = UIImageView(image: Icon.chevronRight.image(11))
                chevron.tintColor = ThemeCenter.shared.theme.textFaint.uiColor
                row.row.trailingStack.addArrangedSubview(chevron)
            }
            navRows[item] = row
            nav.addArrangedSubview(row)
        }
        nav.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nav)
        if compact {
            NSLayoutConstraint.activate([
                nav.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
                nav.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
                nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            ])
        } else {
            contentScroll.translatesAutoresizingMaskIntoConstraints = false
            contentScroll.alwaysBounceVertical = true
            contentScroll.keyboardDismissMode = .interactive
            view.addSubview(contentScroll)
            NSLayoutConstraint.activate([
                nav.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                nav.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                nav.widthAnchor.constraint(equalToConstant: 170),
                contentScroll.leadingAnchor.constraint(equalTo: nav.trailingAnchor, constant: 16),
                contentScroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                contentScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                contentScroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            ])
            show(section)
        }
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        if compact, let initial = pendingInitial {
            pendingInitial = nil
            open(initial, animated: false)
        }
    }

    /// On phones, a section passed at creation opens right away.
    private lazy var pendingInitial: SettingsSection? = compact && section != .general ? section : nil

    private func open(_ item: SettingsSection, animated: Bool = true) {
        if compact {
            let controller = SettingsDetailViewController(section: item, session: session)
            navigationController?.pushViewController(controller, animated: animated)
        } else {
            show(item)
        }
    }

    private func show(_ item: SettingsSection) {
        section = item
        for (key, row) in navRows { row.isSelected = key == item }
        content?.removeFromSuperview()
        let view = SettingsSectionView(section: item, session: session)
        view.host = self
        view.translatesAutoresizingMaskIntoConstraints = false
        contentScroll.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentScroll.frameLayoutGuide.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentScroll.frameLayoutGuide.trailingAnchor, constant: -16),
            view.topAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.topAnchor, constant: 14),
            view.bottomAnchor.constraint(equalTo: contentScroll.contentLayoutGuide.bottomAnchor, constant: -20),
        ])
        content = view
    }
}
