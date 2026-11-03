import UIKit

/// The phone's bottom bar (in the thumb zone): tabs, back and forward, the
/// address pill, the assistant and a menu of everything else.
final class BottomBarView: UIView, ThemeObserving {
    let sidebarButton = IconButton(.sidebar, size: .medium, label: "Show Tabs")
    let backButton = IconButton(.back, size: .medium, label: "Back")
    let forwardButton = IconButton(.forward, size: .medium, label: "Forward")
    let pill = URLPillView(trailing: IconButton(.reload, size: .small, label: "Reload"))
    let assistantButton = IconButton(.sparkles, size: .medium, label: "Curio Assistant")
    let moreButton = IconButton(.ellipsis, size: .medium, label: "More")
    private var loading = false
    var onCommand: ((CurioCommand) -> Void)?

    init() {
        super.init(frame: .zero)
        moreButton.showsMenuAsPrimaryAction = true
        let stack = UIStackView(arrangedSubviews: [sidebarButton, backButton, forwardButton, pill, assistantButton, moreButton])
        stack.spacing = 4
        stack.alignment = .center
        stack.setCustomSpacing(8, after: forwardButton)
        stack.setCustomSpacing(8, after: pill)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.heightAnchor.constraint(equalToConstant: 40),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -4),
            pill.heightAnchor.constraint(equalToConstant: 40),
        ])
        for (button, command) in [(sidebarButton, CurioCommand.toggleSidebar), (backButton, .goBack),
                                  (forwardButton, .goForward), (assistantButton, .toggleAIPanel)] {
            button.addAction(UIAction { [weak self] _ in self?.onCommand?(command) }, for: .primaryActionTriggered)
        }
        pill.trailingButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onCommand?(loading ? .stopLoading : .reload)
        }, for: .primaryActionTriggered)
        pill.addAction(UIAction { [weak self] _ in self?.onCommand?(.editURL) }, for: .primaryActionTriggered)
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ nav: PageNav, assistantOpen: Bool) {
        loading = nav.loading
        backButton.isEnabled = nav.canGoBack
        forwardButton.isEnabled = nav.canGoForward
        pill.update(nav)
        pill.trailingButton.setIcon(nav.loading ? .close : .reload, label: nav.loading ? "Stop" : "Reload")
        pill.trailingButton.isHidden = nav.page == nil
        assistantButton.isToggled = assistantOpen
    }

    func themeDidChange(_ theme: CurioTheme) {}
}
