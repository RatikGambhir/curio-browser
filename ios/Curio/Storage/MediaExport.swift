import Foundation
import Photos

/// Keeps a temporary Photos export alive for the presentation that uses it.
nonisolated final class MediaExport: Sendable {
    let url: URL
    private let temporaryDirectory: URL?

    private init(url: URL, temporaryDirectory: URL? = nil) {
        self.url = url
        self.temporaryDirectory = temporaryDirectory
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    @concurrent
    static func prepare(_ item: MediaItem) async throws -> MediaExport {
        switch item.source {
        case .file(let url):
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return MediaExport(url: url)
        case .photo(let asset):
            guard let resource = MediaLibrary.primaryResource(for: asset) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let name = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
            let export = MediaExport(url: directory.appending(path: name), temporaryDirectory: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: export.url, options: nil)
            return export
        }
    }
}
