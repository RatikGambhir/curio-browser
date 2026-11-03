import Foundation

/// What the assistant is doing.
enum AssistantStatus {
    case idle
    /// Extracting the attached pages.
    case reading
    case thinking
    case writing

    var label: String {
        switch self {
        case .reading: "Reading your tabs…"
        case .thinking: "Thinking…"
        default: "Writing…"
        }
    }
}
