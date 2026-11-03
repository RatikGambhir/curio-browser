import UIKit

/// The Curio assistant. It never reads pages on its own: when a message is
/// sent, it extracts exactly the tabs shown as chips above the message box,
/// so the user always sees what is shared.
final class AssistantViewController: UIViewController, ThemeObserving {
    private let session: BrowserSession
    weak var delegate: AssistantDelegate?

    // Conversation state.
    private var conversation = Conversation()
    private var status: AssistantStatus = .idle
    private var stream: AIStream?
    private var extraction: Task<Void, Never>?
    private var history: [ConversationSummary] = []

    // Context offered as chips.
    private var attached: [ContextTab] = []
    private var attachCurrent: Bool
    private var attachSpace = false
    private var currentTab: ContextTab?
    private var space: (id: UUID, name: String)?
    private var spaceTabs: [ContextTab] = []

    // Views.
    private let header = UIView()
    private let titleLabel = UILabel()
    private let historyButton = IconButton(.history, label: "Chat History")
    private let newChatButton = IconButton(.compose, label: "New Chat")
    private let closeButton = IconButton(.sidebarRight, label: "Close Assistant")
    private let headerDivider = DividerView()
    private let scroll = UIScrollView()
    private let messagesStack = UIStackView()
    private let emptyState = UIStackView()
    private let setupBox = UIView()
    private let suggestions = UIStackView()
    private let composerCard = UIView()
    private let composerWrap = UIView()
    private let contextChips = FlowLayoutView()
    private let composer = ComposerTextView(placeholder: "Ask about this page, your tabs, or anything…")
    private let modelLabel = UILabel()
    private let sendButton = CurioButton(nil, icon: .arrowUp, style: .primary, size: .small)
    private let stopButton = CurioButton(nil, icon: .stop, style: .standard, size: .small)
    private var messageViews: [UIView] = []
    private var renderTask: Task<Void, Never>?

    /// Shown as a sheet on narrow screens (the close button becomes "Done").
    var presentedAsSheet = false {
        didSet { closeButton.setIcon(presentedAsSheet ? .close : .sidebarRight, label: "Close Assistant") }
    }

