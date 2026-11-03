import Foundation

/// One command bar result.
struct CommandItem {
    enum Leading {
        case icon(Icon)
        case site(favicon: String?, label: String)
    }

    var key: String
    var leading: Leading
    var title: String
    var subtitle: String?
    var badge: String?
    var target: CommandTarget
}
