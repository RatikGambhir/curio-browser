import AVFoundation
import ImageIO
import Photos
import UIKit

/// Keeps decoding bounded while allowing the most recently displayed tiles to go first.
final class MediaThumbnails {
    private struct Request {
        let id: UUID
        let item: MediaItem
        let completion: (UIImage?) -> Void
    }

    private struct Running {
        let request: Request
        let cancel: () -> Void
        let cancelsImmediately: Bool
        var cancelled = false
    }

    private enum Cached {
        case image(UIImage)
        case unavailable
    }

    private nonisolated static let pixelSize = 320
    private var photoManager = PHCachingImageManager()
    private var pending: [Request] = []
    private var running: [UUID: Running] = [:]
    private var cache: [MediaItem: Cached] = [:]
    private var recency: [MediaItem] = []

    func request(_ item: MediaItem, completion: @escaping (UIImage?) -> Void) -> UUID? {
        if let entry = cache[item] {
            touch(item)
            switch entry {
            case .image(let image): completion(image)
            case .unavailable: completion(nil)
            }
            return nil
        }

        let request = Request(id: UUID(), item: item, completion: completion)
        pending.append(request)
        if pending.count > 48 { pending.removeFirst() }
        startNext()
        return request.id
    }

    func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
        stop(id)
        startNext()
    }

    func clearCache() {
        cache.removeAll()
        recency.removeAll()
        resetPhotoManager()
    }

    func removePhotos() {
        pending.removeAll { $0.item.isFromPhotos }
        for (id, work) in running where work.request.item.isFromPhotos { stop(id) }
        for item in recency where item.isFromPhotos { cache[item] = nil }
        recency.removeAll(where: \.isFromPhotos)
        resetPhotoManager()
        startNext()
    }

    private func resetPhotoManager() {
        photoManager.stopCachingImagesForAllAssets()
        // Drop PhotoKit's manager cache along with Curio's own cache.
        photoManager = PHCachingImageManager()
    }

    func reset() {
        pending.removeAll()
        for id in Array(running.keys) { stop(id) }
        clearCache()
    }

    private func stop(_ id: UUID) {
        guard var work = running[id], !work.cancelled else { return }
        if work.cancelsImmediately {
            running[id] = nil
        } else {
            // Image I/O is synchronous. Hold the slot until that work actually exits.
            work.cancelled = true
            running[id] = work
        }
        work.cancel()
    }

    private func startNext() {
        while running.count < 3, let request = pending.popLast() {
            let id = request.id
            switch request.item.source {
            case .file(let url):
                let task = Task { [weak self] in
                    let image = await Self.fileThumbnail(url, kind: request.item.kind, size: request.item.fileSize)
                    self?.finish(id, image: image)
                }
                running[id] = Running(request: request, cancel: { task.cancel() }, cancelsImmediately: false)
            case .photo(let asset):
                let manager = photoManager
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .exact
                options.isNetworkAccessAllowed = false
                let size = CGSize(width: Self.pixelSize, height: Self.pixelSize)
                let photoRequest = manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                        options: options) { @Sendable [weak self] image, _ in
                    Task { @MainActor in self?.finish(id, image: image) }
                }
                running[id] = Running(request: request, cancel: { manager.cancelImageRequest(photoRequest) },
                                      cancelsImmediately: true)
            }
        }
    }

    private func finish(_ id: UUID, image: UIImage?) {
        guard let work = running.removeValue(forKey: id) else { return }
        if !work.cancelled {
            let item = work.request.item
            cache[item] = image.map(Cached.image) ?? .unavailable
            touch(item)
            if recency.count > 120 { cache[recency.removeFirst()] = nil }
            work.request.completion(image)
        }
        startNext()
    }

    private func touch(_ item: MediaItem) {
        recency.removeAll { $0 == item }
        recency.append(item)
    }

    @concurrent
    private nonisolated static func fileThumbnail(_ url: URL, kind: MediaItem.Kind, size: Int?) async -> UIImage? {
        guard !Task.isCancelled, let size, size <= 80_000_000 else { return nil }
        switch kind {
        case .image:
            guard url.pathExtension.lowercased() != "svg",
                  let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        case .video:
            let asset = AVURLAsset(url: url, options: [
                AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue,
            ])
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)
            for await frame in generator.images(for: [.zero]) {
                if case .success(_, let image, _) = frame { return UIImage(cgImage: image) }
            }
            return nil
        }
    }
}
