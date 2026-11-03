import Foundation
import Security

/// AI provider API keys, stored in the Keychain and never in Curio's files.
final class KeychainStore {
    private let service = Curio.bundleID

    private func query(_ provider: AIProviderKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
    }

    /// The stored key for `provider`.
    func apiKey(for provider: AIProviderKind) -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    func hasStoredKey(_ provider: AIProviderKind) -> Bool { apiKey(for: provider) != nil }

    /// Saves a key; an empty key removes it.
    func setAPIKey(_ key: String, for provider: AIProviderKind) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(query(provider) as CFDictionary)
        guard !key.isEmpty else { return }
        var attributes = query(provider)
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }
}
