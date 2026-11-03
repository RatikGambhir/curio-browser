import UIKit

/// The top row of the page card with vertical tabs: navigation, the page's
/// address, and the assistant and downloads buttons.
final class PageBarView: UIView, ThemeObserving {
    let sidebarButton = IconButton(.sidebar, label: "Hide Sidebar")
    let backButton = IconButton(.back, label: "Back")
    let forwardButton = IconButton(.forward, label: "Forward")
    let reloadButton = IconButton(.reload, label: "Reload")
    let address = AddressView(showsTitle: true)
    let assistantButton = IconButton(.sparkles, label: "Curio Assistant")
    let downloadsButton = IconButton(.download, label: "Downloads")
    private let divider = DividerView()
    private var loading = false
    var onCommand: ((CurioCommand) -> Void)?

    init() {
        super.init(frame: .zero)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let gap = UIView()
        gap.widthAnchor.constraint(equalToConstant: 6).isActive = true
        let stack = UIStackView(arrangedSubviews: [sidebarButton, backButton, forwardButton, reloadButton, gap, address, spacer, assistantButton, downloadsButton])
        stack.spacing = 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        addSubview(divider)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            address.heightAnchor.constraint(equalToConstant: 28),
            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12),
            heightAnchor.constraint(equalToConstant: Metrics.toolbarHeight),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        bind(sidebarButton, .toggleSidebar)
        bind(backButton, .goBack)
        bind(forwardButton, .goForward)
        bind(assistantButton, .toggleAIPanel)
        bind(downloadsButton, .showDownloads)
        reloadButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onCommand?(loading ? .stopLoading : .reload)
        }, for: .primaryActionTriggered)
        address.addAction(UIAction { [weak self] _ in self?.onCommand?(.editURL) }, for: .primaryActionTriggered)
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func bind(_ button: IconButton, _ command: CurioCommand) {
        button.addAction(UIAction { [weak self] _ in self?.onCommand?(command) }, for: .primaryActionTriggered)
    }

    func update(_ nav: PageNav, sidebarVisible: Bool, assistantOpen: Bool, showsSidebarButton: Bool) {
        loading = nav.loading
        backButton.isEnabled = nav.canGoBack
        forwardButton.isEnabled = nav.canGoForward
        reloadButton.setIcon(nav.loading ? .close : .reload, label: nav.loading ? "Stop" : "Reload")
        sidebarButton.setIcon(.sidebar, label: sidebarVisible ? "Hide Sidebar" : "Show Sidebar")
        sidebarButton.isHidden = !showsSidebarButton
        assistantButton.isToggled = assistantOpen
        address.update(nav)
    }

    func themeDidChange(_ theme: CurioTheme) {}
}
