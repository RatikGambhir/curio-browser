import Foundation

/// The download list, newest first.
final class DownloadStore {
    private let file = JSONFile<[DownloadRecord]>("downloads.json")
    private(set) var records: [DownloadRecord]

    init() {
        records = file.load() ?? []
        // Downloads interrupted by the app quitting did not finish.
        for index in records.indices where records[index].state == .inProgress {
            records[index].state = .failed
        }
    }

    @discardableResult
    func start(url: String, fileName: String?) -> UUID {
        let record = DownloadRecord(url: url, fileName: fileName, state: .inProgress, startedAt: .now)
        records.insert(record, at: 0)
        file.save(records)
        return record.id
    }

    func finish(_ id: UUID, fileName: String?, success: Bool) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        if let fileName { records[index].fileName = fileName }
        records[index].state = success ? .completed : .failed
        file.save(records)
    }

    var hasActive: Bool { records.contains { $0.state == .inProgress } }
}
