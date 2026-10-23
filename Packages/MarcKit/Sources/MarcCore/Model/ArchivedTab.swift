import Foundation

/// A tab that was closed or auto-archived and can be restored from the Archive.
public struct ArchivedTab: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<ArchivedTab>

    public let id: ID
    public let spaceID: Space.ID?
    public let profileID: Profile.ID
    public var title: String
    public var url: URL
    public var faviconURL: URL?
    public let archivedAt: Date

    public init(
        id: ID = ID(),
        spaceID: Space.ID?,
        profileID: Profile.ID,
        title: String,
        url: URL,
        faviconURL: URL? = nil,
        archivedAt: Date = .now,
    ) {
        self.id = id
        self.spaceID = spaceID
        self.profileID = profileID
        self.title = title
        self.url = url
        self.faviconURL = faviconURL
        self.archivedAt = archivedAt
    }
}
