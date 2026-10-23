import Foundation
import GRDB
import MarcCore
import Testing
@testable import MarcPersistence

struct HistoryRepositoryTests {
    let repository: GRDBHistoryRepository
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        repository = try GRDBHistoryRepository(database: ProfileDatabase.inMemory())
    }

    func url(_ string: String) -> URL { URL(string: string)! }

    @Test func `aggregates visits per page`() async throws {
        try await repository.recordVisit(url: url("https://swift.org/"), title: "Swift", transition: .typed, at: base)
        try await repository.recordVisit(
            url: url("https://swift.org/"),
            title: "Swift.org",
            transition: .link,
            at: base.addingTimeInterval(60),
        )
        try await repository.recordVisit(url: url("https://swift.org/"), title: "", transition: .reload, at: base.addingTimeInterval(120))

        let pages = try await repository.searchPages(matching: "", limit: 10)
        #expect(pages.count == 1)
        #expect(pages[0].visitCount == 2)
        #expect(pages[0].typedCount == 1)
        #expect(pages[0].title == "Swift.org")
        #expect(pages[0].lastVisitedAt == base.addingTimeInterval(60))
    }

    @Test func `ignores non web URLs`() async throws {
        try await repository.recordVisit(url: url("about:blank"), title: "", transition: .link, at: base)
        try await repository.recordVisit(url: URL(fileURLWithPath: "/tmp/a.html"), title: "", transition: .link, at: base)
        #expect(try await repository.searchPages(matching: "", limit: 10).isEmpty)
    }

    @Test func `full text search matches prefixes in title and url`() async throws {
        try await repository.recordVisit(
            url: url("https://developer.apple.com/documentation/webkit"),
            title: "WebKit Documentation",
            transition: .link,
            at: base,
        )
        try await repository.recordVisit(url: url("https://news.ycombinator.com/"), title: "Hacker News", transition: .link, at: base)

        #expect(try await repository.searchPages(matching: "webk doc", limit: 10).map(\.title) == ["WebKit Documentation"])
        #expect(try await repository.searchPages(matching: "ycomb", limit: 10).map(\.title) == ["Hacker News"])
        #expect(try await repository.searchPages(matching: "nothing", limit: 10).isEmpty)
    }

    @Test func `title updates are searchable`() async throws {
        try await repository.recordVisit(url: url("https://a.com/"), title: "", transition: .link, at: base)
        try await repository.updateTitle("Renamed Page", for: url("https://a.com/"))
        #expect(try await repository.searchPages(matching: "renamed", limit: 10).count == 1)
    }

    @Test func `deleting visits reconciles pages`() async throws {
        try await repository.recordVisit(url: url("https://a.com/"), title: "A", transition: .link, at: base)
        try await repository.recordVisit(url: url("https://a.com/"), title: "A", transition: .link, at: base.addingTimeInterval(3600))
        try await repository.recordVisit(url: url("https://b.com/"), title: "B", transition: .link, at: base.addingTimeInterval(7200))

        let visits = try await repository.visits(matching: nil, before: nil, limit: 10)
        #expect(visits.map(\.title) == ["B", "A", "A"])

        try await repository.deleteVisits([visits[1].id])
        let pages = try await repository.searchPages(matching: "", limit: 10)
        #expect(pages.first { $0.title == "A" }?.visitCount == 1)
        #expect(pages.first { $0.title == "A" }?.lastVisitedAt == base)

        try await repository.deleteVisits(in: DateInterval(start: base.addingTimeInterval(7000), duration: 1000))
        #expect(try await repository.searchPages(matching: "", limit: 10).map(\.title) == ["A"])

        try await repository.deleteAll()
        #expect(try await repository.visits(matching: nil, before: nil, limit: 10).isEmpty)
    }

    @Test func `visit queries filter by text and date`() async throws {
        try await repository.recordVisit(url: url("https://a.com/"), title: "Alpha", transition: .link, at: base)
        try await repository.recordVisit(url: url("https://b.com/"), title: "Beta", transition: .link, at: base.addingTimeInterval(100))
        #expect(try await repository.visits(matching: "alp", before: nil, limit: 10).map(\.title) == ["Alpha"])
        #expect(try await repository.visits(matching: nil, before: base.addingTimeInterval(50), limit: 10).map(\.title) == ["Alpha"])
    }

    @Test func `imports merge without duplicating`() async throws {
        let entry = ImportedHistoryEntry(
            url: url("https://imported.com/"),
            title: "Imported",
            lastVisitedAt: base,
            visitCount: 5,
            typedCount: 2,
        )
        try await repository.importPages([entry, ImportedHistoryEntry(url: url("javascript:void(0)"), title: "x", lastVisitedAt: base)])
        try await repository.importPages([entry])
        let pages = try await repository.searchPages(matching: "imported", limit: 10)
        #expect(pages.count == 1)
        #expect(pages[0].visitCount == 5)
        #expect(pages[0].typedCount == 2)
    }
}

