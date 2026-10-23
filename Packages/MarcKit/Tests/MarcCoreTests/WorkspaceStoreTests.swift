import Foundation
import Testing
@testable import MarcCore

actor RecordingWorkspaceRepository: WorkspaceRepository {
    private(set) var appliedChanges: [WorkspaceChanges] = []
    private(set) var savedWindows: [[WindowState]] = []
    var failNext = false

    func load() async throws -> WorkspaceSnapshot {
        WorkspaceSnapshot(workspace: .makeDefault(), windows: [])
    }

    func apply(_ changes: WorkspaceChanges) async throws {
        if failNext {
            failNext = false
            throw CocoaError(.fileWriteUnknown)
        }
        appliedChanges.append(changes)
    }

    func saveWindows(_ windows: [WindowState]) async throws {
        savedWindows.append(windows)
    }

    func setFailNext() {
        failNext = true
    }
}

@MainActor
struct WorkspaceStoreTests {
    @Test func `persists changes in order`() async throws {
        let repository = RecordingWorkspaceRepository()
        let store = WorkspaceStore(workspace: .makeDefault(), repository: repository)
        let spaceID = store.workspace.orderedSpaces[0].id

        let first = try store.update { try $0.openTab(TabContent(url: URL(string: "https://a.com")), placement: .todayTop(spaceID)) }
        let second = try store.update { try $0.openTab(TabContent(url: URL(string: "https://b.com")), placement: .todayTop(spaceID)) }
        store.update { $0.remove(first) }
        await store.flush()

        let applied = await repository.appliedChanges
        #expect(applied.count == 3)
        #expect(applied[0].upsertedItems.map(\.id) == [first])
        #expect(applied[1].upsertedItems.map(\.id) == [second])
        #expect(applied[2].deletedItemIDs == [first])
    }

    @Test func `failed mutations leave state untouched`() async {
        let repository = RecordingWorkspaceRepository()
        let store = WorkspaceStore(workspace: .makeDefault(), repository: repository)
        let before = store.workspace
        #expect(throws: WorkspaceError.spaceNotFound) {
            try store.update { try $0.openTab(TabContent(url: nil), placement: .todayTop(Space.ID())) }
        }
        #expect(store.workspace == before)
        await store.flush()
        #expect(await repository.appliedChanges.isEmpty)
    }

    @Test func `no op mutations are not persisted`() async {
        let repository = RecordingWorkspaceRepository()
        let store = WorkspaceStore(workspace: .makeDefault(), repository: repository)
        store.update { _ in }
        await store.flush()
        #expect(await repository.appliedChanges.isEmpty)
    }

    @Test func `reports persistence errors`() async throws {
        let repository = RecordingWorkspaceRepository()
        await repository.setFailNext()
        let store = WorkspaceStore(workspace: .makeDefault(), repository: repository)
        var reported = false
        store.onPersistenceError = { _ in reported = true }
        let spaceID = store.workspace.orderedSpaces[0].id
        try store.update { try $0.openTab(TabContent(url: nil), placement: .todayTop(spaceID)) }
        await store.flush()
        #expect(reported)
    }
}
