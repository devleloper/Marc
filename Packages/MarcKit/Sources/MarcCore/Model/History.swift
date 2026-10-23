import Foundation

/// A single visit to a URL.
public struct HistoryVisit: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let url: URL
    public let title: String
    public let visitedAt: Date

    public init(id: Int64, url: URL, title: String, visitedAt: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }
}

/// Aggregated history for one URL, used for ranking suggestions.
public struct HistoryPage: Hashable, Sendable {
    public let url: URL
    public let title: String
    public let visitCount: Int
    public let typedCount: Int
    public let lastVisitedAt: Date

    public init(url: URL, title: String, visitCount: Int, typedCount: Int, lastVisitedAt: Date) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.typedCount = typedCount
        self.lastVisitedAt = lastVisitedAt
    }
}

/// How a visit was initiated; typed visits weigh more in suggestions.
public enum VisitTransition: Int, Hashable, Sendable, Codable {
    case link = 0
    case typed = 1
    case reload = 2
    case restored = 3
}
