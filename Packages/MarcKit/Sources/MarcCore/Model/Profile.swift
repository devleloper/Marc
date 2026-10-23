import Foundation

/// A browsing identity. Every profile owns an isolated website data store, history database,
/// password namespace and extension set.
public struct Profile: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<Profile>

    public let id: ID
    public var name: String
    public var symbol: String
    /// Identifier passed to `WKWebsiteDataStore(forIdentifier:)`.
    public let dataStoreID: UUID
    public let createdAt: Date
    public var sortKey: Double

    public init(
        id: ID = ID(),
        name: String,
        symbol: String = "person.crop.circle",
        dataStoreID: UUID = UUID(),
        createdAt: Date = .now,
        sortKey: Double = 0,
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.dataStoreID = dataStoreID
        self.createdAt = createdAt
        self.sortKey = sortKey
    }
}
