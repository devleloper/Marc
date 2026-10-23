import Foundation

/// Converts Adblock Plus–style filter lists (EasyList, EasyPrivacy, …) into WebKit content
/// blocker JSON. Only constructs that WebKit's restricted regular-expression engine accepts are
/// emitted; anything that cannot be translated faithfully is skipped rather than approximated
/// in a way that could over-block.
public struct FilterListConverter: Sendable {
    /// WebKit rejects lists above this size.
    public static let maximumRuleCount = 150_000
    static let selectorsPerHidingRule = 64

    public struct Result: Sendable {
        public let json: String
        public let ruleCount: Int
        public let skippedLineCount: Int
    }

    public init() {}

    public func convert(_ lists: [String]) throws -> Result {
        var blocking: [ContentRule] = []
        var exceptions: [ContentRule] = []
        var genericSelectors: [String] = []
        var domainSelectors: [String: [String]] = [:]
        var skipped = 0

        for list in lists {
            for rawLine in list.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
                switch Self.parse(line) {
                case let .block(rule): blocking.append(rule)
                case let .exception(rule): exceptions.append(rule)
                case let .hide(selector, domains):
                    if domains.isEmpty {
                        genericSelectors.append(selector)
                    } else {
                        for domain in domains {
                            domainSelectors[domain, default: []].append(selector)
                        }
                    }
                case .unsupported: skipped += 1
                }
            }
        }

