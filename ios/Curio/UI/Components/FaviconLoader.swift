import ImageIO
import UIKit

/// Downloads and caches favicons, downsampled to icon size.
final class FaviconLoader {
    static let shared = FaviconLoader()

    // Cache failed candidates too, so another view can go straight to the fallback.
    private let cache = NSCache<NSURL, NSObject>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        self.session = session ?? URLSession(configuration: configuration)
        cache.countLimit = 512
    }

    static func candidates(declared: String?, pageURL: String?) -> [URL] {
        var declaredComponents = declared.flatMap(httpComponents)
        declaredComponents?.fragment = nil
        let primary = declaredComponents?.url
        let fallback = pageURL.flatMap { pageURL -> URL? in
            guard let page = httpComponents(pageURL) else { return nil }
            var origin = URLComponents()
            origin.scheme = page.scheme
            origin.percentEncodedHost = page.percentEncodedHost
            origin.port = page.port
            origin.path = "/favicon.ico"
            return origin.url
        }
        return [primary, fallback == primary ? nil : fallback].compactMap { $0 }
    }

    private static func httpComponents(_ value: String) -> URLComponents? {
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.percentEncodedHost, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.percentEncodedHost = host.lowercased()
        if components.port == (scheme == "http" ? 80 : 443) { components.port = nil }
        return components
    }

    func cachedImage(for candidates: [URL]) -> UIImage? {
        for url in candidates {
            guard let result = cache.object(forKey: url as NSURL) else { return nil }
            if let image = result as? UIImage { return image }
        }
        return nil
    }

    func image(for candidates: [URL]) async -> UIImage? {
        for url in candidates {
            guard !Task.isCancelled else { return nil }
            if let image = await image(at: url) { return image }
        }
        return nil
    }

    private func image(at url: URL) async -> UIImage? {
        if let result = cache.object(forKey: url as NSURL) { return result as? UIImage }
        if let task = inFlight[url] { return await task.value }
        let session = session
        let task = Task<UIImage?, Never> { await Self.download(url, session: session) }
        inFlight[url] = task
        let image = await task.value
        cache.setObject(image.map { $0 as NSObject } ?? NSNull(), forKey: url as NSURL)
        inFlight[url] = nil
        return image
    }

    /// Decode and downsample before returning an image to UIKit.
    @concurrent
    private nonisolated static func download(_ url: URL, session: URLSession) async -> UIImage? {
        let source: CGImageSource?
        do {
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
            // Browser content can use Curio's existing WebKit transport policy.
            guard let file = await WebFaviconDownload.file(for: url) else { return nil }
            defer { try? FileManager.default.removeItem(at: file) }
            return decode(CGImageSourceCreateWithURL(file as CFURL, nil))
        } catch {
            return nil
        }
        return decode(source)
    }

    private nonisolated static func decode(_ source: CGImageSource?) -> UIImage? {
        guard let source, let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}
