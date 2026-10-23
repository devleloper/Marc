import Darwin
import Foundation

/// Looks up the address of a site the user is likely to open next (a hovered link, the selected
/// Command Bar result) so the page's first request doesn't wait for DNS. Only the host name is
/// resolved, through the system resolver whose cache WebKit shares; nothing is fetched and no
/// connection is opened. Each host is looked up at most once a minute.
public final class HostPreresolver {
    /// Turned off with the "Look up link addresses in advance" setting.
    public var isEnabled: () -> Bool = { true }
    private let resolve: @Sendable (String) -> Void
    private let now: () -> Date
    private var recent: [String: Date] = [:]
    private let reuseInterval: TimeInterval = 60

    public init(
        resolve: @escaping @Sendable (String) -> Void = HostPreresolver.systemResolve,
        now: @escaping () -> Date = Date.init,
    ) {
        self.resolve = resolve
        self.now = now
    }

    /// Returns whether a lookup was started.
    @discardableResult
    public func preresolve(_ url: URL?) -> Bool {
        guard isEnabled(), let url, let host = Self.host(worthResolving: url) else { return false }
        let date = now()
        if let last = recent[host], date.timeIntervalSince(last) < reuseInterval { return false }
        recent[host] = date
        if recent.count > 256 {
            recent = recent.filter { date.timeIntervalSince($0.value) < reuseInterval }
        }
        let resolve = resolve
        Task.detached(priority: .utility) { resolve(host) }
        return true
    }

    /// The lowercased host of a web URL with a public-looking name; `nil` for other schemes, IP
    /// addresses and single-label names such as `localhost`, which gain nothing from a lookup.
    static func host(worthResolving url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(percentEncoded: false)?.lowercased(), host.contains(".")
        else { return nil }
        var ipv4 = in_addr(), ipv6 = in6_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 || inet_pton(AF_INET6, host, &ipv6) == 1 { return nil }
        return host
    }

    /// Resolves `host` with `getaddrinfo`, which fills the system DNS cache.
    public static let systemResolve: @Sendable (String) -> Void = { host in
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(host, "443", &hints, &result) == 0, let result {
            freeaddrinfo(result)
        }
    }
}
