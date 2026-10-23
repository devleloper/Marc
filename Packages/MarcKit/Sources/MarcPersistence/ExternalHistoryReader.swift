import Foundation
import GRDB
import MarcCore

/// Reads browsing history from other browsers' SQLite files. The files are copied first so that
/// a running browser holding a lock does not interfere, and opened read-only.
public enum ExternalHistoryReader {
    /// Chrome stores times as microseconds since 1601-01-01.
    static let chromeEpochOffset: TimeInterval = 11_644_473_600

    public static func chromeHistory(databaseAt url: URL, limit: Int = 50000) throws -> [ImportedHistoryEntry] {
        try withCopy(of: url) { db in
            let rows = try Row.fetchAll(db, sql: """
            SELECT url, title, visit_count, typed_count, last_visit_time FROM urls
            WHERE hidden = 0 AND last_visit_time > 0
            ORDER BY last_visit_time DESC LIMIT ?
            """, arguments: [limit])
            return rows.compactMap { row -> ImportedHistoryEntry? in
                guard let string: String = row["url"], let url = URL.importable(string) else { return nil }
                let microseconds: Int64 = row["last_visit_time"]
                return ImportedHistoryEntry(
                    url: url,
                    title: row["title"] ?? "",
                    lastVisitedAt: Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - chromeEpochOffset),
                    visitCount: row["visit_count"] ?? 1,
                    typedCount: row["typed_count"] ?? 0,
                )
            }
        }
    }

    /// Safari stores times as seconds since 2001-01-01.
    public static func safariHistory(databaseAt url: URL, limit: Int = 50000) throws -> [ImportedHistoryEntry] {
        try withCopy(of: url) { db in
            let rows = try Row.fetchAll(db, sql: """
            SELECT items.url AS url, items.visit_count AS visit_count,
                   MAX(visits.visit_time) AS last_visit, visits.title AS title
            FROM history_items items JOIN history_visits visits ON visits.history_item = items.id
            GROUP BY items.id ORDER BY last_visit DESC LIMIT ?
            """, arguments: [limit])
            return rows.compactMap { row -> ImportedHistoryEntry? in
                guard let string: String = row["url"], let url = URL.importable(string) else { return nil }
                let seconds: Double = row["last_visit"]
                return ImportedHistoryEntry(
                    url: url,
                    title: row["title"] ?? "",
                    lastVisitedAt: Date(timeIntervalSinceReferenceDate: seconds),
                    visitCount: row["visit_count"] ?? 1,
                )
            }
        }
    }

    private static func withCopy<T>(of url: URL, _ read: (Database) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appending(path: "MarcImport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let copy = directory.appending(path: "History.sqlite")
        try fileManager.copyItem(at: url, to: copy)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(filePath: url.path(percentEncoded: false) + suffix)
            if fileManager.fileExists(atPath: sidecar.path(percentEncoded: false)) {
                try fileManager.copyItem(at: sidecar, to: URL(filePath: copy.path(percentEncoded: false) + suffix))
            }
        }

        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: copy.path(percentEncoded: false), configuration: configuration)
        do {
            return try queue.read(read)
        } catch {
            throw BrowserImportError.unreadableFormat
        }
    }
}
