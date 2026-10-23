import Foundation

/// A rich-text note that lives in the sidebar like a tab.
public struct Note: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<Note>

    public let id: ID
    public var title: String
    /// RTFD-encoded attributed text.
    public var content: Data
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: ID = ID(), title: String = "", content: Data = Data(), createdAt: Date = .now, updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var displayTitle: String {
        title.isEmpty ? "Untitled Note" : title
    }
}
