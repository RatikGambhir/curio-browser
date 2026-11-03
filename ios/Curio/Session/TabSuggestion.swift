import Foundation

/// An open tab offered by the command bar's "Switch to Tab".
struct TabSuggestion: Equatable {
    var id: UUID
    var title: String
    var url: String
    var favicon: String?
    var space: String
}
