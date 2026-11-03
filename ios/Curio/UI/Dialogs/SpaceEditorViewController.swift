import UIKit

/// Creates a space or edits its name, icon and color, with a live preview of
/// the space's chrome.
final class SpaceEditorViewController: UIViewController, ThemeObserving, UITextFieldDelegate {
    private let spaceID: UUID?
    private var icon: String
    private var color: AccentColor
    private let preview = GradientView()
    private let previewIcon = UILabel()
    private let previewName = UILabel()
    private let nameField: CurioTextField
    private let iconGrid = FlowLayoutView()
    private let colorRow = FlowLayoutView()
    var onSave: ((String, String, AccentColor) -> Void)?

    init(spaceID: UUID?, name: String, icon: String, color: AccentColor) {
        self.spaceID = spaceID
        self.icon = icon
        self.color = color
        nameField = CurioTextField(placeholder: "Space name", text: name)
        super.init(nibName: nil, bundle: nil)
        title = spaceID == nil ? "New Space" : "Edit Space"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: spaceID == nil ? "Create Space" : "Save", primaryAction: UIAction { [weak self] _ in
            self?.save()
        })
        preview.layer.cornerRadius = 12
        preview.layer.cornerCurve = .continuous
        preview.clipsToBounds = true
        previewIcon.font = .systemFont(ofSize: 22)
        previewName.font = CurioFont.base(.semibold)
        let previewStack = UIStackView(arrangedSubviews: [previewIcon, previewName])
        previewStack.spacing = 12
        previewStack.alignment = .center
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(previewStack)
        nameField.delegate = self
        nameField.returnKeyType = .done
        nameField.autocapitalizationType = .words
        nameField.addAction(UIAction { [weak self] _ in self?.updatePreview() }, for: .editingChanged)
        iconGrid.centered = false
        iconGrid.spacing = 4
        iconGrid.lineSpacing = 4
        colorRow.centered = false
        colorRow.spacing = 8
        colorRow.lineSpacing = 8
        let stack = UIStackView(arrangedSubviews: [preview, nameField, SectionLabel("Icon"), iconGrid, SectionLabel("Color"), colorRow])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            previewStack.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 12),
            previewStack.trailingAnchor.constraint(lessThanOrEqualTo: preview.trailingAnchor, constant: -12),
            previewStack.topAnchor.constraint(equalTo: preview.topAnchor, constant: 12),
            previewStack.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -12),
        ])
        ThemeCenter.shared.observe(self)
        rebuildPickers()
        updatePreview()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        nameField.becomeFirstResponder()
    }

    func themeDidChange(_ theme: CurioTheme) {
        view.backgroundColor = theme.surface.uiColor
        if isViewLoaded {
            rebuildPickers()
            updatePreview()
        }
    }

    private var currentName: String {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "New Space" : name
    }

    private func updatePreview() {
        let theme = CurioTheme(accent: color, appearance: ThemeCenter.shared.theme.appearance)
        preview.setColors(theme.chromeTop.uiColor, theme.chromeBottom.uiColor)
        previewIcon.text = icon
        previewName.text = currentName
        previewName.textColor = theme.text.uiColor
    }

    private func rebuildPickers() {
        let theme = ThemeCenter.shared.theme
        iconGrid.setItems(Space.icons.map { symbol in
            let button = PickerButton(size: 36)
            button.setTitle(symbol, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17)
            button.layer.cornerRadius = 8
            let selected = symbol == icon
            button.backgroundColor = selected ? theme.accentSoft.uiColor : .clear
            button.layer.borderWidth = selected ? 1 : 0
            button.layer.borderColor = theme.accent.uiColor.cgColor
            button.accessibilityLabel = "Icon \(symbol)"
            button.accessibilityTraits = selected ? [.button, .selected] : .button
            button.addAction(UIAction { [weak self] _ in
                self?.icon = symbol
                self?.rebuildPickers()
                self?.updatePreview()
            }, for: .primaryActionTriggered)
            return button
        })
        colorRow.setItems(AccentColor.allCases.map { accent in
            let button = PickerButton(size: 30)
            button.backgroundColor = CurioTheme.swatch(accent)
            button.layer.cornerRadius = 15
            button.layer.borderWidth = 2
            button.layer.borderColor = accent == color ? theme.text.uiColor.cgColor : UIColor.clear.cgColor
            button.accessibilityLabel = accent.label
            button.accessibilityTraits = accent == color ? [.button, .selected] : .button
            button.addAction(UIAction { [weak self] _ in
                self?.color = accent
                self?.rebuildPickers()
                self?.updatePreview()
            }, for: .primaryActionTriggered)
            return button
        })
    }

    private func save() {
        onSave?(currentName, icon, color)
        dismiss(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        save()
        return false
    }
}
