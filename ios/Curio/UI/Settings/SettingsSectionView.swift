import UIKit

/// The rows of one settings section. Rebuilds itself when settings change.
final class SettingsSectionView: UIView, UITextFieldDelegate {
    private enum TestState: Equatable {
        case idle, testing, ok
        case failed(String)
    }

    private let section: SettingsSection
    private let session: BrowserSession
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private var test: TestState = .idle
    private var testTask: Task<Void, Never>?
    private var keyField: CurioTextField?
    /// Presents sheets and alerts (About, confirmations).
    weak var host: UIViewController?
    var showsTitle = true { didSet { titleLabel.isHidden = !showsTitle } }

    private var settings: Settings { session.settings }
    private var store: SettingsStore { session.services.settings }

    init(section: SettingsSection, session: BrowserSession) {
        self.section = section
        self.session = session
        super.init(frame: .zero)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        titleLabel.text = section.label
        titleLabel.font = CurioFont.lg(.semibold)
        titleLabel.accessibilityTraits = .header
        store.observe(self) { [weak self] _ in self?.rebuild() }
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        testTask?.cancel()
    }

    private var narrow: Bool { bounds.width > 0 && bounds.width < 460 }

    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        titleLabel.textColor = ThemeCenter.shared.theme.text.uiColor
        stack.addArrangedSubview(titleLabel)
        stack.setCustomSpacing(6, after: titleLabel)
        let rows: [UIView] = switch section {
        case .general: generalRows()
        case .appearance: appearanceRows()
        case .ai: aiRows()
        case .privacy: privacyRows()
        case .shortcuts: shortcutRows()
        }
        rows.forEach { stack.addArrangedSubview($0) }
    }

    private var lastWidthWasNarrow: Bool?

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastWidthWasNarrow != narrow {
            lastWidthWasNarrow = narrow
            rebuild()
        }
    }

    // MARK: - Controls

    private func toggle(_ isOn: Bool, label: String, _ change: @escaping (inout Settings, Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = isOn
        control.onTintColor = ThemeCenter.shared.theme.accent.uiColor
        control.accessibilityLabel = label
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let value = control?.isOn else { return }
            self?.store.update { change(&$0, value) }
        }, for: .valueChanged)
        return control
    }

    private func segmented(_ titles: [String], selected: Int, _ onChange: @escaping (Int) -> Void) -> UISegmentedControl {
        let control = UISegmentedControl(items: titles)
        control.selectedSegmentIndex = selected
        control.selectedSegmentTintColor = ThemeCenter.shared.theme.surfaceRaised.uiColor
        control.addAction(UIAction { [weak control] _ in
            guard let index = control?.selectedSegmentIndex else { return }
            onChange(index)
        }, for: .valueChanged)
        return control
    }

    /// A text field that saves on Return or when editing ends.
    private func field(_ placeholder: String, text: String, width: CGFloat, commit: @escaping (String) -> Void) -> CurioTextField {
        let field = CurioTextField(placeholder: placeholder, text: text)
        field.delegate = self
        field.returnKeyType = .done
        if !narrow { field.widthAnchor.constraint(equalToConstant: width).isActive = true }
        field.addAction(UIAction { [weak field] _ in
            commit((field?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }, for: .editingDidEnd)
        return field
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    private func row(_ title: String, description: String? = nil, control: UIView?) -> SettingRowView {
        let stacked = narrow && (control is UITextField || control is UIStackView || control is UISegmentedControl)
        return SettingRowView(title, description: description, control: control, stacked: stacked)
    }

    // MARK: - General

    private func generalRows() -> [UIView] {
        let engine = settings.browsing.searchEngine
        let engineButton = CurioButton(engine.label, icon: .chevronDown)
        engineButton.configuration?.imagePlacement = .trailing
        engineButton.showsMenuAsPrimaryAction = true
        engineButton.menu = UIMenu(children: SearchEngine.builtIn.map { option in
            UIAction(title: option.label, state: option == engine ? .on : .off) { [weak self] _ in
                self?.store.update { $0.browsing.searchEngine = option }
            }
        })
        var custom = ""
        if case .custom(let template) = engine { custom = template }
        let customField = field("https://example.com/search?q=%s", text: custom, width: 300) { [weak self] value in
            guard !value.isEmpty else { return }
            self?.store.update { $0.browsing.searchEngine = .custom(value) }
        }
        customField.keyboardType = .URL
        let downloads = CurioButton("Show in Files", icon: .folder, action: UIAction { _ in
            let path = StoragePaths.downloadsDirectory.path(percentEncoded: false)
            if let url = URL(string: "shareddocuments://\(path)") { UIApplication.shared.open(url) }
        })
        let about = CurioButton("About Curio", icon: .info, action: UIAction { [weak self] _ in
            guard let host = self?.host else { return }
            host.present(SheetStyle.wrap(AboutViewController(), compact: host.traitCollection.horizontalSizeClass == .compact,
                                         size: CGSize(width: 380, height: 420), detents: [.medium()]), animated: true)
        })
        return [
            row("Search engine", description: "Used for searches typed into the address bar.", control: engineButton),
            row("Custom search URL", description: "Optional. Use %s where the query goes; press Return to use it.", control: customField),
            row("Restore previous session", description: "Reopen your spaces and tabs when Curio starts.",
                control: toggle(settings.browsing.restoreSession, label: "Restore previous session") { $0.browsing.restoreSession = $1 }),
            row("Downloads", description: "Saved to On My iPhone › Curio › Downloads in the Files app.", control: downloads),
            row("Tabs kept in memory", description: "Background tabs beyond this limit are put to sleep and reload when you return.",
                control: stepper(settings.browsing.maxLiveTabs)),
            row("About", control: about),
        ]
    }

    private func stepper(_ value: Int) -> UIView {
        let minus = CurioButton(nil, icon: .minus, size: .xsmall, action: UIAction { [weak self] _ in
            self?.store.update { $0.browsing.maxLiveTabs = max(2, $0.browsing.maxLiveTabs - 1) }
        })
        minus.accessibilityLabel = "Fewer tabs"
        let plus = CurioButton(nil, icon: .plus, size: .xsmall, action: UIAction { [weak self] _ in
            self?.store.update { $0.browsing.maxLiveTabs += 1 }
        })
        plus.accessibilityLabel = "More tabs"
        let label = UILabel()
        label.text = "\(value)"
        label.font = CurioFont.sm()
        label.textAlignment = .center
        label.textColor = ThemeCenter.shared.theme.text.uiColor
        label.widthAnchor.constraint(equalToConstant: 28).isActive = true
        label.accessibilityLabel = "\(value) tabs"
        let stack = UIStackView(arrangedSubviews: [minus, label, plus])
        stack.spacing = 6
        stack.alignment = .center
        return stack
    }

    // MARK: - Appearance

    private func appearanceRows() -> [UIView] {
        let theme = segmented(ThemeMode.allCases.map(\.label), selected: ThemeMode.allCases.firstIndex(of: settings.appearance.theme) ?? 0) { [weak self] index in
            self?.store.update { $0.appearance.theme = ThemeMode.allCases[index] }
        }
        let layout = segmented(TabLayout.allCases.map(\.label), selected: TabLayout.allCases.firstIndex(of: settings.appearance.tabLayout) ?? 0) { [weak self] index in
            self?.store.update { $0.appearance.tabLayout = TabLayout.allCases[index] }
        }
        return [
            row("Theme", description: "For web pages. The sidebar, menus and assistant follow each space's theme.", control: theme),
            row("Tab layout", description: "Vertical tabs live in the sidebar; horizontal tabs sit above the page. Your tabs stay as they are.", control: layout),
            row("Show sidebar", description: "Hide it to give the page more room; hover the left edge to peek.",
                control: toggle(settings.appearance.sidebarVisible, label: "Show sidebar") { $0.appearance.sidebarVisible = $1 }),
            row("Reduce motion", description: "Turn off space transitions and other animations.",
                control: toggle(settings.appearance.reduceMotion, label: "Reduce motion") { $0.appearance.reduceMotion = $1 }),
        ]
    }

    // MARK: - AI

    private func aiRows() -> [UIView] {
        let theme = ThemeCenter.shared.theme
        let ai = settings.ai
        let provider = ai.provider
        let keychain = session.services.keychain
        let hasKey = keychain.hasStoredKey(provider)
        let providerControl = segmented(AIProviderKind.allCases.map(\.label), selected: AIProviderKind.allCases.firstIndex(of: provider) ?? 0) { [weak self] index in
            self?.test = .idle
            self?.store.update { $0.ai.provider = AIProviderKind.allCases[index] }
        }
        let modelField = field(provider.defaultModel, text: ai.settings(for: provider).model, width: 220) { [weak self] value in
            self?.store.update { $0.ai.update(provider) { $0.model = value } }
        }
        let suggestions = CurioButton(nil, icon: .chevronDown, size: .small)
        suggestions.accessibilityLabel = "Suggested models"
        suggestions.showsMenuAsPrimaryAction = true
        suggestions.menu = UIMenu(children: provider.suggestedModels.map { model in
            UIAction(title: model, state: ai.model(for: provider) == model ? .on : .off) { [weak self] _ in
                self?.store.update { $0.ai.update(provider) { $0.model = model } }
            }
        })
        let modelControl = UIStackView(arrangedSubviews: [modelField, suggestions])
        modelControl.spacing = 6

        let keyField = CurioTextField(placeholder: hasKey ? "•••••••• (stored in Keychain)" : provider.requiresAPIKey ? "Paste your API key" : "Optional", secure: true)
        keyField.delegate = self
        keyField.textContentType = .password
        if !narrow { keyField.widthAnchor.constraint(equalToConstant: 220).isActive = true }
        self.keyField = keyField
        let save = CurioButton("Save", style: .primary, action: UIAction { [weak self] _ in
            guard let self, let key = self.keyField?.text, !key.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            saveKey(key)
        })
        let remove = CurioButton(nil, icon: .trash, style: .ghost, action: UIAction { [weak self] _ in self?.saveKey("") })
        remove.accessibilityLabel = "Remove key"
        remove.isHidden = !hasKey
        let keyControl = UIStackView(arrangedSubviews: [keyField, save, remove])
        keyControl.spacing = 6

        let status = UILabel()
        status.font = CurioFont.xs()
        status.numberOfLines = 0
        switch test {
        case .idle:
            status.text = hasKey || !provider.requiresAPIKey ? "Not tested" : "No key yet"
            status.textColor = theme.textFaint.uiColor
        case .testing:
            status.text = "Testing…"
            status.textColor = theme.textFaint.uiColor
        case .ok:
            status.text = "✓ Connected"
            status.textColor = theme.success.uiColor
        case .failed(let message):
            status.text = message
            status.textColor = theme.danger.uiColor
        }
        if !narrow { status.widthAnchor.constraint(lessThanOrEqualToConstant: 240).isActive = true }
        let testButton = CurioButton("Test", action: UIAction { [weak self] _ in self?.testConnection() })
        testButton.isEnabled = test != .testing
        let connection = UIStackView(arrangedSubviews: [status, testButton])
        connection.spacing = 8
        connection.alignment = .center

        let translate = field("English", text: ai.translateTo, width: 200) { [weak self] value in
            guard !value.isEmpty else { return }
            self?.store.update { $0.ai.translateTo = value }
        }
        var rows: [UIView] = [
            row("Provider", control: providerControl),
            row("Default Model", description: "Leave empty for the default, or pick a suggestion.", control: modelControl),
            row("API key", description: "Stored in your Keychain, never in Curio’s files. Press Return or Save.", control: keyControl),
            row("Connection", control: connection),
            row("Attach the current tab automatically",
                description: "New messages include the page you’re viewing. It’s always shown above the message box and can be removed.",
                control: toggle(ai.autoAttachCurrentTab, label: "Attach the current tab automatically") { $0.ai.autoAttachCurrentTab = $1 }),
            row("Translate selections into", control: translate),
        ]
        if provider == .openAICompatible {
            let baseURL = field(provider.defaultBaseURL, text: ai.settings(for: provider).baseURL, width: 300) { [weak self] value in
                self?.store.update { $0.ai.update(.openAICompatible) { $0.baseURL = value } }
            }
            baseURL.keyboardType = .URL
            rows.insert(row("API base URL", description: "For example Ollama (http://localhost:11434/v1) or LM Studio.", control: baseURL), at: 2)
        }
        return rows
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField === keyField, let key = textField.text, !key.trimmingCharacters(in: .whitespaces).isEmpty {
            saveKey(key)
        }
    }

    private func saveKey(_ key: String) {
        do {
            try session.services.keychain.setAPIKey(key, for: settings.ai.provider)
            test = .idle
        } catch {
            test = .failed(error.localizedDescription)
        }
        rebuild()
    }

    private func testConnection() {
        let config = ProviderConfig(settings: settings.ai, keychain: session.services.keychain)
        test = .testing
        rebuild()
        testTask = Task { [weak self] in
            let result: TestState
            do {
                try await AIClient.verify(config)
                result = .ok
            } catch let error as AIError {
                result = .failed(error.message)
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard let self, !Task.isCancelled else { return }
            test = result
            rebuild()
        }
    }

    // MARK: - Privacy

    private func privacyRows() -> [UIView] {
        let clearHistory = CurioButton("Clear History", style: .danger, action: UIAction { [weak self] _ in
            self?.confirm(title: "Clear all history?", action: "Clear History") { [weak self] in
                self?.session.services.history.clear()
            }
        })
        let deleteChats = CurioButton("Delete Chats", style: .danger, action: UIAction { [weak self] _ in
            self?.confirm(title: "Delete all chats?", action: "Delete Chats") { [weak self] in
                self?.session.services.conversations.deleteAll()
            }
        })
        return [
            row("Save browsing history", description: "History powers address bar suggestions. It never leaves this device.",
                control: toggle(settings.browsing.saveHistory, label: "Save browsing history") { $0.browsing.saveHistory = $1 }),
            row("Clear history", control: clearHistory),
            row("Clear chat history", description: "Deletes saved conversations with the assistant.", control: deleteChats),
            row("What Curio shares with AI providers",
                description: "Only the pages shown as chips above the message box, and only when you send a message. Passwords and form fields are never read.",
                control: nil),
            row("Site permissions",
                description: "Camera, microphone and location requests are asked by WebKit per site. Links that open other apps always ask first.",
                control: nil),
        ]
    }

    private func confirm(title: String, action: String, perform: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: "This can’t be undone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in perform() })
        host?.present(alert, animated: true)
    }

    // MARK: - Shortcuts

    private func shortcutRows() -> [UIView] {
        let theme = ThemeCenter.shared.theme
        let note = UILabel()
        note.text = "With a hardware keyboard, edit a shortcut and press Return. Use names like secondary-t (⌘T) or shift-secondary-]. Leave empty to remove it. Hold ⌘ to see every shortcut."
        note.font = CurioFont.xs()
        note.textColor = theme.textFaint.uiColor
        note.numberOfLines = 0
        let noteRow = UIStackView(arrangedSubviews: [note])
        noteRow.isLayoutMarginsRelativeArrangement = true
        noteRow.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        var rows: [UIView] = [noteRow]
        for command in CurioCommand.allCases where !command.defaultKeystrokes.isEmpty || settings.keybindings[command.rawValue] != nil {
            let current = command.keystroke(overrides: settings.keybindings) ?? ""
            let input = field("None", text: current, width: 180) { [weak self] value in
                self?.store.update { settings in
                    if value == command.defaultKeystrokes.first ?? "" {
                        settings.keybindings.removeValue(forKey: command.rawValue)
                    } else {
                        settings.keybindings[command.rawValue] = value
                    }
                }
            }
            input.font = CurioFont.mono(12)
            if KeyStroke(current) == nil && !current.isEmpty {
                input.layer.borderColor = theme.danger.uiColor.cgColor
            }
            let label = KeyStroke(current)?.label ?? ""
            let hint = KbdLabel(label.isEmpty ? "—" : label)
            let control = UIStackView(arrangedSubviews: [hint, input])
            control.spacing = 8
            control.alignment = .center
            rows.append(SettingRowView(command.title, control: control, stacked: narrow))
        }
        return rows
    }
}
