import Foundation

/// Snapshot loaded at launch.
public struct WorkspaceSnapshot: Sendable {
    public var workspace: Workspace
    public var windows: [WindowState]

    public init(workspace: Workspace, windows: [WindowState]) {
        self.workspace = workspace
        self.windows = windows
    }
}

public protocol WorkspaceRepository: Sendable {
    func load() async throws -> WorkspaceSnapshot
    func apply(_ changes: WorkspaceChanges) async throws
    func saveWindows(_ windows: [WindowState]) async throws
}

public protocol ArchiveRepository: Sendable {
    func add(_ tabs: [ArchivedTab]) async throws
    func archivedTabs(profileID: Profile.ID?, limit: Int) async throws -> [ArchivedTab]
    func remove(_ ids: [ArchivedTab.ID]) async throws
    func removeAll(profileID: Profile.ID?) async throws
}

/// History of one profile.
public protocol HistoryRepository: Sendable {
    func recordVisit(url: URL, title: String, transition: VisitTransition, at date: Date) async throws
    func updateTitle(_ title: String, for url: URL) async throws
    /// Merges history read from another browser.
    func importPages(_ entries: [ImportedHistoryEntry]) async throws
    /// Pages matching all words of `query` in their title or URL, ordered by recency.
    func searchPages(matching query: String, limit: Int) async throws -> [HistoryPage]
    func visits(matching query: String?, before date: Date?, limit: Int) async throws -> [HistoryVisit]
    func deleteVisits(_ ids: [Int64]) async throws
    func deleteVisits(in interval: DateInterval) async throws
    func deleteAll() async throws
}

public protocol DownloadRepository: Sendable {
    func upsert(_ download: Download) async throws
    func downloads(limit: Int) async throws -> [Download]
    func remove(_ ids: [Download.ID]) async throws
    func removeFinished() async throws
}

public protocol SiteDataRepository: Sendable {
    func permission(for host: String, kind: SitePermissionKind) async throws -> PermissionDecision?
    func setPermission(_ decision: PermissionDecision?, for host: String, kind: SitePermissionKind) async throws
    func permissions(for host: String) async throws -> [SitePermission]
    func allPermissions() async throws -> [SitePermission]
    func settings(for host: String) async throws -> SiteSettings?
    func saveSettings(_ settings: SiteSettings) async throws
    func allSettings() async throws -> [SiteSettings]
    func removeAll(for host: String) async throws
}

public protocol BoostRepository: Sendable {
    func allBoosts() async throws -> [Boost]
    func save(_ boost: Boost) async throws
    func delete(_ id: Boost.ID) async throws
}

public protocol NoteRepository: Sendable {
    func note(_ id: Note.ID) async throws -> Note?
    func allNotes() async throws -> [Note]
    func save(_ note: Note) async throws
    func delete(_ id: Note.ID) async throws
}