struct SiteAndDownloadRepositoryTests {
    @Test func `permissions are remembered per host and kind`() async throws {
        let repository = try GRDBSiteDataRepository(database: ProfileDatabase.inMemory())
        try await repository.setPermission(.allow, for: "Meet.Example.com", kind: .camera)
        try await repository.setPermission(.deny, for: "meet.example.com", kind: .microphone)
        #expect(try await repository.permission(for: "meet.example.com", kind: .camera) == .allow)
        #expect(try await repository.permissions(for: "meet.example.com").count == 2)

        try await repository.setPermission(nil, for: "meet.example.com", kind: .camera)
        #expect(try await repository.permission(for: "meet.example.com", kind: .camera) == nil)

        try await repository.saveSettings(SiteSettings(host: "meet.example.com", zoom: 1.25))
        #expect(try await repository.settings(for: "meet.example.com")?.zoom == 1.25)
        try await repository.saveSettings(SiteSettings(host: "meet.example.com"))
        #expect(try await repository.settings(for: "meet.example.com") == nil, "Empty settings are removed")

        try await repository.saveSettings(SiteSettings(host: "meet.example.com", isContentBlockingEnabled: false))
        try await repository.removeAll(for: "meet.example.com")
        #expect(try await repository.allPermissions().isEmpty)
        #expect(try await repository.allSettings().isEmpty)
    }

    @Test func `downloads upsert and clear finished`() async throws {
        let repository = try GRDBDownloadRepository(database: ProfileDatabase.inMemory())
        var download = Download(sourceURL: URL(string: "https://example.com/file.zip"), fileName: "file.zip")
        try await repository.upsert(download)
        download.state = .inProgress(receivedBytes: 50, expectedBytes: 100)
        try await repository.upsert(download)
        #expect(try await repository.downloads(limit: 10) == [download])

        let finished = Download(sourceURL: nil, fileName: "done.pdf", state: .finished, startedAt: .distantPast)
        try await repository.upsert(finished)
        try await repository.removeFinished()
        #expect(try await repository.downloads(limit: 10).map(\.id) == [download.id])
    }
}

struct ExternalHistoryReaderTests {
    func temporaryDatabase(_ setup: (Database) throws -> Void) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
        let queue = try DatabaseQueue(path: url.path(percentEncoded: false))
        try queue.write(setup)
        try queue.close()
        return url
    }

    @Test func `reads chrome history`() throws {
        let microseconds = Int64((1_800_000_000 + ExternalHistoryReader.chromeEpochOffset) * 1_000_000)
        let url = try temporaryDatabase { db in
            try db
                .execute(
                    sql: """
                    CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER,
                    typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER)
                    """,
                )
            try db.execute(sql: "INSERT INTO urls VALUES (1, 'https://swift.org/', 'Swift', 4, 1, ?, 0)", arguments: [microseconds])
            try db.execute(sql: "INSERT INTO urls VALUES (2, 'chrome://settings', 'Settings', 1, 0, ?, 0)", arguments: [microseconds])
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = try ExternalHistoryReader.chromeHistory(databaseAt: url)
        #expect(entries.count == 1)
        #expect(entries[0].visitCount == 4)
        #expect(abs(entries[0].lastVisitedAt.timeIntervalSince1970 - 1_800_000_000) < 1)
    }

    @Test func `reads safari history`() throws {
        let url = try temporaryDatabase { db in
            try db.execute(sql: "CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER)")
            try db.execute(sql: "CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT)")
            try db.execute(sql: "INSERT INTO history_items VALUES (1, 'https://webkit.org/', 3)")
            try db.execute(sql: "INSERT INTO history_visits VALUES (1, 1, 700000000, 'WebKit')")
            try db.execute(sql: "INSERT INTO history_visits VALUES (2, 1, 700000100, 'WebKit')")
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = try ExternalHistoryReader.safariHistory(databaseAt: url)
        #expect(entries.count == 1)
        #expect(entries[0].lastVisitedAt == Date(timeIntervalSinceReferenceDate: 700_000_100))
    }

    @Test func `unrelated files are rejected`() throws {
        let url = try temporaryDatabase { db in try db.execute(sql: "CREATE TABLE other (id INTEGER)") }
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: BrowserImportError.unreadableFormat) { try ExternalHistoryReader.chromeHistory(databaseAt: url) }
    }
}
