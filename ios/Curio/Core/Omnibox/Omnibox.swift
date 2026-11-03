import Foundation

/// Classifies address bar input as a URL or a web search.
nonisolated enum Omnibox {
    /// Schemes the browser will navigate to directly. Anything else (for
    /// example `javascript:`) is searched, never executed.
    private static let allowedSchemes: Set<String> = ["http", "https", "file", "about", "data", "curio"]

    /// Returns `nil` for blank input.
    static func classify(_ input: String, engine: SearchEngine) -> Navigation? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let search = Navigation.search(query: text, url: engine.searchURL(for: text))

        if text.contains(where: \.isWhitespace) { return search }

        if let colon = text.firstIndex(of: ":") {
            let scheme = String(text[..<colon])
            let rest = text[text.index(after: colon)...]
            let looksLikeScheme = !scheme.isEmpty && scheme.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || "+-.".contains($0) }
            let portPart = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let isPort = !portPart.isEmpty && portPart.allSatisfy { $0.isASCII && $0.isNumber }
            if looksLikeScheme && !isPort {
                if allowedSchemes.contains(scheme.lowercased()) {
                    return URL(string: text).map { .url($0.absoluteString) } ?? search
                }
                return search
            }
        }

        let hostPart = String(text.split(whereSeparator: { "/?#".contains($0) }).first ?? "")
        var host = hostPart
        if let colon = hostPart.lastIndex(of: ":") {
            let port = hostPart[hostPart.index(after: colon)...]
            if port.allSatisfy({ $0.isASCII && $0.isNumber }) { host = String(hostPart[..<colon]) }
        }

        let ipv4 = parseIPv4(host)
        let lowered = host.lowercased()
        let isLocal = lowered == "localhost"
            || ipv4.map { isLoopback($0) || isPrivate($0) || isLinkLocal($0) } == true
            || lowered.hasSuffix(".local") || lowered.hasSuffix(".test") || lowered.hasSuffix(".localhost")
        let isIP = ipv4 != nil || (host.hasPrefix("[") && host.hasSuffix("]"))
        let tld = host.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
        let isDomain = host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
            && tld.count >= 2 && tld.allSatisfy { ($0.isASCII && $0.isLetter) || $0 == "-" }
            && host.allSatisfy { $0.isLetter || $0.isNumber || ".-_".contains($0) }

        if isLocal || isIP || isDomain {
            let scheme = isLocal ? "http" : "https"
            guard let url = URL(string: "\(scheme)://\(text)") else { return search }
            var absolute = url.absoluteString
            // Match the desktop parser: a bare host gets a trailing slash.
            if url.path.isEmpty && url.query == nil && url.fragment == nil { absolute += "/" }
            return .url(absolute)
        }
        return search
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> UInt8? in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return UInt8(part)
        }
        return octets.count == 4 ? octets : nil
    }

    private static func isLoopback(_ ip: [UInt8]) -> Bool { ip[0] == 127 }
    private static func isLinkLocal(_ ip: [UInt8]) -> Bool { ip[0] == 169 && ip[1] == 254 }
    private static func isPrivate(_ ip: [UInt8]) -> Bool {
        ip[0] == 10 || (ip[0] == 172 && (16...31).contains(ip[1])) || (ip[0] == 192 && ip[1] == 168)
    }
}