        var rules = blocking
        for chunk in stride(from: 0, to: genericSelectors.count, by: Self.selectorsPerHidingRule) {
            let selectors = genericSelectors[chunk ..< min(chunk + Self.selectorsPerHidingRule, genericSelectors.count)]
            rules.append(ContentRule(trigger: .init(urlFilter: ".*"), action: .hide(selectors.joined(separator: ", "))))
        }
        for (domain, selectors) in domainSelectors.sorted(by: { $0.key < $1.key }) {
            rules.append(ContentRule(
                trigger: .init(urlFilter: ".*", ifDomain: ["*" + domain]),
                action: .hide(selectors.joined(separator: ", ")),
            ))
        }
        // Exceptions must follow the rules they override.
        let capacity = Self.maximumRuleCount - min(exceptions.count, Self.maximumRuleCount)
        if rules.count > capacity {
            skipped += rules.count - capacity
            rules.removeLast(rules.count - capacity)
        }
        rules += exceptions.prefix(Self.maximumRuleCount)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = try String(bytes: encoder.encode(rules), encoding: .utf8) ?? "[]"
        return Result(json: json, ruleCount: rules.count, skippedLineCount: skipped)
    }

    // MARK: - Parsing

    enum Parsed: Equatable {
        case block(ContentRule)
        case exception(ContentRule)
        case hide(selector: String, domains: [String])
        case unsupported
    }

    static func parse(_ line: String) -> Parsed {
        if let range = line.range(of: "##") {
            return parseHiding(selector: String(line[range.upperBound...]), domains: String(line[..<range.lowerBound]))
        }
        // Exception hiding (#@#), procedural (#?#), snippets (#$#) and scriptlets are not supported.
        if line.contains("#@#") || line.contains("#?#") || line.contains("#$#") || line.contains("#%#") {
            return .unsupported
        }
        let isException = line.hasPrefix("@@")
        let body = isException ? String(line.dropFirst(2)) : line
        guard let rule = parseNetworkRule(body, isException: isException) else { return .unsupported }
        return isException ? .exception(rule) : .block(rule)
    }

    private static func parseHiding(selector: String, domains: String) -> Parsed {
        let selector = selector.trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, selector.allSatisfy(\.isASCII),
              !selector.hasPrefix("+js("), !selector.contains(":-abp-"), !selector.contains(":has-text("),
              !selector.contains(":style("), !selector.contains(":remove("), !selector.contains(":xpath("),
              !selector.contains(":matches-"), !selector.contains("{"), !selector.contains("}")
        else { return .unsupported }
        let domainList = domains.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        // Negated domains on hiding rules cannot be expressed together with a generic rule.
        if domainList.contains(where: { $0.hasPrefix("~") }) { return .unsupported }
        guard domainList.allSatisfy(isValidDomain) else { return .unsupported }
        return .hide(selector: selector, domains: domainList)
    }

    private static func parseNetworkRule(_ text: String, isException: Bool) -> ContentRule? {
        // Raw regular-expression rules (/…/) are not translated.
        guard text.allSatisfy(\.isASCII),
              !(text.hasPrefix("/") && text.count > 1 && text.dropFirst().contains("/") && text.hasSuffix("/")) else {
            return nil
        }
        var pattern = text
        var options: [String] = []
        if let dollar = text.lastIndex(of: "$"), !text[text.index(after: dollar)...].contains("/") {
            pattern = String(text[..<dollar])
            options = text[text.index(after: dollar)...]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        }
        guard var trigger = trigger(for: options), let filter = urlFilter(for: pattern) else { return nil }
        // A rule matching every URL without restrictions would break the web.
        if filter == ".*", trigger.ifDomain == nil, trigger.resourceType == nil, !isException { return nil }
        trigger.urlFilter = filter
        return ContentRule(trigger: trigger, action: isException ? .ignorePreviousRules : .block)
    }

    /// Builds a trigger from rule options, or returns `nil` when an option cannot be expressed.
    private static func trigger(for options: [String]) -> ContentRule.Trigger? {
        var trigger = ContentRule.Trigger(urlFilter: "")
        var resourceTypes: Set<String> = []
        var excludedResourceTypes: Set<String> = []
        for option in options {
            let negated = option.hasPrefix("~")
            let name = negated ? String(option.dropFirst()) : option
            switch name {
            case "third-party", "3p":
                trigger.loadType = [negated ? "first-party" : "third-party"]
            case "first-party", "1p":
                trigger.loadType = [negated ? "third-party" : "first-party"]
            case "match-case":
                trigger.urlFilterIsCaseSensitive = true
            case "important":
                continue
            case _ where name.hasPrefix("domain="):
                guard applyDomains(name.dropFirst("domain=".count), to: &trigger) else { return nil }
            default:
                guard let types = resourceTypeMapping[name] else { return nil }
                if negated { excludedResourceTypes.formUnion(types) } else { resourceTypes.formUnion(types) }
            }
        }
        if !excludedResourceTypes.isEmpty {
            let base = resourceTypes.isEmpty ? allResourceTypes : resourceTypes
            resourceTypes = base.subtracting(excludedResourceTypes)
            if resourceTypes.isEmpty { return nil }
        }
        if !resourceTypes.isEmpty { trigger.resourceType = resourceTypes.sorted() }
        return trigger
    }

    /// `a.com|~b.com`: WebKit cannot combine included and excluded domains, so included ones win.
    private static func applyDomains(_ list: Substring, to trigger: inout ContentRule.Trigger) -> Bool {
        let domains = list.split(separator: "|").map(String.init)
        let included = domains.filter { !$0.hasPrefix("~") }
        let excluded = domains.filter { $0.hasPrefix("~") }.map { String($0.dropFirst()) }
        guard (included + excluded).allSatisfy(isValidDomain) else { return false }
        if !included.isEmpty {
            trigger.ifDomain = included.map { "*" + $0 }
        } else if !excluded.isEmpty {
            trigger.unlessDomain = excluded.map { "*" + $0 }
        }
        return true
    }

    /// Translates an ABP URL pattern into WebKit's regular-expression subset.
    static func urlFilter(for pattern: String) -> String? {
        var pattern = pattern
        var prefix = ""
        var suffix = ""
        if pattern.hasPrefix("||") {
            pattern.removeFirst(2)
            prefix = "^[^:]+:(//)?([^/:]+\\.)?"
        } else if pattern.hasPrefix("|") {
            pattern.removeFirst()
            prefix = "^"
        }
        if pattern.hasSuffix("|") {
            pattern.removeLast()
            suffix = "$"
        }
        let meaningful = pattern.filter { $0 != "*" && $0 != "^" }
        guard meaningful.count >= 3 || (!prefix.isEmpty && !meaningful.isEmpty) else {
            return pattern.allSatisfy { $0 == "*" } && prefix.isEmpty ? ".*" : nil
        }

        var regex = ""
        let characters = Array(pattern)
        for (index, character) in characters.enumerated() {
            switch character {
            case "*":
                if !regex.hasSuffix(".*") { regex += ".*" }
            case "^":
                // After a domain anchor, "^" marks the end of the host.
                let isHostBoundary = !prefix.isEmpty && prefix.hasPrefix("^[^:]") && !characters[..<index].contains("/")
                regex += isHostBoundary ? "[/:]" : "[^a-zA-Z0-9_.%-]"
            case ".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "|", "$":
                regex += "\\" + String(character)
            default:
                regex.append(character)
            }
        }
        if prefix.isEmpty, regex.hasPrefix(".*") { regex.removeFirst(2) }
        if suffix.isEmpty, regex.hasSuffix(".*") { regex.removeLast(2) }
        return prefix + regex + suffix
    }

    static func isValidDomain(_ domain: String) -> Bool {
        !domain.isEmpty && domain.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") } && !domain
            .contains("*")
    }

    static let resourceTypeMapping: [String: Set<String>] = [
        "script": ["script"],
        "image": ["image"],
        "stylesheet": ["style-sheet"],
        "css": ["style-sheet"],
        "font": ["font"],
        "media": ["media"],
        "object": ["media"],
        "xmlhttprequest": ["raw"],
        "xhr": ["raw"],
        "websocket": ["raw"],
        "ping": ["raw"],
        "other": ["raw"],
        "subdocument": ["document"],
        "frame": ["document"],
        "popup": ["popup"],
    ]

    static let allResourceTypes: Set = ["document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup"]
}

/// One WebKit content-blocker rule.
struct ContentRule: Encodable, Equatable {
    struct Trigger: Encodable, Equatable {
        var urlFilter: String
        var urlFilterIsCaseSensitive: Bool?
        var ifDomain: [String]?
        var unlessDomain: [String]?
        var resourceType: [String]?
        var loadType: [String]?

        enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter"
            case urlFilterIsCaseSensitive = "url-filter-is-case-sensitive"
            case ifDomain = "if-domain"
            case unlessDomain = "unless-domain"
            case resourceType = "resource-type"
            case loadType = "load-type"
        }
    }

    enum Action: Encodable, Equatable {
        case block
        case ignorePreviousRules
        case hide(String)

        enum CodingKeys: String, CodingKey {
            case type
            case selector
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .block:
                try container.encode("block", forKey: .type)
            case .ignorePreviousRules:
                try container.encode("ignore-previous-rules", forKey: .type)
            case let .hide(selector):
                try container.encode("css-display-none", forKey: .type)
                try container.encode(selector, forKey: .selector)
            }
        }
    }

    var trigger: Trigger
    var action: Action
}
