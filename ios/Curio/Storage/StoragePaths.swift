import Foundation

/// Where Curio keeps its files.
nonisolated enum StoragePaths {
    #if DEBUG
    /// One isolated storage directory per UI test, reused when that test relaunches.
    private static let uiTestDirectory: URL? = {
        guard let value = ProcessInfo.processInfo.environment["CURIO_UI_TEST_ID"],
              let id = UUID(uuidString: value) else { return nil }
        return FileManager.default.temporaryDirectory
            .appending(path: "CurioUITests", directoryHint: .isDirectory)
            .appending(path: id.uuidString, directoryHint: .isDirectory)
    }()
    #endif

    /// Private app data: settings, session, history, chats.
    static var dataDirectory: URL {
        #if DEBUG
        if let uiTestDirectory { return uiTestDirectory }
        #endif
        return URL.applicationSupportDirectory.appending(path: "Curio", directoryHint: .isDirectory)
    }

    /// Downloads live in Documents so they show up in the Files app.
    static var downloadsDirectory: URL {
        #if DEBUG
        if let uiTestDirectory {
            return uiTestDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
        }
        #endif
        return URL.documentsDirectory.appending(path: "Downloads", directoryHint: .isDirectory)
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
