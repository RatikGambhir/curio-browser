import UIKit

/// Downloads and caches favicons, downsampled to icon size.
final class FaviconLoader {
    static let shared = FaviconLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    func cached(_ url: String) -> UIImage? { cache.object(forKey: url as NSString) }

    func image(for url: String) async -> UIImage? {
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        guard let target = URL(string: url), target.scheme?.hasPrefix("http") == true else { return nil }
        let session = session
        let task = Task<UIImage?, Never> { await Self.download(target, session: session) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSString) }
        return image
    }

    /// Downloads, decodes and downsamples off the main thread.
    @concurrent
    private nonisolated static func download(_ url: URL, session: URLSession) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let image = UIImage(data: data) else { return nil }
        return image.preparingThumbnail(of: CGSize(width: 64, height: 64)) ?? image
    }
}
