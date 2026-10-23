import Foundation

/// A search provider described by OpenSearch-style URL templates.
public struct SearchEngine: Identifiable, Hashable, Sendable, Codable {
    public static let placeholder = "{searchTerms}"

    public let id: String
    public var name: String
    /// URL template containing `{searchTerms}`.
    public var searchTemplate: String
    /// Template returning OpenSearch suggestion JSON (`[query, [suggestion, …]]`).
    public var suggestionsTemplate: String?
    /// Host that triggers "press Tab to search" in the Command Bar.
    public var keyword: String?

    public init(id: String, name: String, searchTemplate: String, suggestionsTemplate: String? = nil, keyword: String? = nil) {
        self.id = id
        self.name = name
        self.searchTemplate = searchTemplate
        self.suggestionsTemplate = suggestionsTemplate
        self.keyword = keyword
    }

    public func searchURL(for query: String) -> URL? {
        Self.expand(searchTemplate, with: query)
    }

    public func suggestionsURL(for query: String) -> URL? {
        suggestionsTemplate.flatMap { Self.expand($0, with: query) }
    }

    /// Characters allowed unescaped inside a query value.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=#?/;:@$,")
        return set
    }()

    private static func expand(_ template: String, with query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              template.contains(placeholder),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: queryValueAllowed)
        else { return nil }
        return URL(string: template.replacingOccurrences(of: placeholder, with: encoded))
    }
}

public extension SearchEngine {
    static let google = SearchEngine(
        id: "google",
        name: "Google",
        searchTemplate: "https://www.google.com/search?q={searchTerms}",
        suggestionsTemplate: "https://suggestqueries.google.com/complete/search?client=firefox&q={searchTerms}",
        keyword: "google.com",
    )

    static let duckDuckGo = SearchEngine(
        id: "duckduckgo",
        name: "DuckDuckGo",
        searchTemplate: "https://duckduckgo.com/?q={searchTerms}",
        suggestionsTemplate: "https://duckduckgo.com/ac/?q={searchTerms}&type=list",
        keyword: "duckduckgo.com",
    )

    static let bing = SearchEngine(
        id: "bing",
        name: "Bing",
        searchTemplate: "https://www.bing.com/search?q={searchTerms}",
        suggestionsTemplate: "https://api.bing.com/osjson.aspx?query={searchTerms}",
        keyword: "bing.com",
    )

    static let kagi = SearchEngine(
        id: "kagi",
        name: "Kagi",
        searchTemplate: "https://kagi.com/search?q={searchTerms}",
        suggestionsTemplate: "https://kagi.com/api/autosuggest?q={searchTerms}",
        keyword: "kagi.com",
    )

    static let ecosia = SearchEngine(
        id: "ecosia",
        name: "Ecosia",
        searchTemplate: "https://www.ecosia.org/search?q={searchTerms}",
        suggestionsTemplate: "https://ac.ecosia.org/autocomplete?q={searchTerms}&type=list",
        keyword: "ecosia.org",
    )

    static let yandex = SearchEngine(
        id: "yandex",
        name: "Yandex",
        searchTemplate: "https://yandex.com/search/?text={searchTerms}",
        suggestionsTemplate: "https://suggest.yandex.com/suggest-ff.cgi?part={searchTerms}",
        keyword: "yandex.com",
    )

    /// Engines offered as the default search engine.
    static let builtIn: [SearchEngine] = [.google, .duckDuckGo, .bing, .kagi, .ecosia, .yandex]

    /// Sites that support "press Tab to search" in addition to the built-in engines.
    static let siteSearches: [SearchEngine] = [
        SearchEngine(
            id: "youtube",
            name: "YouTube",
            searchTemplate: "https://www.youtube.com/results?search_query={searchTerms}",
            keyword: "youtube.com",
        ),
        SearchEngine(
            id: "wikipedia",
            name: "Wikipedia",
            searchTemplate: "https://en.wikipedia.org/w/index.php?search={searchTerms}",
            keyword: "wikipedia.org",
        ),
        SearchEngine(id: "github", name: "GitHub", searchTemplate: "https://github.com/search?q={searchTerms}", keyword: "github.com"),
        SearchEngine(
            id: "maps",
            name: "Google Maps",
            searchTemplate: "https://www.google.com/maps/search/{searchTerms}",
            keyword: "maps.google.com",
        ),
        SearchEngine(
            id: "stackoverflow",
            name: "Stack Overflow",
            searchTemplate: "https://stackoverflow.com/search?q={searchTerms}",
            keyword: "stackoverflow.com",
        ),
        SearchEngine(
            id: "apple-developer",
            name: "Apple Developer",
            searchTemplate: "https://developer.apple.com/search/?q={searchTerms}",
            keyword: "developer.apple.com",
        ),
    ]

    static func builtIn(id: String) -> SearchEngine {
        builtIn.first { $0.id == id } ?? .google
    }
}
