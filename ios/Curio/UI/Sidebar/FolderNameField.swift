import UIKit

/// The text field a folder row turns into while its name is edited. Return
/// and tapping away save; Escape on a hardware keyboard cancels.
final class FolderNameField: UITextField, UITextFieldDelegate {
    /// Called once per edit with the typed name (blank names are ignored by
    /// the model, so the old name stays).
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    /// Set when the edit has already been saved or cancelled, so ending
    /// editing afterwards does not save again.
    private var finished = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        borderStyle = .none
        returnKeyType = .done
        autocapitalizationType = .words
        autocorrectionType = .no
        spellCheckingType = .no
        adjustsFontForContentSizeCategory = true
        accessibilityLabel = "Folder name"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `name` and arms the field for a new edit.
    func prepare(name: String) {
        text = name
        finished = false
    }

    /// Takes focus and selects the whole name. Returns `false` when the field
    /// can't take focus yet (not in a window, or a menu is still dismissing).
    @discardableResult
    func focusAndSelectAll() -> Bool {
        guard !finished, window != nil else { return false }
        if !isFirstResponder && !becomeFirstResponder() { return false }
        selectedTextRange = textRange(from: beginningOfDocument, to: endOfDocument)
        return true
    }

    /// Stops editing without saving or cancelling (the row is being reused or
    /// left edit mode from the model side).
    func reset() {
        finished = true
        if isFirstResponder { resignFirstResponder() }
    }

    private func commit() {
        guard !finished else { return }
        finished = true
        onCommit?(text ?? "")
    }

    @objc private func cancelEditing() {
        guard !finished else { return }
        finished = true
        resignFirstResponder()
        onCancel?()
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        commit()
        resignFirstResponder()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        commit()
    }

    // MARK: - Keyboard

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelEditing))
        escape.wantsPriorityOverSystemBehavior = true
        return [escape] + (super.keyCommands ?? [])
    }
}
