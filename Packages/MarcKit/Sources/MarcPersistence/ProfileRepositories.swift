import Foundation
import GRDB
import MarcCore

public struct GRDBHistoryRepository: HistoryRepository {
    private let writer: any DatabaseWriter

    public init(database: ProfileDatabase) {
        writer = database.writer
    }

    public func recordVisit(url: URL, title: String, transition: VisitTransition, at date: Date) async throws {
        guard url.isWebURL, transition != .reload, transition != .restored else { return }
        try await writer.write { db in
            var page = try PageRecord.filter(Column("url") == url.absoluteString).fetchOne(db)
                ?? PageRecord(
                    id: nil,
                    url: url.absoluteString,
                    host: url.displayHost ?? "",
                    title: title,
                    visitCount: 0,
                    typedCount: 0,
                    lastVisitedAt: date,
                )
            page.visitCount += 1
            if transition == .typed { page.typedCount += 1 }
            page.lastVisitedAt = date
            if !title.isEmpty { page.title = title }
            try page.save(db)
            guard let pageID = page.id else { return }
            var visit = VisitRecord(id: nil, pageId: pageID, visitedAt: date, transition: transition.rawValue)
            try visit.insert(db)
        }
    }

    public func updateTitle(_ title: String, for url: URL) async throws {
        guard !title.isEmpty else { return }
        try await writer.write { db in
            try db.execute(sql: "UPDATE page SET title = ? WHERE url = ?", arguments: [title, url.absoluteString])
        }
    }

    public func importPages(_ entries: [ImportedHistoryEntry]) async throws {
        try await writer.write { db in
            for entry in entries where entry.url.isWebURL {
                if var page = try PageRecord.filter(Column("url") == entry.url.absoluteString).fetchOne(db) {
                    page.visitCount = max(page.visitCount, entry.visitCount)
                    page.typedCount = max(page.typedCount, entry.typedCount)
                    if entry.lastVisitedAt > page.lastVisitedAt {
                        page.lastVisitedAt = entry.lastVisitedAt
                        if !entry.title.isEmpty { page.title = entry.title }
                    }
                    try page.update(db)
                } else {
                    var page = PageRecord(
                        id: nil,
                        url: entry.url.absoluteString,
                        host: entry.url.displayHost ?? "",
                        title: entry.title,
                        visitCount: max(entry.visitCount, 1),
                        typedCount: entry.typedCount,
                        lastVisitedAt: entry.lastVisitedAt,
                    )
                    try page.insert(db)
                    if let pageID = page.id {
                        var visit = VisitRecord(
                            id: nil,
                            pageId: pageID,
                            visitedAt: entry.lastVisitedAt,
                            transition: VisitTransition.link.rawValue,
                        )
                        try visit.insert(db)
                    }
                }
            }
        }
    }

    public func searchPages(matching query: String, limit: Int) async throws -> [HistoryPage] {
        try await writer.read { db in
            guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else {
                return try PageRecord.order(Column("lastVisitedAt").desc).limit(limit).fetchAll(db).compactMap(\.domain)
            }
            let sql = """
            SELECT page.* FROM page
            JOIN page_fts ON page_fts.rowid = page.id
            WHERE page_fts MATCH ?
            ORDER BY page.lastVisitedAt DESC
            LIMIT ?
            """
            return try PageRecord.fetchAll(db, sql: sql, arguments: [pattern, limit]).compactMap(\.domain)
        }
    }

    public func visits(matching query: String?, before date: Date?, limit: Int) async throws -> [HistoryVisit] {
        try await writer.read { db in
            var conditions: [String] = []
            var arguments: StatementArguments = []
            if let query, let pattern = FTS5Pattern(matchingAllPrefixesIn: query) {
                conditions.append("page.id IN (SELECT rowid FROM page_fts WHERE page_fts MATCH ?)")
                _ = arguments.append(contentsOf: [pattern])
            }
            if let date {
                conditions.append("visit.visitedAt < ?")
                _ = arguments.append(contentsOf: [date])
            }
            _ = arguments.append(contentsOf: [limit])
            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = """
            SELECT visit.id AS id, page.url AS url, page.title AS title, visit.visitedAt AS visitedAt
            FROM visit JOIN page ON page.id = visit.pageId
            \(whereClause)
            ORDER BY visit.visitedAt DESC
            LIMIT ?
            """
            return try Row.fetchAll(db, sql: sql, arguments: arguments).compactMap { row in
                guard let url = URL(string: row["url"]) else { return nil }
                return HistoryVisit(id: row["id"], url: url, title: row["title"], visitedAt: row["visitedAt"])
            }
        }
    }

