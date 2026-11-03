import Foundation

/// A download and where it was saved.
nonisolated struct DownloadRecord: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case inProgress = "in_progress"
        case completed
        case failed
    }

    var id = UUID()
    var url: String
    /// File name inside the Downloads folder, once known.
    var fileName: String?
    var state: State
    var startedAt: Timestamp

    var fileURL: URL? {
        fileName.map { StoragePaths.downloadsDirectory.appending(path: $0) }
    }

    /// The file name, or the host while it is unknown.
    var displayName: String { fileName ?? Curio.displayHost(url) }
}
