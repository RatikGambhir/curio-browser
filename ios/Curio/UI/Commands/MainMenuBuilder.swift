import UIKit

/// Builds the menu bar (iPad) and the keyboard shortcuts (every device with a
/// hardware keyboard) from `CurioCommand`, honoring keybinding overrides.
struct MainMenuBuilder {
    let keybindings: [String: String]

    /// Shortcuts the system or text editing already owns.
    private static let reserved: Set<KeyStroke> = Set(
        ["secondary-c", "secondary-v", "secondary-x", "secondary-z", "shift-secondary-z", "secondary-a",
         "secondary-q", "secondary-h", "secondary-m", "secondary-tab", "secondary-space"].compactMap(KeyStroke.init)
    )

    func build(_ builder: UIMenuBuilder) {
        guard builder.system == .main else { return }
        // Standard menus whose shortcuts Curio uses for its own commands.
        for menu: UIMenu.Identifier in [.format, .find, .close, .print, .newScene, .toolbar, .document, .preferences] {
            builder.remove(menu: menu)
        }
        var used = Self.reserved

        func element(_ command: CurioCommand, hidden: Bool = false) -> UIMenuElement {
            let strokes = command.keystrokes(overrides: keybindings).compactMap(KeyStroke.init).filter { !used.contains($0) }
            guard let stroke = strokes.first else {
                return UICommand(title: command.title, image: command.icon.image(), action: #selector(BrowserViewController.performCurioCommand(_:)),
                                 propertyList: command.rawValue, attributes: hidden ? .hidden : [])
            }
            used.insert(stroke)
            let key = UIKeyCommand(title: command.title, image: command.icon.image(), action: #selector(BrowserViewController.performCurioCommand(_:)),
                                   input: stroke.input, modifierFlags: stroke.modifiers, propertyList: command.rawValue,
                                   attributes: hidden ? .hidden : [])
            key.wantsPriorityOverSystemBehavior = true
            return key
        }

        /// Extra default bindings (⌘+ for Zoom In, ⌃Tab for Next Tab) as
        /// hidden alternates.
        func alternates(_ command: CurioCommand) -> [UIMenuElement] {
            guard keybindings[command.rawValue] == nil else { return [] }
            let strokes = command.defaultKeystrokes.dropFirst().compactMap(KeyStroke.init).filter { !used.contains($0) }
            return strokes.enumerated().map { index, stroke in
                used.insert(stroke)
                // Each menu command needs its own identity; "#n" marks an alternate.
                let key = UIKeyCommand(title: command.title, action: #selector(BrowserViewController.performCurioCommand(_:)),
                                       input: stroke.input, modifierFlags: stroke.modifiers, propertyList: "\(command.rawValue)#\(index + 1)", attributes: .hidden)
                key.wantsPriorityOverSystemBehavior = true
                return key
            }
        }

        func menu(_ title: String, _ identifier: String, _ commands: [CurioCommand]) -> UIMenu {
            var children: [UIMenuElement] = commands.map { element($0) }
            for command in commands { children += alternates(command) }
            return UIMenu(title: title, identifier: UIMenu.Identifier("app.curio.menu.\(identifier)"), children: children)
        }

        builder.insertSibling(UIMenu(options: .displayInline, children: [element(.openSettings), element(.about)]), afterMenu: .about)
        builder.insertChild(UIMenu(options: .displayInline, children: [
            element(.newTab), element(.openCommandBar), element(.editURL), element(.newSpace),
            element(.closeTab), element(.reopenClosedTab), element(.duplicateTab), element(.print), element(.share),
        ]), atStartOfMenu: .file)
        builder.insertChild(UIMenu(options: .displayInline, children: [
            element(.findInPage), element(.findNext), element(.findPrevious), element(.copyURL),
        ]), atEndOfMenu: .edit)
        builder.insertChild(menu("Page", "page", [
            .toggleSidebar, .toggleTabLayout, .toggleLibrary, .reload, .stopLoading, .zoomIn, .zoomOut, .zoomReset, .openDevTools,
        ]), atStartOfMenu: .view)
        let history = menu("History", "history", [.goBack, .goForward, .showHistory, .showDownloads, .toggleBookmark])
        let tabs = menu("Tabs", "tabs", [
            .pinTab, .addFavorite, .newGroupFromTab, .nextTab, .previousTab,
            .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectLastTab,
        ])
        let spaces = menu("Spaces", "spaces", [
            .nextSpace, .previousSpace, .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4, .selectSpace5,
            .selectSpace6, .selectSpace7, .selectSpace8, .selectSpace9,
        ])
        let assistant = menu("Assistant", "assistant", [.toggleAIPanel, .newChat, .askAboutPage, .explainSelection])
        builder.insertSibling(history, afterMenu: .view)
        builder.insertSibling(tabs, afterMenu: history.identifier)
        builder.insertSibling(spaces, afterMenu: tabs.identifier)
        builder.insertSibling(assistant, afterMenu: spaces.identifier)
        builder.insertChild(UIMenu(options: .displayInline, children: [element(.escape, hidden: true)]), atEndOfMenu: assistant.identifier)
    }
}
