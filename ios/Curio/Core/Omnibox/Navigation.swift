import Foundation

/// What address bar input resolves to.
nonisolated enum Navigation: Equatable, Sendable {
    case url(String)
    case search(query: String, url: String)

    var url: String {
        switch self {
        case .url(let url), .search(_, let url): url
        }
    }
}
