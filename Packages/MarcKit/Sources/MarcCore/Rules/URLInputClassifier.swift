import Foundation

/// Decides whether text typed into the address field is a URL to open or a query to search.
public struct URLInputClassifier: Sendable {
    public enum Result: Hashable, Sendable {
        case url(URL)
        case search(String)
    }

    /// Schemes recognized without `//` (for example `mailto:` or `about:blank`).
    static let opaqueSchemes: Set = [
        "about", "data", "javascript", "mailto", "tel", "sms", "facetime", "facetime-audio", "maps", "webcal", "file",
    ]

    /// Host suffixes reserved for local or private use; they are opened over plain HTTP.
    static let localSuffixes: Set = ["localhost", "local", "test", "internal", "lan", "home.arpa"]

    private let topLevelDomains: Set<String>

    public init(topLevelDomains: Set<String> = TopLevelDomains.all) {
        self.topLevelDomains = topLevelDomains
    }

    public func classify(_ input: String) -> Result? {
        let text = input
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !text.isEmpty else { return nil }

        if let url = urlWithExplicitScheme(text) {
            return .url(url)
        }
        if text.contains(" ") {
            return .search(text)
        }
        if let url = urlFromHostLikeText(text) {
            return .url(url)
        }
        return .search(text)
    }

    // MARK: - Explicit schemes

    private func urlWithExplicitScheme(_ text: String) -> URL? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = text[..<colon].lowercased()
        let remainder = text[text.index(after: colon)...]
        guard let first = scheme.first, first.isASCII, first.isLetter,
              scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
        else { return nil }

        // "localhost:3000" or "example.com:8080/path" is a host with a port, not a scheme.
        if remainder.first?.isNumber == true, isHostWithPort(scheme: scheme, remainder: remainder) {
            return nil
        }

        let hasAuthority = remainder.hasPrefix("//")
        guard hasAuthority || Self.opaqueSchemes.contains(scheme) else { return nil }
        if scheme == "http" || scheme == "https", remainder.dropFirst(2).isEmpty { return nil }
        return Self.makeURL(scheme + ":" + remainder)
    }

    private func isHostWithPort(scheme: String, remainder: Substring) -> Bool {
        let portDigits = remainder.prefix { $0.isNumber }
        let rest = remainder.dropFirst(portDigits.count)
        guard rest.isEmpty || rest.first.map({ "/?#".contains($0) }) == true else { return false }
        return scheme == "localhost" || scheme.contains(".")
    }

    // MARK: - Host-like text

    private func urlFromHostLikeText(_ text: String) -> URL? {
        let authorityEnd = text.firstIndex { "/?#".contains($0) } ?? text.endIndex
        let authority = String(text[..<authorityEnd])
        guard !authority.isEmpty, !authority.contains("@") else { return nil }

        let (host, port) = splitHostAndPort(authority)
        guard let host, port.map({ $0 > 0 && $0 <= 65535 }) ?? true else { return nil }

        let lowercasedHost = host.lowercased()
        let scheme: String
        if lowercasedHost == "localhost" || isIPAddress(lowercasedHost) || isLocalHost(lowercasedHost) {
            scheme = "http"
        } else if isPublicHostname(lowercasedHost) {
            scheme = "https"
        } else if port != nil, isValidLabel(lowercasedHost) {
            // A single-label intranet host with an explicit port, e.g. "devbox:8080".
            scheme = "http"
        } else {
            return nil
        }
        return Self.makeURL("\(scheme)://\(text)")
    }

    private func splitHostAndPort(_ authority: String) -> (String?, Int?) {
        if authority.hasPrefix("[") {
            guard let close = authority.firstIndex(of: "]") else { return (nil, nil) }
            let host = String(authority[...close])
            let rest = authority[authority.index(after: close)...]
            if rest.isEmpty { return (host, nil) }
            guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return (nil, nil) }
            return (host, port)
        }
        let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1: return (authority, nil)
        case 2:
            guard let port = Int(parts[1]) else { return (nil, nil) }
            return (String(parts[0]), port)
        default: return (nil, nil)
        }
    }

    private func isIPAddress(_ host: String) -> Bool {
        if host.hasPrefix("["), host.hasSuffix("]") {
            return host.dropFirst().dropLast().allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." }
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { octet in
            !octet.isEmpty && octet.count <= 3 && octet.allSatisfy(\.isNumber) && (Int(octet) ?? 256) <= 255
        }
    }

    private func isLocalHost(_ host: String) -> Bool {
        let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = trimmed.split(separator: ".")
        guard labels.count >= 2, labels.allSatisfy({ isValidLabel(String($0)) }) else { return false }
        return Self.localSuffixes.contains { trimmed.hasSuffix("." + $0) }
    }

    private func isPublicHostname(_ host: String) -> Bool {
        let trimmed = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = trimmed.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2, labels.allSatisfy(isValidLabel), let tld = labels.last else { return false }
        return topLevelDomains.contains(tld) || tld.hasPrefix("xn--")
    }

    private func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 63, !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            scalar == "-" || (scalar.isASCII ? CharacterSet.alphanumerics.contains(scalar) : CharacterSet.letters.contains(scalar))
        }
    }

    private static func makeURL(_ string: String) -> URL? {
        if let url = URL(string: string), url.scheme != nil { return url }
        let allowed = CharacterSet.urlFragmentAllowed.union(.urlPathAllowed).union(.urlQueryAllowed).union(CharacterSet(charactersIn: "#%"))
        guard let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: encoded)
    }
}

/// The IANA root zone, bundled as a resource.
public enum TopLevelDomains {
    public static let all: Set<String> = {
        guard let url = Bundle.module.url(forResource: "top-level-domains", withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Set(
            contents
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") },
        )
    }()
}
