import Foundation

/// Where Curio keeps its files.
nonisolated enum StoragePaths {
    /// Private app data: settings, session, history, chats.
    static var dataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Curio", directoryHint: .isDirectory)
    }

    /// Downloads live in Documents so they show up in the Files app.
    static var downloadsDirectory: URL {
        URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
    }

    static func file(_ name: String) -> URL {
        dataDirectory.appending(path: name)
    }

    static func ensureDirectories() {
        for directory in [dataDirectory, downloadsDirectory, dataDirectory.appending(path: "conversations")] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
