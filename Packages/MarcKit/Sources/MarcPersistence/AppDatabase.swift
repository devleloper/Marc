import Foundation
import GRDB

/// The global database: profiles, Spaces, the sidebar tree, archive, boosts, notes and window
/// sessions.
public struct AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path(percentEncoded: false), configuration: .marc))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(configuration: .marc))
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = false
        #endif

        migrator.registerMigration("v1") { db in
            try db.create(table: "profile") { t in
                t.primaryKey("id", .blob)
                t.column("name", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("dataStoreID", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("sortKey", .double).notNull()
            }
            try db.create(table: "space") { t in
                t.primaryKey("id", .blob)
                t.column("profileID", .blob).notNull().indexed()
                t.column("name", .text).notNull()
                t.column("icon", .jsonText).notNull()
                t.column("theme", .jsonText).notNull()
                t.column("sortKey", .double).notNull()
            }
            try db.create(table: "sidebarItem") { t in
                t.primaryKey("id", .blob)
                t.column("containerKind", .text).notNull()
                t.column("containerID", .blob).notNull()
                t.column("parentID", .blob)
                t.column("sortKey", .double).notNull()
                t.column("content", .jsonText).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastActiveAt", .datetime).notNull()
            }
            try db.create(index: "sidebarItem_container", on: "sidebarItem", columns: ["containerKind", "containerID"])
            try db.create(table: "windowSession") { t in
                t.primaryKey("id", .blob)
                t.column("state", .jsonText).notNull()
                t.column("sortKey", .double).notNull()
            }
            try db.create(table: "archivedTab") { t in
                t.primaryKey("id", .blob)
                t.column("spaceID", .blob)
                t.column("profileID", .blob).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("url", .text).notNull()
                t.column("faviconURL", .text)
                t.column("archivedAt", .datetime).notNull().indexed()
            }
            try db.create(table: "boost") { t in
                t.primaryKey("id", .blob)
                t.column("hostPattern", .text).notNull()
                t.column("payload", .jsonText).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "note") { t in
                t.primaryKey("id", .blob)
                t.column("title", .text).notNull()
                t.column("content", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
        return migrator
    }
}

extension Configuration {
    static var marc: Configuration {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        return configuration
    }
}
