import Foundation
import GRDB
import MarcCore
import Testing
@testable import MarcPersistence

struct WorkspaceRepositoryTests {
    @Test func `round trips the workspace through changes`() async throws {
        let database = try AppDatabase.inMemory()
        let repository = GRDBWorkspaceRepository(database: database)

        let empty = Workspace()
        var workspace = Workspace.makeDefault()
        let spaceID = workspace.orderedSpaces[0].id
        let folder = try workspace.createFolder(named: "Docs", at: SidebarDestination(container: .pinned(spaceID), index: 0))
        let a = try workspace.openTab(TabContent(url: URL(string: "https://a.com"), title: "A"), placement: .inFolder(folder))
        let b = try workspace.openTab(TabContent(url: URL(string: "https://b.com"), title: "B"), placement: .todayTop(spaceID))
        let c = try workspace.openTab(TabContent(url: URL(string: "https://c.com"), title: "C"), placement: .todayTop(spaceID))
        try workspace.split(b, with: c, axis: .vertical)
        try workspace.updateSpace(spaceID) { $0.theme = Theme.presets[3] }

        try await repository.apply(WorkspaceChanges(from: empty, to: workspace))
        let loaded = try await repository.load()
        #expect(loaded.workspace == workspace)

        var updated = workspace
        updated.remove(a)
        try await repository.apply(WorkspaceChanges(from: workspace, to: updated))
        #expect(try await repository.load().workspace == updated)
    }

    @Test func `saves window sessions in order`() async throws {
        let repository = try GRDBWorkspaceRepository(database: AppDatabase.inMemory())
        let space = Space.ID()
        let tab = SidebarItem.ID()
        let windows = [
            WindowState(spaceID: space, selection: [space: tab], frame: .init(x: 1, y: 2, width: 3, height: 4)),
            WindowState(kind: .little, spaceID: nil, isSidebarVisible: false),
        ]
        try await repository.saveWindows(windows)
        #expect(try await repository.load().windows == windows)
        try await repository.saveWindows(Array(windows.prefix(1)))
        #expect(try await repository.load().windows.count == 1)
    }

    @Test func `persists to disk across reopen`() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let locations = StorageLocations(root: directory)
        try locations.createDirectories()

        var workspace = Workspace.makeDefault()
        try workspace.openTab(TabContent(url: URL(string: "https://a.com")), placement: .todayTop(workspace.orderedSpaces[0].id))
        do {
            let repository = try GRDBWorkspaceRepository(database: AppDatabase.open(at: locations.appDatabase))
            try await repository.apply(WorkspaceChanges(from: Workspace(), to: workspace))
        }
        let reopened = try GRDBWorkspaceRepository(database: AppDatabase.open(at: locations.appDatabase))
        #expect(try await reopened.load().workspace == workspace)
    }
}

struct GlobalRepositoryTests {
    @Test func `archive lists newest first and filters by profile`() async throws {
        let repository = try GRDBArchiveRepository(database: AppDatabase.inMemory())
        let profile = Profile.ID()
        let other = Profile.ID()
        let old = try ArchivedTab(
            spaceID: nil,
            profileID: profile,
            title: "Old",
            url: #require(URL(string: "https://old.com")),
            archivedAt: .distantPast,
        )
        let new = try ArchivedTab(spaceID: nil, profileID: profile, title: "New", url: #require(URL(string: "https://new.com")))
        let foreign = try ArchivedTab(spaceID: nil, profileID: other, title: "X", url: #require(URL(string: "https://x.com")))
        try await repository.add([old, new, foreign])

        #expect(try await repository.archivedTabs(profileID: profile, limit: 10).map(\.title) == ["New", "Old"])
        try await repository.remove([new.id])
        #expect(try await repository.archivedTabs(profileID: nil, limit: 10).count == 2)
        try await repository.removeAll(profileID: other)
        #expect(try await repository.archivedTabs(profileID: nil, limit: 10).map(\.title) == ["Old"])
    }

    @Test func `boosts and notes round trip`() async throws {
        let database = try AppDatabase.inMemory()
        let boosts = GRDBBoostRepository(database: database)
        let notes = GRDBNoteRepository(database: database)

        let boost = Boost(name: "HN", hostPattern: "news.ycombinator.com", style: .init(hueRotation: 120), zappedSelectors: [".ad"])
        try await boosts.save(boost)
        #expect(try await boosts.allBoosts() == [boost])
        try await boosts.delete(boost.id)
        #expect(try await boosts.allBoosts().isEmpty)

        let note = Note(title: "Ideas", content: Data("rtfd".utf8))
        try await notes.save(note)
        #expect(try await notes.note(note.id) == note)
        #expect(try await notes.allNotes() == [note])
        try await notes.delete(note.id)
        #expect(try await notes.note(note.id) == nil)
    }
}
