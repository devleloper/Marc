import Foundation

public extension URL {
    /// Host without a leading `www.`, as shown in the address field.
    var displayHost: String? {
        guard let host = host(percentEncoded: false), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// A compact human-readable form without scheme, `www.` or trailing slash.
    var displayString: String {
        guard let host = displayHost else { return absoluteString }
        var result = host
        if let port { result += ":\(port)" }
        let path = path(percentEncoded: false)
        if path != "/" { result += path }
        if let query = query(percentEncoded: false), !query.isEmpty { result += "?" + query }
        return result
    }

    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func markdownLink(title: String) -> String {
        let escapedTitle = title
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escapedTitle.isEmpty ? absoluteString : escapedTitle)](\(absoluteString))"
    }

    /// Two URLs share an origin-like site when their hosts match ignoring `www.`.
    func isSameSite(as other: URL) -> Bool {
        guard let lhs = displayHost?.lowercased(), let rhs = other.displayHost?.lowercased() else { return false }
        return lhs == rhs || lhs.hasSuffix("." + rhs) || rhs.hasSuffix("." + lhs)
    }
}