    public func deleteVisits(_ ids: [Int64]) async throws {
        try await writer.write { db in
            _ = try VisitRecord.deleteAll(db, keys: ids)
            try Self.reconcilePages(db)
        }
    }

    public func deleteVisits(in interval: DateInterval) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM visit WHERE visitedAt >= ? AND visitedAt <= ?", arguments: [interval.start, interval.end])
            try Self.reconcilePages(db)
        }
    }

    public func deleteAll() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM visit")
            try db.execute(sql: "DELETE FROM page")
        }
    }

    /// Keeps aggregate page data consistent with the remaining visits.
    private static func reconcilePages(_ db: Database) throws {
        try db.execute(sql: "DELETE FROM page WHERE id NOT IN (SELECT DISTINCT pageId FROM visit)")
        try db.execute(sql: """
        UPDATE page SET
            visitCount = (SELECT COUNT(*) FROM visit WHERE visit.pageId = page.id),
            typedCount = MIN(typedCount, (SELECT COUNT(*) FROM visit WHERE visit.pageId = page.id AND visit.transition = 1)),
            lastVisitedAt = (SELECT MAX(visitedAt) FROM visit WHERE visit.pageId = page.id)
        """)
    }
}

public struct GRDBDownloadRepository: DownloadRepository {
    private let writer: any DatabaseWriter

    public init(database: ProfileDatabase) {
        writer = database.writer
    }

    public func upsert(_ download: Download) async throws {
        try await writer.write { db in
            try DownloadRecord(download).upsert(db)
        }
    }

    public func downloads(limit: Int) async throws -> [Download] {
        try await writer.read { db in
            try DownloadRecord.order(Column("startedAt").desc).limit(limit).fetchAll(db).map(\.payload)
        }
    }

    public func remove(_ ids: [Download.ID]) async throws {
        try await writer.write { db in
            _ = try DownloadRecord.deleteAll(db, keys: ids.map(\.rawValue))
        }
    }

    public func removeFinished() async throws {
        try await writer.write { db in
            let finished = try DownloadRecord.fetchAll(db).filter { !$0.payload.state.isActive }.map(\.id)
            _ = try DownloadRecord.deleteAll(db, keys: finished)
        }
    }
}

public struct GRDBSiteDataRepository: SiteDataRepository {
    private let writer: any DatabaseWriter

    public init(database: ProfileDatabase) {
        writer = database.writer
    }

    public func permission(for host: String, kind: SitePermissionKind) async throws -> PermissionDecision? {
        try await writer.read { db in
            try SitePermissionRecord.fetchOne(db, key: ["host": host.lowercased(), "kind": kind.rawValue])?.domain?.decision
        }
    }

    public func setPermission(_ decision: PermissionDecision?, for host: String, kind: SitePermissionKind) async throws {
        try await writer.write { db in
            let key: [String: any DatabaseValueConvertible] = ["host": host.lowercased(), "kind": kind.rawValue]
            if let decision {
                try SitePermissionRecord(host: host.lowercased(), kind: kind.rawValue, decision: decision.rawValue).upsert(db)
            } else {
                _ = try SitePermissionRecord.deleteOne(db, key: key)
            }
        }
    }

    public func permissions(for host: String) async throws -> [SitePermission] {
        try await writer.read { db in
            try SitePermissionRecord.filter(Column("host") == host.lowercased()).fetchAll(db).compactMap(\.domain)
        }
    }

    public func allPermissions() async throws -> [SitePermission] {
        try await writer.read { db in
            try SitePermissionRecord.order(Column("host")).fetchAll(db).compactMap(\.domain)
        }
    }

    public func settings(for host: String) async throws -> SiteSettings? {
        try await writer.read { db in
            try SiteSettingsRecord.fetchOne(db, key: host.lowercased())?.payload
        }
    }

    public func saveSettings(_ settings: SiteSettings) async throws {
        try await writer.write { db in
            let host = settings.host.lowercased()
            if settings.zoom == nil, settings.isContentBlockingEnabled == nil {
                _ = try SiteSettingsRecord.deleteOne(db, key: host)
            } else {
                try SiteSettingsRecord(host: host, payload: settings).upsert(db)
            }
        }
    }

    public func allSettings() async throws -> [SiteSettings] {
        try await writer.read { db in
            try SiteSettingsRecord.order(Column("host")).fetchAll(db).map(\.payload)
        }
    }

    public func removeAll(for host: String) async throws {
        try await writer.write { db in
            let host = host.lowercased()
            _ = try SitePermissionRecord.filter(Column("host") == host).deleteAll(db)
            _ = try SiteSettingsRecord.deleteOne(db, key: host)
        }
    }
}
