import Foundation
import Security

/// A Keychain failure with a readable message.
struct KeychainError: LocalizedError {
    var status: OSStatus
    var errorDescription: String? {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
    }
}
