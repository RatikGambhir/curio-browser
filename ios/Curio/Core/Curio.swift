import Foundation

/// App-wide constants and small helpers shared by every layer.
nonisolated enum Curio {
    static let appName = "Curio"
    static let bundleID = "app.curio.browser"
    /// The URL of Curio's own new tab page.
    static let newTabURL = "curio://newtab"

    /// Whether `url` is one of Curio's own pages.
    static func isInternalURL(_ url: String) -> Bool {
        url.hasPrefix("curio://")
    }

    /// A short, human-friendly host for a URL: `www.` is dropped, paths are
    /// ignored, and Curio's own pages show as "Curio".
    static func displayHost(_ url: String) -> String {
        if isInternalURL(url) { return appName }
        guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty else {
            return url
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
