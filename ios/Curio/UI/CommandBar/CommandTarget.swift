import Foundation

/// What choosing a command bar result does.
enum CommandTarget: Equatable {
    case navigate(url: String, newTab: Bool)
    case switchTab(UUID)
    case command(CurioCommand)
    case askAI(String)
}
