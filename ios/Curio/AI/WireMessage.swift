import Foundation

/// One message on the wire.
nonisolated struct WireMessage: Equatable, Sendable {
    var role: Role
    var content: String
}
