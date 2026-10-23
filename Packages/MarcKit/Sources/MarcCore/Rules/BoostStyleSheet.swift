import Foundation

public extension Boost {
    /// Whether the boost applies to `host`. `*.example.com` matches the domain and its subdomains.
    func matches(host: String) -> Bool {
        let host = host.lowercased()
        let pattern = hostPattern.lowercased().trimmingCharacters(in: .whitespaces)
        if pattern.hasPrefix("*.") {
            let domain = String(pattern.dropFirst(2))
            return host == domain || host.hasSuffix("." + domain)
        }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let barePattern = pattern.hasPrefix("www.") ? String(pattern.dropFirst(4)) : pattern
        return bareHost == barePattern
    }

    /// The CSS injected for this boost.
    var styleSheet: String {
        var rules: [String] = []
        let filters = style.cssFilters
        if !filters.isEmpty {
            rules.append("html { filter: \(filters.joined(separator: " ")) !important; }")
            if style.invertsColors {
                rules.append("img, video, picture, canvas, iframe, svg image { filter: invert(1) hue-rotate(180deg) !important; }")
            }
        }
        if let family = style.fontFamily?.trimmingCharacters(in: .whitespaces), !family.isEmpty, Self.isSafeCSSValue(family) {
            let selector = "body, body *:not(code):not(pre):not(kbd):not(samp):not(i):not([class*=\"icon\"]):not([class*=\"Icon\"])"
            rules.append("\(selector) { font-family: \"\(family)\", system-ui, sans-serif !important; }")
        }
        if abs(style.fontScale - 1) > 0.001 {
            rules.append("html { font-size: \(Int((style.fontScale * 100).rounded()))% !important; }")
        }
        let selectors = zappedSelectors.filter(Self.isSafeSelector)
        if !selectors.isEmpty {
            rules.append("\(selectors.joined(separator: ",\n")) { display: none !important; }")
        }
        if !customCSS.isEmpty {
            rules.append(customCSS)
        }
        return rules.joined(separator: "\n")
    }

    /// Selectors must not be able to close the rule they are placed in.
    static func isSafeSelector(_ selector: String) -> Bool {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains { "{};<>".contains($0) } && !trimmed.contains("/*")
    }

    static func isSafeCSSValue(_ value: String) -> Bool {
        !value.contains { "{};\"\\<>".contains($0) }
    }
}

extension Boost.Style {
    var cssFilters: [String] {
        var filters: [String] = []
        if invertsColors { filters.append("invert(1) hue-rotate(180deg)") }
        if let hueRotation, abs(hueRotation) > 0.5 { filters.append("hue-rotate(\(Int(hueRotation.rounded()))deg)") }
        if abs(saturation - 1) > 0.01 { filters.append(String(format: "saturate(%.2f)", saturation)) }
        if abs(brightness - 1) > 0.01 { filters.append(String(format: "brightness(%.2f)", brightness)) }
        return filters
    }
}
