import Foundation

/// Per-provider configuration (everything except the secret key).
nonisolated struct ProviderSettings: Codable, Equatable, Sendable {
    /// Model identifier; empty means the provider default.
    var model = ""
    /// API base URL; empty means the provider default.
    var baseURL = ""

    private enum CodingKeys: String, CodingKey { case model, baseURL = "base_url" }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
    }
}
