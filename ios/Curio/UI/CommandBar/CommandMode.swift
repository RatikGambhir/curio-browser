import Foundation

/// What the command bar was opened for.
enum CommandMode {
    /// A new tab (⌘T): navigation creates a tab.
    case newTab
    /// Editing the current address (⌘L): navigation replaces the page.
    case editURL
    /// The command palette (⌘K): commands first.
    case palette
}
