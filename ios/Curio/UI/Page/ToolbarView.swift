import UIKit

/// The toolbar above the page with horizontal tabs: the space picker,
/// navigation, the URL pill, and window tools.
final class ToolbarView: UIView {
    let spacePicker = UIButton(configuration: .plain())
    let backButton = IconButton(.back, label: "Back")
    let forwardButton = IconButton(.forward, label: "Forward")
    let reloadButton = IconButton(.reload, label: "Reload")
    let pill = URLPillView(trailing: IconButton(.link, size: .xsmall, label: "Copy Link"))
    let assistantButton = IconButton(.sparkles, label: "Curio Assistant")
    let downloadsButton = IconButton(.download, label: "Downloads")
    let settingsButton = IconButton(.settings, label: "Settings")
    private var loading = false
    var onCommand: ((CurioCommand) -> Void)?

    init() {
        super.init(frame: .zero)
        spacePicker.showsMenuAsPrimaryAction = true
        spacePicker.setContentHuggingPriority(.required, for: .horizontal)
        let pillHost = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pillHost.addSubview(pill)
        let pillWidth = pill.widthAnchor.constraint(equalTo: pillHost.widthAnchor)
        pillWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: pillHost.centerXAnchor),
            pill.topAnchor.constraint(equalTo: pillHost.topAnchor),
            pill.bottomAnchor.constraint(equalTo: pillHost.bottomAnchor),
            pill.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            pill.widthAnchor.constraint(lessThanOrEqualTo: pillHost.widthAnchor),
            pillWidth,
            pill.heightAnchor.constraint(equalToConstant: 34),
        ])
        let stack = UIStackView(arrangedSubviews: [spacePicker, backButton, forwardButton, reloadButton, pillHost, assistantButton, downloadsButton, settingsButton])
        stack.spacing = 4
        stack.alignment = .center
        stack.setCustomSpacing(10, after: reloadButton)
        stack.setCustomSpacing(10, after: pillHost)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: Metrics.toolbarHeight),
        ])
        for (button, command) in [(backButton, CurioCommand.goBack), (forwardButton, .goForward), (assistantButton, .toggleAIPanel),
                                  (downloadsButton, .showDownloads), (settingsButton, .openSettings), (pill.trailingButton, .copyURL)] {
            button.addAction(UIAction { [weak self] _ in self?.onCommand?(command) }, for: .primaryActionTriggered)
        }
        reloadButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onCommand?(loading ? .stopLoading : .reload)
        }, for: .primaryActionTriggered)
        pill.addAction(UIAction { [weak self] _ in self?.onCommand?(.editURL) }, for: .primaryActionTriggered)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(_ nav: PageNav, space: Space, assistantOpen: Bool, spaceMenu: UIMenu) {
        loading = nav.loading
        backButton.isEnabled = nav.canGoBack
        forwardButton.isEnabled = nav.canGoForward
        reloadButton.setIcon(nav.loading ? .close : .reload, label: nav.loading ? "Stop" : "Reload")
        pill.update(nav)
        pill.trailingButton.isHidden = nav.page == nil
        assistantButton.isToggled = assistantOpen
        let theme = ThemeCenter.shared.theme
        var configuration = UIButton.Configuration.plain()
        configuration.title = "\(space.icon)  \(space.name)"
        configuration.image = Icon.chevronDown.image(10)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 6
        configuration.baseForegroundColor = theme.text.uiColor
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = CurioFont.sm(.medium)
            return attributes
        }
        spacePicker.configuration = configuration
        spacePicker.menu = spaceMenu
    }
}