    init(session: BrowserSession) {
        self.session = session
        attachCurrent = session.settings.ai.autoAttachCurrentTab
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        extraction?.cancel()
        renderTask?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHeader()
        buildBody()
        buildComposer()
        let column = UIStackView(arrangedSubviews: [header, headerDivider, scroll, composerWrap])
        column.axis = .vertical
        column.setCustomSpacing(4, after: scroll)
        column.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.topAnchor.constraint(equalTo: view.topAnchor),
            column.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10),
        ])
        reloadHistory()
        refreshContext()
        ThemeCenter.shared.observe(self)
        render()
    }

    func themeDidChange(_ theme: CurioTheme) {
        guard isViewLoaded else { return }
        view.backgroundColor = theme.surface.uiColor
        titleLabel.textColor = theme.text.uiColor
        composerCard.backgroundColor = theme.surfaceRaised.uiColor
        composerCard.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        Shadow.sm.apply(to: composerCard.layer, dark: theme.appearance == .dark)
        composer.setColors(text: theme.text.uiColor, placeholder: theme.textFaint.uiColor, tint: theme.accent.uiColor)
        modelLabel.textColor = theme.textFaint.uiColor
        setupBox.backgroundColor = theme.accentSoft.uiColor
        render()
    }

    // MARK: - Building

    private func buildHeader() {
        let logo = LogoView(size: 20)
        titleLabel.font = CurioFont.sm(.semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.accessibilityTraits = .header
        historyButton.showsMenuAsPrimaryAction = true
        historyButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.historyMenuItems() ?? [])
        }])
        newChatButton.addAction(UIAction { [weak self] _ in self?.newConversation() }, for: .primaryActionTriggered)
        closeButton.addAction(UIAction { [weak self] _ in self?.delegate?.assistantDidClose() }, for: .primaryActionTriggered)
        let stack = UIStackView(arrangedSubviews: [logo, titleLabel, historyButton, newChatButton, closeButton])
        stack.spacing = 8
        stack.alignment = .center
        stack.setCustomSpacing(4, after: historyButton)
        stack.setCustomSpacing(4, after: newChatButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 46),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
    }

    private func historyMenuItems() -> [UIMenuElement] {
        reloadHistory()
        guard !history.isEmpty else {
            return [UIAction(title: "No previous chats", attributes: .disabled) { _ in }]
        }
        let chats = history.map { summary in
            UIAction(title: summary.title, image: Icon.message.image()) { [weak self] _ in self?.openConversation(summary.id) }
        }
        let clear = UIAction(title: "Delete All Chats", image: Icon.trash.image(), attributes: .destructive) { [weak self] _ in
            self?.deleteAllConversations()
        }
        return [UIMenu(options: .displayInline, children: chats), clear]
    }

    private func buildBody() {
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        messagesStack.axis = .vertical
        messagesStack.spacing = 16
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(messagesStack)
        emptyState.axis = .vertical
        emptyState.alignment = .center
        emptyState.spacing = 14
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(emptyState)
        NSLayoutConstraint.activate([
            messagesStack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 14),
            messagesStack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -14),
            messagesStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 14),
            messagesStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -14),
            emptyState.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            emptyState.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
            emptyState.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
        ])
    }

    private func buildComposer() {
        composerCard.layer.cornerRadius = 14
        composerCard.layer.cornerCurve = .continuous
        composerCard.layer.borderWidth = 1
        composer.onSubmit = { [weak self] in self?.submit() }
        composer.onChange = { [weak self] in self?.updateSendButton() }
        modelLabel.font = CurioFont.xs()
        modelLabel.lineBreakMode = .byTruncatingTail
        sendButton.accessibilityLabel = "Send"
        sendButton.toolTip = "Send (⏎)"
        stopButton.accessibilityLabel = "Stop"
        sendButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .primaryActionTriggered)
        stopButton.addAction(UIAction { [weak self] _ in self?.stop() }, for: .primaryActionTriggered)
        modelLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        modelLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for button in [sendButton, stopButton] {
            button.setContentHuggingPriority(.required, for: .horizontal)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let footer = UIStackView(arrangedSubviews: [modelLabel, stopButton, sendButton])
        footer.spacing = 6
        footer.alignment = .center
        contextChips.centered = false
        contextChips.spacing = 5
        contextChips.lineSpacing = 5
        let stack = UIStackView(arrangedSubviews: [contextChips, composer, footer])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        composerCard.addSubview(stack)
        composerWrap.addSubview(composerCard)
        composerCard.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            composerCard.leadingAnchor.constraint(equalTo: composerWrap.leadingAnchor, constant: 10),
            composerCard.trailingAnchor.constraint(equalTo: composerWrap.trailingAnchor, constant: -10),
            composerCard.topAnchor.constraint(equalTo: composerWrap.topAnchor),
            composerCard.bottomAnchor.constraint(equalTo: composerWrap.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: composerCard.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: composerCard.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: composerCard.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: composerCard.bottomAnchor, constant: -8),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        composerCard.layer.shadowPath = UIBezierPath(roundedRect: composerCard.bounds, cornerRadius: 14).cgPath
    }

    // MARK: - Rendering

    private var isBusy: Bool { status != .idle }

    private func render() {
        guard isViewLoaded else { return }
        let theme = ThemeCenter.shared.theme
        titleLabel.text = conversation.messages.isEmpty ? "Curio Assistant" : conversation.title
        let empty = conversation.messages.isEmpty
        emptyState.isHidden = !empty
        messagesStack.isHidden = empty
        if empty { renderEmptyState(theme) } else { renderMessages(theme) }
        renderContextChips(theme)
        let ai = session.settings.ai
        modelLabel.text = "\(ai.provider.label) · \(ai.model(for: ai.provider))"
        updateSendButton()
    }

    private func updateSendButton() {
        sendButton.isHidden = isBusy
        stopButton.isHidden = !isBusy
        sendButton.isEnabled = !composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func renderEmptyState(_ theme: CurioTheme) {
        emptyState.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let title = UILabel()
        title.text = "What are you curious about?"
        title.font = CurioFont.lg(.semibold)
        title.textColor = theme.text.uiColor
        title.textAlignment = .center
        title.numberOfLines = 0
        let body = UILabel()
        body.text = "Ask about this page, compare your open tabs, or explore anything. Pages are shared only when shown below the message box."
        body.font = CurioFont.sm()
        body.textColor = theme.textMuted.uiColor
        body.textAlignment = .center
        body.numberOfLines = 0
        for view in [LogoView(size: 52), title, body] as [UIView] { emptyState.addArrangedSubview(view) }
        if !providerConfig.isReady {
            setupBox.subviews.forEach { $0.removeFromSuperview() }
            let label = UILabel()
            label.text = "Connect an AI provider to start chatting."
            label.font = CurioFont.sm()
            label.textColor = theme.text.uiColor
            label.numberOfLines = 0
            label.textAlignment = .center
            let button = CurioButton("Set Up AI…", style: .primary, action: UIAction { [weak self] _ in self?.delegate?.assistantOpenSettings() })
            let stack = UIStackView(arrangedSubviews: [label, button])
            stack.axis = .vertical
            stack.alignment = .center
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            setupBox.addSubview(stack)
            setupBox.layer.cornerRadius = 10
            setupBox.layer.cornerCurve = .continuous
            setupBox.backgroundColor = theme.accentSoft.uiColor
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: setupBox.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: setupBox.trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: setupBox.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: setupBox.bottomAnchor, constant: -12),
            ])
            emptyState.addArrangedSubview(setupBox)
        }
        suggestions.arrangedSubviews.forEach { $0.removeFromSuperview() }
        suggestions.axis = .vertical
        suggestions.spacing = 8
        func suggestion(_ title: String, _ icon: Icon, _ action: QuickAction) {
            let chip = ChipButton(title, icon: icon, large: true, outlined: true, action: UIAction { [weak self] _ in self?.quickAction(action) })
            suggestions.addArrangedSubview(chip)
        }
        if currentTab != nil {
            suggestion("Summarize this page", .fileText, .summarizePage)
            suggestion("What are the key points?", .list, .keyPoints)
        }
        if spaceTabs.count >= 2 { suggestion("Compare my open tabs", .columns, .compareTabs) }
        if !suggestions.arrangedSubviews.isEmpty {
            emptyState.addArrangedSubview(suggestions)
            suggestions.widthAnchor.constraint(lessThanOrEqualToConstant: 320).isActive = true
            suggestions.widthAnchor.constraint(equalTo: emptyState.widthAnchor).withPriority(.defaultHigh).isActive = true
        }
    }

    private func renderMessages(_ theme: CurioTheme) {
        let messages = conversation.messages
        // Rebuild if messages were removed (retry) or replaced (opened chat).
        if messageViews.count > messages.count { resetMessageViews() }
        for (index, message) in messages.enumerated() {
            let isLast = index == messages.count - 1
            let streaming = isLast && isBusy && message.role == .assistant
            if index < messageViews.count {
                if let view = messageViews[index] as? AssistantMessageView {
                    view.update(message, streaming: streaming, status: status, isLast: isLast, theme: theme)
                }
                continue
            }
            let view: UIView
            switch message.role {
            case .user:
                view = UserBubbleView(message: message, theme: theme)
            case .assistant:
                let answer = AssistantMessageView()
                answer.onRetry = { [weak self] in self?.retry() }
                answer.markdown.onLink = { [weak self] url in self?.delegate?.assistantOpenURL(url) }
                answer.update(message, streaming: streaming, status: status, isLast: isLast, theme: theme)
                view = answer
            }
            messageViews.append(view)
            messagesStack.addArrangedSubview(view)
        }
    }

    private func resetMessageViews() {
        messageViews.forEach { $0.removeFromSuperview() }
        messageViews.removeAll()
    }

    private func scrollToBottom() {
        view.layoutIfNeeded()
        let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
    }

    // MARK: - Context chips

    /// Updates the tabs offered as context (after tab or space changes).
    func refreshContext() {
        let context = session.assistantContext
        if space?.id != context.space.id {
            // A different space: explicit attachments no longer apply.
            attached.removeAll()
            attachSpace = false
        }
        let open = Set(context.spaceTabs.map(\.id))
        attached.removeAll { !open.contains($0.id) && $0.id != context.current?.id }
        attached = attached.map { tab in context.spaceTabs.first { $0.id == tab.id } ?? tab }
        currentTab = context.current.flatMap { $0.url.hasPrefix("http") ? $0 : nil }
        space = context.space
        spaceTabs = context.spaceTabs.filter { $0.url.hasPrefix("http") }
        if isViewLoaded {
            renderContextChips(ThemeCenter.shared.theme)
            if conversation.messages.isEmpty { renderEmptyState(ThemeCenter.shared.theme) }
        }
    }

    private var contextTabs: [ContextTab] {
        if attachSpace { return spaceTabs }
        var tabs: [ContextTab] = []
        if attachCurrent, let currentTab { tabs.append(currentTab) }
        for tab in attached where !tabs.contains(where: { $0.id == tab.id }) { tabs.append(tab) }
        return tabs
    }

    private func renderContextChips(_ theme: CurioTheme) {
        var chips: [UIView] = []
        if attachSpace {
            let icon = UIImageView(image: Icon.layout.image(10))
            chips.append(ContextChipView(title: "All \(spaceTabs.count) tabs in \(space?.name ?? "this space")", leading: icon, active: true, removable: true) { [weak self] in
                self?.attachSpace = false
                self?.render()
            })
        } else {
            for tab in contextTabs {
                let favicon = FaviconView(size: 12)
                favicon.configure(label: tab.title, url: tab.favicon)
                let isCurrent = tab.id == currentTab?.id
                chips.append(ContextChipView(title: tab.title.isEmpty ? Curio.displayHost(tab.url) : tab.title, leading: favicon,
                                             active: true, removable: true, tooltip: tab.url) { [weak self] in
                    if isCurrent { self?.attachCurrent = false }
                    self?.attached.removeAll { $0.id == tab.id }
                    self?.render()
                })
            }
            if !attachCurrent, let currentTab {
                let chip = ContextChipView(title: "Add \(Curio.displayHost(currentTab.url))", leading: UIImageView(image: Icon.plus.image(10)),
                                           active: false, removable: false)
                chip.addAction(UIAction { [weak self] _ in
                    self?.attachCurrent = true
                    self?.render()
                }, for: .primaryActionTriggered)
                chips.append(chip)
            }
        }
        chips.append(makeTabPicker(theme))
        contextChips.setItems(chips)
    }

    private func makeTabPicker(_ theme: CurioTheme) -> UIView {
        let button = CurioButton("Tabs", icon: .paperclip, style: .ghost, size: .xsmall)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            completion(self?.tabPickerItems() ?? [])
        }])
        button.accessibilityLabel = "Choose tabs to share"
        let size = button.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        button.frame.size = size
        return PickerHost(button: button)
    }

    private func tabPickerItems() -> [UIMenuElement] {
        let selected = Set(contextTabs.map(\.id))
        let all = UIAction(title: "All tabs in this space", image: Icon.layout.image()) { [weak self] _ in
            self?.attachSpace = true
            self?.render()
        }
        let none = UIAction(title: "No page context", image: Icon.xCircle.image()) { [weak self] _ in
            self?.attachSpace = false
            self?.attachCurrent = false
            self?.attached.removeAll()
            self?.render()
        }
        let tabs = spaceTabs.map { tab in
            UIAction(title: tab.title.isEmpty ? Curio.displayHost(tab.url) : String(tab.title.prefix(48)),
                     state: selected.contains(tab.id) ? .on : .off) { [weak self] _ in
                guard let self else { return }
                attachSpace = false
                let isCurrent = tab.id == currentTab?.id
                if selected.contains(tab.id) {
                    if isCurrent { attachCurrent = false }
                    attached.removeAll { $0.id == tab.id }
                } else if isCurrent {
                    attachCurrent = true
                } else {
                    attached.append(tab)
                }
                render()
            }
        }
        return [UIMenu(options: .displayInline, children: [all, none]), UIMenu(options: .displayInline, children: tabs)]
    }

    // MARK: - Public actions

    func focusComposer() {
        loadViewIfNeeded()
        composer.becomeFirstResponder()
    }

    /// Starts a new, empty conversation.
    func newConversation() {
        stop()
        conversation = Conversation()
        attached.removeAll()
        attachSpace = false
        attachCurrent = session.settings.ai.autoAttachCurrentTab
        resetMessageViews()
        render()
    }

    /// Attaches a tab ("Ask Curio About This Tab").
    func attachTab(_ tab: ContextTab) {
        attachSpace = false
        if tab.id == currentTab?.id {
            attachCurrent = true
        } else if !attached.contains(where: { $0.id == tab.id }) {
            attached.append(tab)
        }
        render()
    }

    /// Sends `text` as a user message.
    func ask(_ text: String) {
        loadViewIfNeeded()
        composer.setText(text)
        submit()
    }

    func quickAction(_ action: QuickAction) {
        if action == .compareTabs && contextTabs.count < 2 {
            attachSpace = true
        } else if action != .compareTabs {
            attachCurrent = true
        }
        ask(action.prompt)
    }

    /// Asks about selected text, quoting it.
    func askAboutSelection(_ action: QuickAction, selection: String) {
        attachCurrent = true
        ask("\(action.prompt)\n\n\(Self.quote(selection))")
    }

    /// Puts a quote of `text` in the message box for the user's own question.
    func prefillQuote(_ text: String) {
        loadViewIfNeeded()
        attachCurrent = true
        composer.setText("\(Self.quote(text))\n\n")
        composer.becomeFirstResponder()
        render()
    }

    private static func quote(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))
            .components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
    }

    // MARK: - Sending

    private var providerConfig: ProviderConfig {
        ProviderConfig(settings: session.settings.ai, keychain: session.services.keychain)
    }

    private func submit() {
        let text = composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        composer.setText("")
        let tabs = contextTabs
        var user = ChatMessage(role: .user, content: text)
        user.context = tabs.map { ContextRef(title: $0.title, url: $0.url, faviconURL: $0.favicon) }
        conversation.scope = if attachSpace {
            space.map { .space($0.id) } ?? .none
        } else if tabs.isEmpty {
            .none
        } else if tabs.count == 1 {
            .tab(tabs[0].id)
        } else {
            .tabs(tabs.map(\.id))
        }
        conversation.messages.append(user)
        if conversation.messages.count == 1 { conversation.retitleFromFirstMessage() }
        status = .reading
        render()
        scrollToBottom()
        let ids = tabs.map(\.id)
        extraction = Task { [weak self] in
            guard let self else { return }
            let pages = ids.isEmpty ? [] : await session.extractPages(ids)
            guard !Task.isCancelled, status == .reading else { return }
            startStream(pages: pages)
        }
    }

    private func startStream(pages: [PageContext]) {
        let ai = session.settings.ai
        let system = SystemPrompt.build(pages: pages, maxChars: ai.maxContextChars)
        let messages = conversation.messages
            .filter { $0.error == nil || !$0.content.isEmpty }
            .map { WireMessage(role: $0.role, content: $0.content) }
        conversation.messages.append(ChatMessage(role: .assistant, content: ""))
        status = .thinking
        render()
        stream = AIStream(config: providerConfig, request: ChatRequest(system: system, messages: messages)) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: StreamEvent) {
        guard !conversation.messages.isEmpty else { return }
        let last = conversation.messages.count - 1
        switch event {
        case .thinking:
            if status != .writing { status = .thinking }
        case .text(let chunk):
            status = .writing
            conversation.messages[last].content += chunk
        case .done(let reason):
            switch reason {
            case .maxTokens: conversation.messages[last].error = "The answer was cut off at the length limit."
            case .refusal: conversation.messages[last].error = "The model declined to answer this request."
            default: break
            }
            finish()
        case .error(let error):
            conversation.messages[last].error = error.message
            finish()
        }
        scheduleRender()
    }

    /// Coalesces streaming updates to about 30 per second.
    private func scheduleRender() {
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(33))
            guard let self else { return }
            renderTask = nil
            let nearBottom = scroll.contentOffset.y + scroll.bounds.height >= scroll.contentSize.height - 80
            render()
            if nearBottom || !isBusy { scrollToBottom() }
        }
    }

    private func finish() {
        status = .idle
        stream = nil
        conversation.updatedAt = .now
        session.services.conversations.save(conversation)
        reloadHistory()
    }

    /// Stops the current answer, keeping what was written.
    func stop() {
        extraction?.cancel()
        stream?.cancel()
        stream = nil
        if isBusy {
            if let last = conversation.messages.last, last.role == .assistant, last.content.isEmpty {
                conversation.messages[conversation.messages.count - 1].error = "Stopped."
            }
            finish()
        }
        render()
    }

    /// Drops the failed answer and sends the last question again.
    private func retry() {
        guard !isBusy else { return }
        while conversation.messages.last?.role == .assistant { conversation.messages.removeLast() }
        guard let question = conversation.messages.popLast() else { return }
        resetMessageViews()
        composer.setText(question.content)
        submit()
    }

    // MARK: - History

    private func reloadHistory() {
        history = session.services.conversations.list(limit: 30)
    }

    private func openConversation(_ id: UUID) {
        stop()
        guard let saved = session.services.conversations.load(id) else { return }
        conversation = saved
        resetMessageViews()
        render()
        scrollToBottom()
    }

    private func deleteAllConversations() {
        session.services.conversations.deleteAll()
        newConversation()
        reloadHistory()
    }
}
