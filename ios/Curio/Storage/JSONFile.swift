import Foundation
import OSLog

/// Reads and writes one Codable value as a JSON file.
struct JSONFile<Value: Codable> {
    let url: URL
    private let log = Logger(subsystem: Curio.bundleID, category: "storage")

    init(_ name: String) {
        url = StoragePaths.file(name)
    }

    init(url: URL) {
        self.url = url
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            log.error("Could not read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Encodes now and writes in the background.
    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let url = url
        Task { await DiskWriter.shared.write(data, to: url) }
    }

    /// Encodes and writes before returning (used when the app is
    /// backgrounded and may be suspended).
    func saveNow(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
