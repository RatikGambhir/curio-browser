import Foundation
import OSLog

/// Serializes file writes off the main thread. Callers encode on their own
/// actor and hand over plain `Data`.
actor DiskWriter {
    static let shared = DiskWriter()
    private let log = Logger(subsystem: Curio.bundleID, category: "storage")

    func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log.error("Could not write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
