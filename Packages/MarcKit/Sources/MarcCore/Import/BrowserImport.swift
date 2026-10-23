import Foundation

/// Data read from another browser, independent of where it came from.
public struct BrowserImport: Hashable, Sendable {
    public var source: Source
    public var spaces: [ImportedSpace]
    /// Favorites keyed by the source profile they belong to.
    public var favorites: [ImportedProfileKey: [ImportedLink]]
    /// Plain bookmark trees (Chrome, Safari, HTML files) imported into one pinned folder.
    public var bookmarks: [ImportedNode]
    public var history: [ImportedHistoryEntry]

    public init(
        source: Source,
        spaces: [ImportedSpace] = [],
        favorites: [ImportedProfileKey: [ImportedLink]] = [:],
        bookmarks: [ImportedNode] = [],
        history: [ImportedHistoryEntry] = [],
    ) {
        self.source = source
        self.spaces = spaces
        self.favorites = favorites
        self.bookmarks = bookmarks
        self.history = history
    }

    public enum Source: String, Hashable, Sendable, CaseIterable {
        case arc
        case chrome
        case safari
        case bookmarksFile

        public var displayName: String {
            switch self {
            case .arc: "Arc"
            case .chrome: "Google Chrome"
            case .safari: "Safari"
            case .bookmarksFile: "Bookmarks File"
            }
        }
    }

    public var isEmpty: Bool {
        spaces.isEmpty && favorites.values.allSatisfy(\.isEmpty) && bookmarks.isEmpty && history.isEmpty
    }
}

/// Identifies a profile in the source browser so that imported Spaces sharing a profile stay
/// together.
public enum ImportedProfileKey: Hashable, Sendable {
    case `default`
    case named(String)
}

public struct ImportedSpace: Hashable, Sendable {
    public var name: String
    public var icon: SpaceIcon?
    public var theme: Theme?
    public var profile: ImportedProfileKey
    public var pinned: [ImportedNode]
    public var today: [ImportedNode]

    public init(
        name: String,
        icon: SpaceIcon? = nil,
        theme: Theme? = nil,
        profile: ImportedProfileKey = .default,
        pinned: [ImportedNode] = [],
        today: [ImportedNode] = [],
    ) {
        self.name = name
        self.icon = icon
        self.theme = theme
        self.profile = profile
        self.pinned = pinned
        self.today = today
    }
}

public struct ImportedLink: Hashable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }
}

public indirect enum ImportedNode: Hashable, Sendable {
    case link(ImportedLink)
    case folder(name: String, children: [ImportedNode])
    case split(links: [ImportedLink], axis: SplitLayout.Axis)

    var linkCount: Int {
        switch self {
        case .link: 1
        case let .folder(_, children): children.reduce(0) { $0 + $1.linkCount }
        case let .split(links, _): links.count
        }
    }
}

public struct ImportedHistoryEntry: Hashable, Sendable {
    public var url: URL
    public var title: String
    public var lastVisitedAt: Date
    public var visitCount: Int
    public var typedCount: Int

    public init(url: URL, title: String, lastVisitedAt: Date, visitCount: Int = 1, typedCount: Int = 0) {
        self.url = url
        self.title = title
        self.lastVisitedAt = lastVisitedAt
        self.visitCount = visitCount
        self.typedCount = typedCount
    }
}

public enum BrowserImportError: Error, Equatable, Sendable {
    case unreadableFormat
    case nothingToImport
}

public extension URL {
    /// Accepts only web URLs from imported data; `javascript:` bookmarklets and local file
    /// references are dropped.
    static func importable(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.isWebURL else { return nil }
        return url
    }
}
