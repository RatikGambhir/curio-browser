import UIKit

/// One page card in the page area. It shows one tab: the tab's web view, or
/// a quiet placeholder while there is none (the new tab page of a pane that
/// isn't focused, or an internal page). The header slot holds the page bar
/// for the focused pane or a slim `PaneHeaderView` for the others. In a
/// split view the focused pane gets an accent outline.
final class PaneView: UIView, ThemeObserving, UIGestureRecognizerDelegate {
    let card = CardView()
    let headerSlot = UIView()
    let content = UIView()
    let header = PaneHeaderView()
    private let placeholder = PanePlaceholderView()
    private let outline = UIView()
    private(set) weak var hostedWebView: CurioWebView?
    private(set) var tabID: UUID?
    private var headerView: UIView?
    /// Shows the accent outline (the focused pane of a split view).
    var outlined = false { didSet { restyleOutline() } }
    /// Whether the pane is the focused one; taps only focus the others.
    var isFocusedPane = true
    /// A tap anywhere in an unfocused pane focuses it.
    var onFocus: ((UUID) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        let column = UIStackView(arrangedSubviews: [headerSlot, content])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(column)
        content.clipsToBounds = true
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(placeholder)
        outline.isUserInteractionEnabled = false
        outline.layer.cornerRadius = Metrics.cardRadius
        outline.layer.cornerCurve = .continuous
        outline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outline)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            column.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            column.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
            placeholder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            placeholder.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            placeholder.topAnchor.constraint(equalTo: content.topAnchor),
            placeholder.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            outline.leadingAnchor.constraint(equalTo: leadingAnchor),
            outline.trailingAnchor.constraint(equalTo: trailingAnchor),
            outline.topAnchor.constraint(equalTo: topAnchor),
            outline.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        headerSlot.isHidden = true
        // Taps inside a web view don't reliably reach UIKit recognizers; the
        // page bridge's focus message covers those. This catches the rest
        // (headers, placeholders, the new tab page).
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        addGestureRecognizer(tap)
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) { restyleOutline() }

    private func restyleOutline() {
        outline.layer.borderWidth = outlined ? 2 : 0
        outline.layer.borderColor = ThemeCenter.shared.theme.accent.uiColor.cgColor
    }

    /// Assigns the pane's tab.
    func setTab(_ id: UUID) {
        tabID = id
    }

    /// Puts `view` (the page bar, the slim header, or nothing) on top.
    func setHeader(_ view: UIView?) {
        if headerView === view, view?.superview === headerSlot {
            headerSlot.isHidden = view == nil
            return
        }
        if let headerView, headerView.superview === headerSlot { headerView.removeFromSuperview() }
        headerView = view
        headerSlot.isHidden = view == nil
        guard let view else { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        headerSlot.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: headerSlot.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: headerSlot.trailingAnchor),
            view.topAnchor.constraint(equalTo: headerSlot.topAnchor),
            view.bottomAnchor.constraint(equalTo: headerSlot.bottomAnchor),
        ])
    }

    /// Shows a web view in the content, above the placeholder.
    func host(_ webView: CurioWebView?) {
        if hostedWebView !== webView {
            if let hostedWebView, hostedWebView.superview === content { hostedWebView.removeFromSuperview() }
            hostedWebView = webView
            if let webView {
                webView.translatesAutoresizingMaskIntoConstraints = false
                content.insertSubview(webView, aboveSubview: placeholder)
                NSLayoutConstraint.activate([
                    webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    webView.topAnchor.constraint(equalTo: content.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                ])
            }
        } else if let webView, webView.superview !== content {
            // Another pane took it; take it back.
            hostedWebView = nil
            host(webView)
        }
    }

    /// Puts `view` (the new tab page) above the placeholder and below the
    /// page and overlays. The caller constrains it.
    func insertUnderPage(_ view: UIView) {
        content.insertSubview(view, aboveSubview: placeholder)
    }

    /// The quiet stand-in shown while the pane has no web view.
    func showPlaceholder(_ model: TabViewModel?, visible: Bool) {
        placeholder.isHidden = !visible
        if visible, let model { placeholder.configure(model) }
    }

    /// Releases the pane's web view and header so the pane can be dropped.
    func reset() {
        host(nil)
        setHeader(nil)
        tabID = nil
        outlined = false
    }

    @objc private func tapped() {
        if !isFocusedPane, let tabID { onFocus?(tabID) }
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Buttons in the header act on their own.
        !isFocusedPane && !(touch.view is UIControl)
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// The slim bar of a split pane that isn't focused: its favicon and title,
/// and buttons to take it out of the split or close it. Tapping it focuses
/// the pane.
final class PaneHeaderView: UIView, ThemeObserving, UIContextMenuInteractionDelegate {
    let removeButton = IconButton(.unlink, size: .xsmall, label: "Remove from Split View")
    let closeButton = IconButton(.close, size: .xsmall, label: "Close Tab")
    private let favicon = FaviconView(size: 14)
    private let title = UILabel()
    private let divider = DividerView()
    /// The pane's menu on long press (the split items).
    var menuProvider: (() -> UIMenu?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addInteraction(UIContextMenuInteraction(delegate: self))
        title.font = CurioFont.sm()
        title.adjustsFontForContentSizeCategory = true
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = UIStackView(arrangedSubviews: [favicon, title, removeButton, closeButton])
        stack.spacing = 8
        stack.alignment = .center
        stack.setCustomSpacing(4, after: removeButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Metrics.toolbarHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        title.textColor = theme.textMuted.uiColor
    }

    /// Saved tabs (pinned or in a folder) unload (−) instead of closing (×).
    func configure(_ model: TabViewModel) {
        favicon.configure(label: model.title, url: model.favicon, pageURL: model.url, loading: model.loading)
        title.text = model.title
        closeButton.setIcon(model.saved ? .minus : .close, label: model.saved ? "Unload Tab" : "Close Tab")
        accessibilityElements = [title, removeButton, closeButton]
        title.accessibilityLabel = model.title
        title.accessibilityHint = "Shows this pane’s page bar."
    }

    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let menuProvider else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menuProvider() }
    }
}

/// What a pane without a web view shows: the page's icon and title, such as
/// "New Tab", centered.
final class PanePlaceholderView: UIView, ThemeObserving {
    private let favicon = FaviconView(size: 28)
    private let title = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.font = CurioFont.sm(.medium)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.lineBreakMode = .byTruncatingTail
        let stack = UIStackView(arrangedSubviews: [favicon, title])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func themeDidChange(_ theme: CurioTheme) {
        title.textColor = theme.textMuted.uiColor
    }

    func configure(_ model: TabViewModel) {
        favicon.configure(label: model.title, url: model.favicon, pageURL: model.url, loading: model.loading)
        title.text = model.title
    }
}
