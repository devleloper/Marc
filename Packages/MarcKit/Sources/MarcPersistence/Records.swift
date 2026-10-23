import Foundation
import GRDB
import MarcCore

// Database records are infrastructure DTOs; they map explicitly to and from domain values.

/// Stores dates as `timeIntervalSinceReferenceDate` and JSON payloads with Foundation's default
/// date coding, so that values round-trip exactly. GRDB's defaults keep millisecond precision,
/// which would make reloaded values compare unequal to the ones that were saved.
protocol LosslessRecord: EncodableRecord, FetchableRecord {}

extension LosslessRecord {
    static func databaseDateEncodingStrategy(for column: String) -> DatabaseDateEncodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    static func databaseDateDecodingStrategy(for column: String) -> DatabaseDateDecodingStrategy {
        .timeIntervalSinceReferenceDate
    }

    static func databaseJSONEncoder(for column: String) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    static func databaseJSONDecoder(for column: String) -> JSONDecoder {
        JSONDecoder()
    }
}

struct ProfileRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "profile"

    var id: UUID
    var name: String
    var symbol: String
    var dataStoreID: UUID
    var createdAt: Date
    var sortKey: Double

    init(_ profile: Profile) {
        id = profile.id.rawValue
        name = profile.name
        symbol = profile.symbol
        dataStoreID = profile.dataStoreID
        createdAt = profile.createdAt
        sortKey = profile.sortKey
    }

    var domain: Profile {
        Profile(id: Profile.ID(id), name: name, symbol: symbol, dataStoreID: dataStoreID, createdAt: createdAt, sortKey: sortKey)
    }
}

struct SpaceRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "space"

    var id: UUID
    var profileID: UUID
    var name: String
    var icon: SpaceIcon
    var theme: Theme
    var sortKey: Double

    init(_ space: Space) {
        id = space.id.rawValue
        profileID = space.profileID.rawValue
        name = space.name
        icon = space.icon
        theme = space.theme
        sortKey = space.sortKey
    }

    var domain: Space {
        Space(id: Space.ID(id), profileID: Profile.ID(profileID), name: name, icon: icon, theme: theme, sortKey: sortKey)
    }
}

struct SidebarItemRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "sidebarItem"

    var id: UUID
    var containerKind: String
    var containerID: UUID
    var parentID: UUID?
    var sortKey: Double
    var content: SidebarItem.Content
    var createdAt: Date
    var lastActiveAt: Date

    init(_ item: SidebarItem) {
        id = item.id.rawValue
        switch item.container {
        case let .favorites(profileID):
            containerKind = "favorites"
            containerID = profileID.rawValue
        case let .pinned(spaceID):
            containerKind = "pinned"
            containerID = spaceID.rawValue
        case let .today(spaceID):
            containerKind = "today"
            containerID = spaceID.rawValue
        }
        parentID = item.parentID?.rawValue
        sortKey = item.sortKey
        content = item.content
        createdAt = item.createdAt
        lastActiveAt = item.lastActiveAt
    }

    var domain: SidebarItem? {
        let container: SidebarContainer
        switch containerKind {
        case "favorites": container = .favorites(Profile.ID(containerID))
        case "pinned": container = .pinned(Space.ID(containerID))
        case "today": container = .today(Space.ID(containerID))
        default: return nil
        }
        return SidebarItem(
            id: SidebarItem.ID(id),
            container: container,
            parentID: parentID.map(SidebarItem.ID.init),
            sortKey: sortKey,
            content: content,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt,
        )
    }
}

struct WindowSessionRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "windowSession"

    var id: UUID
    var state: WindowState
    var sortKey: Double
}

struct ArchivedTabRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "archivedTab"

    var id: UUID
    var spaceID: UUID?
    var profileID: UUID
    var title: String
    var url: String
    var faviconURL: String?
    var archivedAt: Date

    init(_ tab: ArchivedTab) {
        id = tab.id.rawValue
        spaceID = tab.spaceID?.rawValue
        profileID = tab.profileID.rawValue
        title = tab.title
        url = tab.url.absoluteString
        faviconURL = tab.faviconURL?.absoluteString
        archivedAt = tab.archivedAt
    }

    var domain: ArchivedTab? {
        guard let url = URL(string: url) else { return nil }
        return ArchivedTab(
            id: ArchivedTab.ID(id),
            spaceID: spaceID.map(Space.ID.init),
            profileID: Profile.ID(profileID),
            title: title,
            url: url,
            faviconURL: faviconURL.flatMap(URL.init(string:)),
            archivedAt: archivedAt,
        )
    }
}

struct BoostRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "boost"

    var id: UUID
    var hostPattern: String
    var payload: Boost
    var updatedAt: Date

    init(_ boost: Boost) {
        id = boost.id.rawValue
        hostPattern = boost.hostPattern
        payload = boost
        updatedAt = boost.updatedAt
    }
}

struct NoteRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "note"

    var id: UUID
    var title: String
    var content: Data
    var createdAt: Date
    var updatedAt: Date

    init(_ note: Note) {
        id = note.id.rawValue
        title = note.title
        content = note.content
        createdAt = note.createdAt
        updatedAt = note.updatedAt
    }

    var domain: Note {
        Note(id: Note.ID(id), title: title, content: content, createdAt: createdAt, updatedAt: updatedAt)
    }
}

// MARK: - Profile database

struct PageRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "page"

    var id: Int64?
    var url: String
    var host: String
    var title: String
    var visitCount: Int
    var typedCount: Int
    var lastVisitedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var domain: HistoryPage? {
        URL(string: url).map { HistoryPage(
            url: $0,
            title: title,
            visitCount: visitCount,
            typedCount: typedCount,
            lastVisitedAt: lastVisitedAt,
        ) }
    }
}

struct VisitRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "visit"

    var id: Int64?
    var pageId: Int64
    var visitedAt: Date
    var transition: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DownloadRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "download"

    var id: UUID
    var payload: Download
    var startedAt: Date

    init(_ download: Download) {
        id = download.id.rawValue
        payload = download
        startedAt = download.startedAt
    }
}

struct SitePermissionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sitePermission"

    var host: String
    var kind: String
    var decision: String

    var domain: SitePermission? {
        guard let kind = SitePermissionKind(rawValue: kind), let decision = PermissionDecision(rawValue: decision) else { return nil }
        return SitePermission(host: host, kind: kind, decision: decision)
    }
}

struct SiteSettingsRecord: Codable, FetchableRecord, PersistableRecord, LosslessRecord {
    static let databaseTableName = "siteSettings"

    var host: String
    var payload: SiteSettings
}
