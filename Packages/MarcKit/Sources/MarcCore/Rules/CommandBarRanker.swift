import Foundation

/// An action the Command Bar can run, such as "Toggle Sidebar".
public struct CommandDescriptor: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let keywords: [String]
    public let symbol: String
    public let shortcut: String?

    public init(id: String, title: String, keywords: [String] = [], symbol: String, shortcut: String? = nil) {
        self.id = id
        self.title = title
        self.keywords = keywords
        self.symbol = symbol
        self.shortcut = shortcut
    }
}

/// An open tab offered as a "Switch to tab" result.
public struct TabCandidate: Hashable, Sendable {
    public let itemID: SidebarItem.ID
    public let spaceID: Space.ID?
    public let title: String
    public let url: URL?
    public let faviconURL: URL?

    public init(itemID: SidebarItem.ID, spaceID: Space.ID?, title: String, url: URL?, faviconURL: URL?) {
        self.itemID = itemID
        self.spaceID = spaceID
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
    }
}

public enum CommandBarResult: Hashable, Sendable, Identifiable {
    case navigate(URL)
    case search(String, SearchEngine)
    case suggestion(String, SearchEngine)
    case tab(TabCandidate)
    case history(HistoryPage)
    case command(CommandDescriptor)
    /// "Press Tab to search <site>".
    case searchSite(SearchEngine)

    public var id: String {
        switch self {
        case let .navigate(url): "navigate:\(url.absoluteString)"
        case let .search(query, engine): "search:\(engine.id):\(query)"
        case let .suggestion(text, engine): "suggestion:\(engine.id):\(text)"
        case let .tab(tab): "tab:\(tab.itemID)"
        case let .history(page): "history:\(page.url.absoluteString)"
        case let .command(command): "command:\(command.id)"
        case let .searchSite(engine): "site:\(engine.id)"
        }
    }
}

/// Builds and orders Command Bar results. Pure: all data is passed in.
public struct CommandBarRanker: Sendable {
    public struct Limits: Sendable {
        public var tabs = 3
        public var commands = 3
        public var history = 5
        public var suggestions = 4

        public init() {}
    }

    private let classifier: URLInputClassifier
    private let limits: Limits

    public init(classifier: URLInputClassifier = URLInputClassifier(), limits: Limits = Limits()) {
        self.classifier = classifier
        self.limits = limits
    }

    public func results(
        for query: String,
        engine: SearchEngine,
        siteSearches: [SearchEngine] = SearchEngine.siteSearches + SearchEngine.builtIn,
        tabs: [TabCandidate],
        history: [HistoryPage],
        suggestions: [String],
        commands: [CommandDescriptor],
        now: Date,
    ) -> [CommandBarResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return history
                .sorted { Frecency.score($0, now: now) > Frecency.score($1, now: now) }
                .prefix(limits.history)
                .map(CommandBarResult.history)
        }

        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        var results: [CommandBarResult] = []

        let rankedHistory = history
            .compactMap { page -> (HistoryPage, Double)? in
                guard let match = Self.score(tokens: tokens, title: page.title, url: page.url) else { return nil }
                return (page, match + Frecency.score(page, now: now))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        // Inline-autocomplete behavior: a frequently visited host that starts with the query wins.
        if tokens.count == 1, trimmed.count >= 2,
           let top = rankedHistory.first,
           top.url.displayHost?.lowercased().hasPrefix(tokens[0]) == true {
            results.append(.history(top))
        }

        switch classifier.classify(trimmed) {
        case let .url(url): results.append(.navigate(url))
        case let .search(text): results.append(.search(text, engine))
        case nil: break
        }

        if let site = siteSearches.first(where: { Self.matchesKeyword($0, query: tokens[0]) }), tokens.count == 1 {
            results.append(.searchSite(site))
        }

        let openTabURLs = Set(tabs.compactMap(\.url))
        let matchingTabs = tabs
            .compactMap { tab in Self.score(tokens: tokens, title: tab.title, url: tab.url).map { (tab, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limits.tabs)
            .map { CommandBarResult.tab($0.0) }
        results.append(contentsOf: matchingTabs)

        let matchingCommands = commands
            .compactMap { command in Self.score(tokens: tokens, command: command).map { (command, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limits.commands)
            .map { CommandBarResult.command($0.0) }
        results.append(contentsOf: matchingCommands)

        let historyResults = rankedHistory
            .filter { !openTabURLs.contains($0.url) }
            .prefix(limits.history)
            .map(CommandBarResult.history)
        results.append(contentsOf: historyResults)

        let suggestionResults = suggestions
            .filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
            .prefix(limits.suggestions)
            .map { CommandBarResult.suggestion($0, engine) }
        results.append(contentsOf: suggestionResults)

        var seen = Set<String>()
        return results.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Scoring

    static func score(tokens: [String], title: String, url: URL?) -> Double? {
        let lowercasedTitle = title.lowercased()
        let titleWords = lowercasedTitle.split { !$0.isLetter && !$0.isNumber }
        let host = url?.displayHost?.lowercased() ?? ""
        let urlText = url?.displayString.lowercased() ?? ""
        var total = 0.0
        for (index, token) in tokens.enumerated() {
            if index == 0, host.hasPrefix(token) {
                total += 40
            } else if titleWords.contains(where: { $0.hasPrefix(token) }) {
                total += 20
            } else if urlText.contains(token) {
                total += 12
            } else if lowercasedTitle.contains(token) {
                total += 8
            } else {
                return nil
            }
        }
        return total
    }

    static func score(tokens: [String], command: CommandDescriptor) -> Double? {
        let words = (command.title.lowercased().split(separator: " ") + command.keywords.map { Substring($0.lowercased()) })
        var total = 0.0
        for token in tokens {
            if words.contains(where: { $0.hasPrefix(token) }) {
                total += 20
            } else if command.title.lowercased().contains(token) {
                total += 8
            } else {
                return nil
            }
        }
        return total
    }

    static func matchesKeyword(_ engine: SearchEngine, query: String) -> Bool {
        guard let keyword = engine.keyword?.lowercased(), query.count >= 3 else { return false }
        let name = keyword.split(separator: ".").first.map(String.init) ?? keyword
        return keyword.hasPrefix(query) || name.hasPrefix(query)
    }
}

/// Frequency weighted by recency, in the spirit of Firefox's frecency.
public enum Frecency {
    public static func score(_ page: HistoryPage, now: Date) -> Double {
        let age = now.timeIntervalSince(page.lastVisitedAt) / 86400
        let recencyWeight: Double = switch age {
        case ..<4: 100
        case ..<14: 70
        case ..<31: 50
        case ..<90: 30
        default: 10
        }
        let weightedVisits = Double(page.visitCount) + 2 * Double(page.typedCount)
        return weightedVisits * recencyWeight / 100
    }
}
