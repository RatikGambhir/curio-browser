import UIKit

/// Curio's new tab page: the logo, a greeting, a search box, favorite and
/// frequent sites, and shortcuts to the assistant and history.
final class NewTabPageView: UIView, ThemeObserving {
    private let scroll = UIScrollView()
    private let greeting = UILabel()
    private let spaceLabel = UILabel()
    private let searchBox = TapControl()
    private let searchIcon = UIImageView(image: Icon.search.image(15))
    private let searchLabel = UILabel()
    private let kbd = KbdLabel("⌘T")
    private let tiles = FlowLayoutView()
    var onCommand: ((CurioCommand) -> Void)?
    var onOpen: ((String) -> Void)?

    init() {
        super.init(frame: .zero)
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        let logo = LogoView(size: 76)
        greeting.text = "Where to next?"
        greeting.font = CurioFont.size(26, .semibold)
        greeting.adjustsFontForContentSizeCategory = true
        greeting.textAlignment = .center
        greeting.accessibilityTraits = .header
        spaceLabel.font = CurioFont.sm()
        spaceLabel.textAlignment = .center
        let titles = UIStackView(arrangedSubviews: [greeting, spaceLabel])
        titles.axis = .vertical
        titles.spacing = 4
        configureSearchBox()
        tiles.spacing = 6
        let ask = CurioButton("Ask Curio", icon: .sparkles, style: .ghost, action: UIAction { [weak self] _ in self?.onCommand?(.toggleAIPanel) })
        let history = CurioButton("History", icon: .history, style: .ghost, action: UIAction { [weak self] _ in self?.onCommand?(.showHistory) })
        let buttons = UIStackView(arrangedSubviews: [ask, history])
        buttons.spacing = 8
        let stack = UIStackView(arrangedSubviews: [logo, titles, searchBox, tiles, buttons])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 22
        stack.translatesAutoresizingMaskIntoConstraints = false
        // The content is centered vertically when it is shorter than the page.
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(container)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            container.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            searchBox.widthAnchor.constraint(lessThanOrEqualToConstant: 560),
            searchBox.widthAnchor.constraint(equalTo: stack.widthAnchor).withPriority(.defaultHigh),
            searchBox.heightAnchor.constraint(equalToConstant: 50),
            tiles.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            tiles.widthAnchor.constraint(equalTo: stack.widthAnchor).withPriority(.defaultHigh),
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func configureSearchBox() {
        searchLabel.text = "Search the web, enter an address, or ask Curio"
        searchLabel.font = CurioFont.size(15)
        searchLabel.adjustsFontForContentSizeCategory = true
        searchLabel.lineBreakMode = .byTruncatingTail
        searchIcon.setContentHuggingPriority(.required, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [searchIcon, searchLabel, kbd])
        stack.spacing = 12
        stack.alignment = .center
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
        ])
        searchBox.layer.cornerRadius = 14
        searchBox.layer.cornerCurve = .continuous
        searchBox.layer.borderWidth = 1
        searchBox.addAction(UIAction { [weak self] _ in self?.onCommand?(.editURL) }, for: .primaryActionTriggered)
        searchBox.isAccessibilityElement = true
        searchBox.accessibilityLabel = searchLabel.text
        searchBox.accessibilityTraits = .searchField
        HoverTracker(searchBox) { [weak self] inside in
            let theme = ThemeCenter.shared.theme
            self?.searchBox.layer.borderColor = (inside ? theme.accent : theme.surfaceBorder).uiColor.cgColor
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        searchBox.layer.shadowPath = UIBezierPath(roundedRect: searchBox.bounds, cornerRadius: 14).cgPath
    }

    /// Fills in the space name, keyboard hint and site tiles.
    func update(spaceName: String, sites: [(title: String, url: String, favicon: String?)], showsKeyboardHint: Bool) {
        spaceLabel.text = "You’re in \(spaceName)"
        kbd.isHidden = !showsKeyboardHint
        tiles.setItems(sites.prefix(8).map { site in
            SiteTileView(title: site.title, url: site.url, favicon: site.favicon, action: UIAction { [weak self] _ in
                self?.onOpen?(site.url)
            })
        })
        tiles.isHidden = sites.isEmpty
    }

    func themeDidChange(_ theme: CurioTheme) {
        backgroundColor = theme.card.uiColor
        greeting.textColor = theme.text.uiColor
        spaceLabel.textColor = theme.textFaint.uiColor
        searchBox.backgroundColor = theme.surface.uiColor
        searchBox.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        Shadow.sm.apply(to: searchBox.layer, dark: theme.appearance == .dark)
        searchIcon.tintColor = theme.textFaint.uiColor
        searchLabel.textColor = theme.textFaint.uiColor
    }
}
