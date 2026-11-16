import Foundation
import Photos

/// Builds a bounded, read-only catalog of Curio's local files and accessible Photos assets.
nonisolated enum MediaLibrary {
    struct ScanLimits {
        var depth = 6
        var entries = 60_000
        var files = 5_000
    }

    @concurrent
    static func load(includePhotos: Bool, extraDownloads: [URL]) async -> [MediaItem] {
        let limits = ScanLimits()
        let files = scanFiles(in: .documentsDirectory, extraDownloads: extraDownloads, limits: limits)
        guard includePhotos, !Task.isCancelled else { return files }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType IN %@", [
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue,
        ])
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limits.files
        let assets = PHAsset.fetchAssets(with: options)
        var photos: [MediaItem] = []
        photos.reserveCapacity(assets.count)
        for index in 0..<assets.count {
            guard !Task.isCancelled else { break }
            let asset = assets.object(at: index)
            let kind: MediaItem.Kind = asset.mediaType == .video ? .video : .image
            let name = primaryResource(for: asset)?.originalFilename ?? (kind == .video ? "Video" : "Photo")
            photos.append(MediaItem(source: .photo(asset), name: name, folder: "Photos", kind: kind,
                                    date: asset.creationDate ?? .distantPast, modificationDate: asset.modificationDate,
                                    fileSize: nil))
        }
        return Array((files + photos).sorted(by: MediaItem.newestFirst).prefix(limits.files))
    }

    static func primaryResource(for asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        return resources.first { $0.type == (isVideo ? .fullSizeVideo : .fullSizePhoto) }
            ?? resources.first { $0.type == (isVideo ? .video : .photo) }
    }

    private static let buildFolders: Set<String> = [
        "node_modules", "target", "build", "dist", "DerivedData", "Pods", "vendor", "__pycache__", "venv",
    ]
    private static let packageExtensions: Set<String> = [
        "app", "appex", "bundle", "framework", "plugin", "kext", "photoslibrary", "photolibrary",
        "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle", "logicx", "xcodeproj", "xcworkspace",
        "xcassets", "pages", "numbers", "key", "rtfd",
    ]
    private static let fileKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey,
    ]

    static func scanFiles(in documents: URL, extraDownloads: [URL] = [], limits: ScanLimits = .init()) -> [MediaItem] {
        let root = documents.standardizedFileURL.resolvingSymlinksInPath()
        let downloadsPath = root.appending(path: "Downloads").path(percentEncoded: false) + "/"
        var items: [MediaItem] = []
        var seen: Set<URL> = []

        func appendFile(_ url: URL, values: URLResourceValues, folder: String, canonicalURL: URL) {
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let size = values.fileSize, size > 0, let kind = MediaItem.Kind(fileURL: url),
                  seen.insert(canonicalURL).inserted else { return }
            items.append(MediaItem(source: .file(canonicalURL), name: url.lastPathComponent, folder: folder,
                                   kind: kind, date: values.contentModificationDate ?? .distantPast,
                                   modificationDate: values.contentModificationDate, fileSize: size))
        }

        if let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(fileKeys),
                                                        errorHandler: { _, _ in true }) {
            for _ in 0..<limits.entries {
                guard !Task.isCancelled, let url = entries.nextObject() as? URL else { break }
                guard let values = try? url.resourceValues(forKeys: fileKeys), values.isSymbolicLink != true,
                      !url.lastPathComponent.hasPrefix(".") else {
                    entries.skipDescendants()
                    continue
                }

                if values.isDirectory == true {
                    if entries.level > limits.depth || buildFolders.contains(url.lastPathComponent)
                        || packageExtensions.contains(url.pathExtension.lowercased()) {
                        entries.skipDescendants()
                    }
                } else {
                    let folder = url.path(percentEncoded: false).hasPrefix(downloadsPath) ? "Downloads" : "Documents"
                    appendFile(url, values: values, folder: folder, canonicalURL: url.standardizedFileURL)
                }
            }
        }

        for url in extraDownloads {
            guard !Task.isCancelled else { break }
            guard !url.lastPathComponent.hasPrefix("."), let values = try? url.resourceValues(forKeys: fileKeys),
                  values.isSymbolicLink != true else { continue }
            appendFile(url, values: values, folder: "Downloads",
                       canonicalURL: url.standardizedFileURL.resolvingSymlinksInPath())
        }
        return Array(items.sorted(by: MediaItem.newestFirst).prefix(limits.files))
    }
}
