import Foundation
import MarcCore
import MarcWebKit
@testable import MarcUI

// In-memory implementations of the ports, enough to drive the browser session in tests.

actor MemoryWorkspaceRepository: WorkspaceRepository {
    private(set) var workspace = Workspace()
    private(set) var windows: [WindowState] = []

    func load() async throws -> WorkspaceSnapshot {
        WorkspaceSnapshot(workspace: workspace, windows: windows)
    }

    func apply(_ changes: WorkspaceChanges) async throws {
        var profiles = workspace.profiles
        var spaces = workspace.spaces
        var items = workspace.items
        changes.upsertedProfiles.forEach { profiles[$0.id] = $0 }
        changes.deletedProfileIDs.forEach { profiles[$0] = nil }
        changes.upsertedSpaces.forEach { spaces[$0.id] = $0 }
        changes.deletedSpaceIDs.forEach { spaces[$0] = nil }
        changes.upsertedItems.forEach { items[$0.id] = $0 }
        changes.deletedItemIDs.forEach { items[$0] = nil }
        workspace = Workspace(profiles: Array(profiles.values), spaces: Array(spaces.values), items: Array(items.values))
    }

    func saveWindows(_ windows: [WindowState]) async throws {
        self.windows = windows
    }
}

actor MemoryArchiveRepository: ArchiveRepository {
    private(set) var tabs: [ArchivedTab] = []

    func add(_ tabs: [ArchivedTab]) async throws { self.tabs.insert(contentsOf: tabs, at: 0) }
    func archivedTabs(profileID: Profile.ID?, limit: Int) async throws -> [ArchivedTab] { Array(tabs.prefix(limit)) }
    func remove(_ ids: [ArchivedTab.ID]) async throws { tabs.removeAll { ids.contains($0.id) } }
    func removeAll(profileID: Profile.ID?) async throws { tabs.removeAll() }
}

actor MemoryNoteRepository: NoteRepository {
    private var notes: [Note.ID: Note] = [:]

    func note(_ id: Note.ID) async throws -> Note? { notes[id] }
    func allNotes() async throws -> [Note] { Array(notes.values) }
    func save(_ note: Note) async throws { notes[note.id] = note }
    func delete(_ id: Note.ID) async throws { notes[id] = nil }
}

actor MemoryBoostRepository: BoostRepository {
    private var boosts: [Boost] = []

    func allBoosts() async throws -> [Boost] { boosts }
    func save(_ boost: Boost) async throws { boosts.removeAll { $0.id == boost.id }
        boosts.append(boost)
    }

    func delete(_ id: Boost.ID) async throws { boosts.removeAll { $0.id == id } }
}

actor MemoryHistoryRepository: HistoryRepository {
    private(set) var visits: [(url: URL, title: String, transition: VisitTransition)] = []

    func recordVisit(url: URL, title: String, transition: VisitTransition, at date: Date) async throws {
        visits.append((url, title, transition))
    }

    func updateTitle(_ title: String, for url: URL) async throws {}
    func importPages(_ entries: [ImportedHistoryEntry]) async throws {}
    func searchPages(matching query: String, limit: Int) async throws -> [HistoryPage] { [] }
    func visits(matching query: String?, before date: Date?, limit: Int) async throws -> [HistoryVisit] { [] }
    func deleteVisits(_ ids: [Int64]) async throws {}
    func deleteVisits(in interval: DateInterval) async throws {}
    func deleteAll() async throws { visits.removeAll() }
}

actor MemoryDownloadRepository: DownloadRepository {
    func upsert(_ download: Download) async throws {}
    func downloads(limit: Int) async throws -> [Download] { [] }
    func remove(_ ids: [Download.ID]) async throws {}
    func removeFinished() async throws {}
}

