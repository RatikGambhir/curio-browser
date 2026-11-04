import UIKit

/// Creates a space or edits its name, icon and theme, with a live preview of
/// the space's chrome.
final class SpaceEditorViewController: UIViewController, ThemeObserving, UITextFieldDelegate {
    private let spaceID: UUID?
    private var icon: String
    private var gradient: SpaceGradient
    private let preview = GradientView()
    private let previewIcon = UILabel()
    private let previewName = UILabel()
    private let previewTheme = UILabel()
    private let nameField: CurioTextField
    private let iconGrid = FlowLayoutView()
    private let themeGrid = UIStackView()
    private var themeTiles: [ThemeTileButton] = []
    var onSave: ((String, String, SpaceGradient) -> Void)?

    init(spaceID: UUID?, name: String, icon: String, gradient: SpaceGradient) {
        self.spaceID = spaceID
        self.icon = icon
        self.gradient = gradient
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
        previewName.adjustsFontForContentSizeCategory = true
        previewName.setContentHuggingPriority(.defaultLow, for: .horizontal)
        previewName.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previewTheme.font = CurioFont.xs()
        previewTheme.adjustsFontForContentSizeCategory = true
        previewTheme.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The name takes the spare room, so the icon hugs it on the left and
        // the theme name sits at the right edge.
        previewIcon.setContentHuggingPriority(.required, for: .horizontal)
        previewTheme.setContentHuggingPriority(.required, for: .horizontal)
        let previewStack = UIStackView(arrangedSubviews: [previewIcon, previewName, previewTheme])
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
        buildThemeGrid()
        let stack = UIStackView(arrangedSubviews: [preview, nameField, SectionLabel("Icon"), iconGrid, SectionLabel("Theme"), themeGrid])
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
            preview.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            previewStack.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 12),
            previewStack.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -12),
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
        let theme = CurioTheme(gradient: gradient)
        preview.setGradient(gradient)
        previewIcon.text = icon
        previewName.text = currentName
        previewName.textColor = theme.text.uiColor
        previewTheme.text = gradient.label
        previewTheme.textColor = theme.textMuted.uiColor
    }

    /// Two rows of five light themes above two rows of five dark ones, so
    /// every tile stays at least 44pt tall and wide enough to tap on a phone.
    private func buildThemeGrid() {
        themeGrid.axis = .vertical
        themeGrid.spacing = 6
        for (index, tone) in [SpaceGradient.light, SpaceGradient.dark].enumerated() {
            for start in stride(from: 0, to: tone.count, by: 5) {
                let tiles = tone[start ..< min(start + 5, tone.count)].map { gradient in
                    let tile = ThemeTileButton(gradient: gradient)
                    tile.addAction(UIAction { [weak self] _ in
                        self?.gradient = gradient
                        self?.rebuildPickers()
                        self?.updatePreview()
                    }, for: .primaryActionTriggered)
                    return tile
                }
                themeTiles += tiles
                let row = UIStackView(arrangedSubviews: tiles)
                row.distribution = .fillEqually
                row.spacing = 6
                themeGrid.addArrangedSubview(row)
            }
            if index == 0, let last = themeGrid.arrangedSubviews.last {
                themeGrid.setCustomSpacing(14, after: last)
            }
        }
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
        for tile in themeTiles {
            tile.style(selected: tile.gradient == gradient, theme: theme)
        }
    }

    private func save() {
        onSave?(currentName, icon, gradient)
        dismiss(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        save()
        return false
    }
}

/// One theme in the space editor: its gradient, with a 2pt accent ring when
/// selected. The ring sits outside the swatch, so the selected one doesn't
/// shrink.
private final class ThemeTileButton: TapControl {
    let gradient: SpaceGradient
    private let swatch = GradientView()

    init(gradient: SpaceGradient) {
        self.gradient = gradient
        super.init(frame: .zero)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        layer.borderWidth = 2
        swatch.style = .swatch
        swatch.setGradient(gradient)
        swatch.layer.cornerRadius = 7
        swatch.layer.cornerCurve = .continuous
        swatch.layer.borderWidth = 1
        swatch.clipsToBounds = true
        swatch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swatch)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            swatch.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            swatch.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            swatch.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
        isAccessibilityElement = true
        accessibilityLabel = gradient.label
        toolTip = gradient.label
        addInteraction(UIPointerInteraction(delegate: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func style(selected: Bool, theme: CurioTheme) {
        layer.borderColor = selected ? theme.accent.uiColor.cgColor : UIColor.clear.cgColor
        swatch.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
        accessibilityTraits = selected ? [.button, .selected] : .button
        isSelected = selected
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }
}
