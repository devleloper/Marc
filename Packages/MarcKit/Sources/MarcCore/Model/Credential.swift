import Foundation

/// Saved login metadata. The password itself never leaves the secure store.
public struct Credential: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<Credential>

    public let id: ID
    /// Scheme, host and port of the login page, e.g. `https://example.com`.
    public var origin: String
    public var username: String
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(id: ID = ID(), origin: String, username: String, createdAt: Date = .now, lastUsedAt: Date? = nil) {
        self.id = id
        self.origin = origin
        self.username = username
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// Normalized origin for a URL, or `nil` if passwords must not be offered there.
    /// Only HTTPS origins and loopback HTTP origins qualify.
    public static func origin(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else {
            return nil
        }
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".localhost")
        guard scheme == "https" || (scheme == "http" && isLoopback) else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        if let port = url.port, port != defaultPort {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}