actor MemorySiteDataRepository: SiteDataRepository {
    func permission(for host: String, kind: SitePermissionKind) async throws -> PermissionDecision? { nil }
    func setPermission(_ decision: PermissionDecision?, for host: String, kind: SitePermissionKind) async throws {}
    func permissions(for host: String) async throws -> [SitePermission] { [] }
    func allPermissions() async throws -> [SitePermission] { [] }
    func settings(for host: String) async throws -> SiteSettings? { nil }
    func saveSettings(_ settings: SiteSettings) async throws {}
    func allSettings() async throws -> [SiteSettings] { [] }
    func removeAll(for host: String) async throws {}
}

actor MemoryCredentialStore: CredentialStore {
    private var entries: [Credential.ID: (Credential, String)] = [:]

    func credentials(for origin: String) async throws -> [Credential] { entries.values.map(\.0).filter { $0.origin == origin } }
    func allCredentials() async throws -> [Credential] { entries.values.map(\.0) }
    func password(for credential: Credential) async throws -> String? { entries[credential.id]?.1 }
    func save(_ credential: Credential, password: String) async throws { entries[credential.id] = (credential, password) }
    func delete(_ credential: Credential) async throws { entries[credential.id] = nil }
    func markUsed(_ credential: Credential, at date: Date) async throws {}
}

final class MemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: BrowserSettings

    init(_ settings: BrowserSettings) {
        self.settings = settings
    }

    func load() -> BrowserSettings { lock.withLock { settings } }
    func save(_ settings: BrowserSettings) { lock.withLock { self.settings = settings } }
}

struct NoSecrets: SecretStore {
    func secret(for key: String) throws -> String? { nil }
    func setSecret(_ value: String?, for key: String) throws {}
}

struct NoSuggestions: SearchSuggestionProvider {
    func suggestions(for query: String, engine: SearchEngine) async throws -> [String] { [] }
}

struct AlwaysAuthenticated: UserAuthenticator {
    func authenticate(reason: String) async -> Bool { true }
}

@MainActor
enum TestSession {
    static func make(workspace: Workspace = .makeDefault()) async throws
        -> (BrowserSession, MemoryWorkspaceRepository, MemoryArchiveRepository) {
        let repository = MemoryWorkspaceRepository()
        try await repository.apply(WorkspaceChanges(from: Workspace(), to: workspace))
        let archive = MemoryArchiveRepository()
        var settings = BrowserSettings()
        settings.isContentBlockingEnabled = false
        settings.hasCompletedOnboarding = true
        let history = MemoryHistoryRepository()
        let profileServices = ProfileServices(
            history: history,
            downloads: MemoryDownloadRepository(),
            siteData: MemorySiteDataRepository(),
            credentials: MemoryCredentialStore(),
        )
        let services = SessionServices(
            workspaceRepository: repository,
            archive: archive,
            notes: MemoryNoteRepository(),
            boosts: MemoryBoostRepository(),
            settingsStore: MemorySettingsStore(settings),
            secrets: NoSecrets(),
            suggestions: NoSuggestions(),
            authenticator: AlwaysAuthenticated(),
            languageModels: LanguageModelResolver(claude: nil, onDevice: nil),
            profileServices: { _ in profileServices },
            removeProfileData: { _ in },
            extensionsDirectory: { _ in
                FileManager.default.temporaryDirectory.appending(path: "MarcUITestsExtensions-\(UUID().uuidString)")
            },
            importers: ImportServices(readHistory: { _, _ in [] }, suggestedLocation: { _ in nil }),
            filterLists: [],
            isUITesting: true,
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: "MarcUIFeatureTests-\(UUID().uuidString)")
        let engine = WebEngine(
            contentBlocker: ContentBlocker(directory: directory.appending(path: "Blocker")) { _, _ in .notModified },
            favicons: FaviconLoader(directory: directory.appending(path: "Favicons")),
        )
        let snapshot = try await repository.load()
        let session = BrowserSession(snapshot: snapshot, services: services, engine: engine)
        return (session, repository, archive)
    }
}
