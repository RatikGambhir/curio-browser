import Foundation

/// An incremental Server-Sent Events parser. Lines are fed without their
/// newline; a blank line completes an event.
nonisolated struct SSEParser: Sendable {
    private var event: String?
    private var data: String?

    mutating func feed(_ rawLine: String) -> SSEEvent? {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return dispatch() }
        if line.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = line.firstIndex(of: ":") {
            field = line[..<colon]
            value = line[line.index(after: colon)...]
            if value.hasPrefix(" ") { value = value.dropFirst() }
        } else {
            field = line[...]
            value = ""
        }
        switch field {
        case "event": event = String(value)
        case "data": data = data.map { $0 + "\n" + value } ?? String(value)
        default: break
        }
        return nil
    }

    /// Flushes a pending event at end of stream.
    mutating func finish() -> SSEEvent? { dispatch() }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            data = nil
            event = nil
        }
        guard let data else { return nil }
        return SSEEvent(event: event ?? "message", data: data)
    }
}
