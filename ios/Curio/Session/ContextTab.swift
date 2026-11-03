import Foundation

/// A tab that can be shared with the assistant.
struct ContextTab: Equatable {
    var id: UUID
    var title: String
    var url: String
    var favicon: String?
}
