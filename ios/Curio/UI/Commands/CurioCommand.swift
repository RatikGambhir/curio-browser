import UIKit

/// Every browser action, named like the desktop's (`curio::NewTab`), so
/// keybinding overrides are shared between apps.
nonisolated enum CurioCommand: String, CaseIterable, Sendable {
    case newTab = "curio::NewTab"
    case openCommandBar = "curio::OpenCommandBar"
    case editURL = "curio::EditUrl"
    case closeTab = "curio::CloseTab"
    case reopenClosedTab = "curio::ReopenClosedTab"
    case duplicateTab = "curio::DuplicateTab"
    case pinTab = "curio::PinTab"
    case nextTab = "curio::NextTab"
    case previousTab = "curio::PreviousTab"
    case selectTab1 = "curio::SelectTab1"
    case selectTab2 = "curio::SelectTab2"
    case selectTab3 = "curio::SelectTab3"
    case selectTab4 = "curio::SelectTab4"
    case selectTab5 = "curio::SelectTab5"
    case selectTab6 = "curio::SelectTab6"
    case selectTab7 = "curio::SelectTab7"
    case selectTab8 = "curio::SelectTab8"
    case selectLastTab = "curio::SelectLastTab"
    case newGroupFromTab = "curio::NewGroupFromTab"
    case addFavorite = "curio::AddFavorite"
    case toggleBookmark = "curio::ToggleBookmark"
    case copyURL = "curio::CopyUrl"
    case goBack = "curio::GoBack"
    case goForward = "curio::GoForward"
    case reload = "curio::Reload"
    case stopLoading = "curio::StopLoading"
    case escape = "curio::Escape"
    case findInPage = "curio::FindInPage"
    case findNext = "curio::FindNext"
    case findPrevious = "curio::FindPrevious"
    case zoomIn = "curio::ZoomIn"
    case zoomOut = "curio::ZoomOut"
    case zoomReset = "curio::ZoomReset"
    case openDevTools = "curio::OpenDevTools"
    case print = "curio::Print"
    case share = "curio::Share"
    case showHistory = "curio::ShowHistory"
    case showDownloads = "curio::ShowDownloads"
    case newSpace = "curio::NewSpace"
    case nextSpace = "curio::NextSpace"
    case previousSpace = "curio::PreviousSpace"
    case selectSpace1 = "curio::SelectSpace1"
    case selectSpace2 = "curio::SelectSpace2"
    case selectSpace3 = "curio::SelectSpace3"
    case selectSpace4 = "curio::SelectSpace4"
    case selectSpace5 = "curio::SelectSpace5"
    case selectSpace6 = "curio::SelectSpace6"
    case selectSpace7 = "curio::SelectSpace7"
    case selectSpace8 = "curio::SelectSpace8"
    case selectSpace9 = "curio::SelectSpace9"
    case toggleSidebar = "curio::ToggleSidebar"
    case toggleTabLayout = "curio::ToggleTabLayout"
    case toggleAIPanel = "curio::ToggleAiPanel"
    case explainSelection = "curio::ExplainSelection"
    case newChat = "curio::NewChat"
    case askAboutPage = "curio::AskAboutPage"
    case toggleLibrary = "curio::ToggleLibrary"
    case openSettings = "curio::OpenSettings"
    case about = "curio::About"

    /// The desktop's default shortcuts (`secondary` is ⌘).
    var defaultKeystrokes: [String] {
        switch self {
        case .openSettings: ["secondary-,"]
        case .newTab: ["secondary-t"]
        case .openCommandBar: ["secondary-k"]
        case .editURL: ["secondary-l"]
        case .closeTab: ["secondary-w"]
        case .reopenClosedTab: ["shift-secondary-t"]
        case .duplicateTab: ["shift-secondary-k"]
        case .pinTab: ["secondary-d"]
        case .nextTab: ["ctrl-tab", "shift-secondary-]"]
        case .previousTab: ["ctrl-shift-tab", "shift-secondary-["]
        case .selectTab1: ["secondary-1"]
        case .selectTab2: ["secondary-2"]
        case .selectTab3: ["secondary-3"]
        case .selectTab4: ["secondary-4"]
        case .selectTab5: ["secondary-5"]
        case .selectTab6: ["secondary-6"]
        case .selectTab7: ["secondary-7"]
        case .selectTab8: ["secondary-8"]
        case .selectLastTab: ["secondary-9"]
        case .newGroupFromTab: ["alt-secondary-g"]
        case .toggleBookmark: ["shift-secondary-d"]
        case .copyURL: ["shift-secondary-c"]
        case .goBack: ["secondary-["]
        case .goForward: ["secondary-]"]
        case .reload: ["secondary-r"]
        case .stopLoading: ["secondary-."]
        case .escape: ["escape"]
        case .findInPage: ["secondary-f"]
        case .findNext: ["secondary-g"]
        case .findPrevious: ["shift-secondary-g"]
        case .zoomIn: ["secondary-=", "secondary-+"]
        case .zoomOut: ["secondary--"]
        case .zoomReset: ["secondary-0"]
        case .openDevTools: ["alt-secondary-i"]
        case .print: ["secondary-p"]
        case .showHistory: ["secondary-y"]
        case .showDownloads: ["alt-secondary-l"]
        case .newSpace: ["shift-secondary-n"]
        case .nextSpace: ["ctrl-secondary-right"]
        case .previousSpace: ["ctrl-secondary-left"]
        case .selectSpace1: ["ctrl-1"]
        case .selectSpace2: ["ctrl-2"]
        case .selectSpace3: ["ctrl-3"]
        case .selectSpace4: ["ctrl-4"]
        case .selectSpace5: ["ctrl-5"]
        case .selectSpace6: ["ctrl-6"]
        case .selectSpace7: ["ctrl-7"]
        case .selectSpace8: ["ctrl-8"]
        case .selectSpace9: ["ctrl-9"]
        case .toggleSidebar: ["secondary-s"]
        case .toggleTabLayout: ["alt-secondary-t"]
        case .toggleAIPanel: ["secondary-e"]
        case .explainSelection: ["shift-secondary-e"]
        case .newChat: ["shift-secondary-o"]
        case .addFavorite, .askAboutPage, .toggleLibrary, .about, .share: []
        }
    }

    /// The keystroke in effect: a user override (empty unbinds) or the default.
    func keystroke(overrides: [String: String]) -> String? {
        if let custom = overrides[rawValue] { return custom.isEmpty ? nil : custom }
        return defaultKeystrokes.first
    }

    /// Every keystroke in effect (defaults can have more than one).
    func keystrokes(overrides: [String: String]) -> [String] {
        if let custom = overrides[rawValue] { return custom.isEmpty ? [] : [custom] }
        return defaultKeystrokes
    }

    var title: String {
        switch self {
        case .newTab: "New Tab"
        case .openCommandBar: "Command Palette"
        case .editURL: "Edit Address"
        case .closeTab: "Close Tab"
        case .reopenClosedTab: "Reopen Closed Tab"
        case .duplicateTab: "Duplicate Tab"
        case .pinTab: "Pin or Unpin Tab"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8:
            "Go to Tab \(rawValue.suffix(1))"
        case .selectLastTab: "Go to Last Tab"
        case .newGroupFromTab: "New Group from Tab"
        case .addFavorite: "Add Tab to Favorites"
        case .toggleBookmark: "Bookmark Page"
        case .copyURL: "Copy URL"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .reload: "Reload"
        case .stopLoading: "Stop"
        case .escape: "Escape"
        case .findInPage: "Find in Page"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .zoomReset: "Actual Size"
        case .openDevTools: "Developer Tools"
        case .print: "Print…"
        case .share: "Share…"
        case .showHistory: "Show History"
        case .showDownloads: "Show Downloads"
        case .newSpace: "New Space"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4, .selectSpace5, .selectSpace6, .selectSpace7, .selectSpace8, .selectSpace9:
            "Go to Space \(rawValue.suffix(1))"
        case .toggleSidebar: "Toggle Sidebar"
        case .toggleTabLayout: "Switch Vertical / Horizontal Tabs"
        case .toggleAIPanel: "Toggle Curio Assistant"
        case .explainSelection: "Explain Selection"
        case .newChat: "New Chat"
        case .askAboutPage: "Summarize This Page"
        case .toggleLibrary: "Open Library"
        case .openSettings: "Settings"
        case .about: "About Curio"
        }
    }

    var icon: Icon {
        switch self {
        case .newSpace, .newTab, .zoomIn: .plus
        case .toggleAIPanel: .bot
        case .askAboutPage, .explainSelection: .sparkles
        case .newChat: .message
        case .toggleSidebar: .sidebar
        case .toggleLibrary: .library
        case .toggleTabLayout: .layout
        case .pinTab: .star
        case .addFavorite: .heart
        case .toggleBookmark: .book
        case .duplicateTab: .copy
        case .newGroupFromTab: .folder
        case .copyURL: .link
        case .reopenClosedTab: .undo
        case .closeTab, .stopLoading, .escape: .close
        case .findInPage, .findNext, .findPrevious: .search
        case .showHistory: .history
        case .showDownloads: .download
        case .openSettings: .settings
        case .zoomOut: .minus
        case .zoomReset: .maximize
        case .openDevTools: .terminal
        case .nextSpace, .nextTab: .chevronRight
        case .previousSpace, .previousTab: .chevronLeft
        case .goBack: .back
        case .goForward: .forward
        case .reload: .reload
        case .print: .printer
        case .share: .share
        case .editURL: .globe
        case .openCommandBar: .command
        case .about: .info
        default: .chevronRight
        }
    }

    /// Commands listed in the command palette, in the desktop's order.
    static let palette: [CurioCommand] = [
        .newSpace, .toggleAIPanel, .askAboutPage, .newChat, .toggleSidebar, .toggleLibrary, .toggleTabLayout,
        .pinTab, .addFavorite, .toggleBookmark, .duplicateTab, .newGroupFromTab, .copyURL, .reopenClosedTab,
        .closeTab, .findInPage, .share, .print, .showHistory, .showDownloads, .openSettings, .zoomIn, .zoomOut, .zoomReset,
        .openDevTools, .nextSpace, .previousSpace,
    ]
}
