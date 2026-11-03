import Foundation

/// One-tap prompts for common browsing tasks.
nonisolated enum QuickAction: Equatable, Sendable {
    case summarizePage
    case keyPoints
    case explainSelection
    case summarizeSelection
    case translateSelection(language: String)
    case compareTabs

    /// The user message sent for this action.
    var prompt: String {
        switch self {
        case .summarizePage: "Summarize this page."
        case .keyPoints: "What are the most important points on this page?"
        case .explainSelection: "Explain the text I selected on this page."
        case .summarizeSelection: "Summarize the text I selected."
        case .translateSelection(let language): "Translate the text I selected into \(language). Reply with only the translation."
        case .compareTabs: "Compare these pages: where do they agree, where do they differ, and which is most useful for me?"
        }
    }

    var label: String {
        switch self {
        case .summarizePage, .summarizeSelection: "Summarize"
        case .keyPoints: "Key points"
        case .explainSelection: "Explain"
        case .translateSelection: "Translate"
        case .compareTabs: "Compare"
        }
    }
}
