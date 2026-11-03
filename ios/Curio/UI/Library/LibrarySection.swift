import Foundation

/// A collection in the library.
enum LibrarySection: CaseIterable {
    case media, downloads, notes, spaces, calendar, archivedTabs, clipboardHistory, aliases, inbox

    var label: String {
        switch self {
        case .media: "Media"
        case .downloads: "Downloads"
        case .notes: "Notes"
        case .spaces: "Spaces"
        case .calendar: "Calendar"
        case .archivedTabs: "Archived Tabs"
        case .clipboardHistory: "Clipboard History"
        case .aliases: "Aliases"
        case .inbox: "Inbox"
        }
    }

    var icon: Icon {
        switch self {
        case .media: .media
        case .downloads: .downloadCircle
        case .notes: .notes
        case .spaces: .layers
        case .calendar: .calendar
        case .archivedTabs: .archive
        case .clipboardHistory: .clipboard
        case .aliases: .at
        case .inbox: .inbox
        }
    }

    /// Whether the section lists real items yet.
    var hasContent: Bool {
        switch self {
        case .notes, .calendar, .clipboardHistory, .aliases, .inbox: false
        default: true
        }
    }

    var searchPlaceholder: String {
        switch self {
        case .archivedTabs: "Search Archive…"
        case .clipboardHistory: "Search Clipboard…"
        default: "Search \(label)…"
        }
    }

    var emptyCopy: (title: String, description: String) {
        switch self {
        case .media: ("No media yet", "Images and videos you download show up here.")
        case .downloads: ("No downloads yet", "Files you download show up here.")
        case .notes: ("No notes yet", "Notes you write will live here.")
        case .spaces: ("No spaces yet", "Create a space to organize your tabs.")
        case .calendar: ("Nothing scheduled", "Your upcoming events will show up here.")
        case .archivedTabs: ("Nothing here yet!", "Tabs you close are archived here, so you can bring them back.")
        case .clipboardHistory: ("Nothing copied yet", "Text and links you copy will show up here.")
        case .aliases: ("No aliases yet", "Short names you give to sites and pages will show up here.")
        case .inbox: ("You’re all caught up", "New items will land here.")
        }
    }
}
