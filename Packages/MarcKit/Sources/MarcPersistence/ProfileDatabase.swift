import Foundation
import GRDB

/// Browsing data of a single profile: history (with full-text search), downloads, site
/// permissions and per-site settings. Each profile has its own file so that deleting a profile
/// removes all of its data.
public struct ProfileDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func open(at url: URL) throws -> ProfileDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ProfileDatabase(DatabasePool(path: url.path(percentEncoded: false), configuration: .marc))
    }

    public static func inMemory() throws -> ProfileDatabase {
        try ProfileDatabase(DatabaseQueue(configuration: .marc))
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "page") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("url", .text).notNull().unique()
                t.column("host", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("visitCount", .integer).notNull()
                t.column("typedCount", .integer).notNull()
                t.column("lastVisitedAt", .datetime).notNull().indexed()
            }
            try db.create(virtualTable: "page_fts", using: FTS5()) { t in
                t.synchronize(withTable: "page")
                t.tokenizer = .unicode61()
                t.column("title")
                t.column("url")
            }
            try db.create(table: "visit") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("page", onDelete: .cascade).notNull()
                t.column("visitedAt", .datetime).notNull().indexed()
                t.column("transition", .integer).notNull()
            }
            try db.create(table: "download") { t in
                t.primaryKey("id", .blob)
                t.column("payload", .jsonText).notNull()
                t.column("startedAt", .datetime).notNull().indexed()
            }
            try db.create(table: "sitePermission") { t in
                t.column("host", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("decision", .text).notNull()
                t.primaryKey(["host", "kind"])
            }
            try db.create(table: "siteSettings") { t in
                t.primaryKey("host", .text)
                t.column("payload", .jsonText).notNull()
            }
        }
        return migrator
    }
}
