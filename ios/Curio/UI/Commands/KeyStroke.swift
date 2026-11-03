import UIKit

/// Parses desktop-style keystrokes ("shift-secondary-t", "ctrl-tab",
/// "secondary--") into key command input and modifiers.
nonisolated struct KeyStroke: Hashable, Sendable {
    var input: String
    var modifiers: UIKeyModifierFlags

    init?(_ text: String) {
        let lowered = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !lowered.isEmpty else { return nil }
        // A trailing "-" means the key itself is minus ("secondary--").
        var parts = lowered.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        if lowered.hasSuffix("--") {
            parts.removeLast(2)
            parts.append("-")
        } else if lowered == "-" {
            parts = ["-"]
        }
        guard let key = parts.popLast(), !key.isEmpty else { return nil }
        var modifiers: UIKeyModifierFlags = []
        for part in parts {
            switch part {
            case "secondary", "cmd", "command", "meta": modifiers.insert(.command)
            case "ctrl", "control": modifiers.insert(.control)
            case "alt", "option", "opt": modifiers.insert(.alternate)
            case "shift": modifiers.insert(.shift)
            case "": continue
            default: return nil
            }
        }
        let input: String = switch key {
        case "left": UIKeyCommand.inputLeftArrow
        case "right": UIKeyCommand.inputRightArrow
        case "up": UIKeyCommand.inputUpArrow
        case "down": UIKeyCommand.inputDownArrow
        case "escape", "esc": UIKeyCommand.inputEscape
        case "tab": "\t"
        case "enter", "return": "\r"
        case "space": " "
        default: key
        }
        self.input = input
        self.modifiers = modifiers
    }

    /// "⌃⇧⌘T" style label.
    var label: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.alternate) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        let key: String = switch input {
        case UIKeyCommand.inputLeftArrow: "←"
        case UIKeyCommand.inputRightArrow: "→"
        case UIKeyCommand.inputUpArrow: "↑"
        case UIKeyCommand.inputDownArrow: "↓"
        case UIKeyCommand.inputEscape: "esc"
        case "\t": "⇥"
        case "\r": "↩"
        default: input.uppercased()
        }
        return out + key
    }

    static func == (lhs: KeyStroke, rhs: KeyStroke) -> Bool {
        lhs.input == rhs.input && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(input)
        hasher.combine(modifiers.rawValue)
    }
}
