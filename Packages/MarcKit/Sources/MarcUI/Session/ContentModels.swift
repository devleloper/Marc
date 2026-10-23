import Foundation
import MarcCore
import MarcWebKit
import Observation
import os

/// Archived tabs, newest first.
@Observable
public final class ArchiveModel {
    public private(set) var tabs: [ArchivedTab] = []
    @ObservationIgnored private let repository: any ArchiveRepository

    init(repository: any ArchiveRepository) {
        self.repository = repository
    }

    func reload() async {
        tabs = await (try? repository.archivedTabs(profileID: nil, limit: 1000)) ?? []
    }

    func add(_ newTabs: [ArchivedTab]) {
        guard !newTabs.isEmpty else { return }
        tabs.insert(contentsOf: newTabs, at: 0)
        Task { try? await repository.add(newTabs) }
    }

    func remove(_ ids: [ArchivedTab.ID]) {
        let removed = Set(ids)
        tabs.removeAll { removed.contains($0.id) }
        Task { try? await repository.remove(ids) }
    }

    func clear() {
        tabs.removeAll()
        Task { try? await repository.removeAll(profileID: nil) }
    }
}

/// Notes loaded on demand, saved with a short debounce while typing.
@Observable
public final class NotesModel {
    public private(set) var notes: [Note.ID: Note] = [:]
    @ObservationIgnored private let repository: any NoteRepository
    @ObservationIgnored private var pendingSaves: [Note.ID: Task<Void, Never>] = [:]

    init(repository: any NoteRepository) {
        self.repository = repository
    }

    func loadAll() async {
        let all = await (try? repository.allNotes()) ?? []
        notes = Dictionary(all.map { ($0.id, $0) }) { first, _ in first }
    }

    func create() -> Note {
        let note = Note()
        notes[note.id] = note
        Task { try? await repository.save(note) }
        return note
    }

    func update(_ id: Note.ID, title: String, content: Data) {
        guard var note = notes[id] else { return }
        note.title = title
        note.content = content
        note.updatedAt = .now
        notes[id] = note
        pendingSaves[id]?.cancel()
        let repository = repository
        pendingSaves[id] = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            try? await repository.save(note)
        }
    }

    func delete(_ id: Note.ID) {
        notes[id] = nil
        Task { try? await repository.delete(id) }
    }
}

/// Boosts, mirrored into the web engine so that tabs apply them.
@Observable
public final class BoostsModel {
    public private(set) var boosts: [Boost] = []
    @ObservationIgnored private let repository: any BoostRepository
    @ObservationIgnored private let engine: WebEngine
    @ObservationIgnored private let runtime: TabRuntimeRegistry

    init(repository: any BoostRepository, engine: WebEngine, runtime: TabRuntimeRegistry) {
        self.repository = repository
        self.engine = engine
        self.runtime = runtime
    }

    func load() async {
        boosts = await (try? repository.allBoosts()) ?? []
        engine.setBoosts(boosts)
    }

    func boost(for host: String) -> Boost? {
        boosts.first { $0.matches(host: host) }
    }

    func save(_ boost: Boost) {
        var boost = boost
        boost.updatedAt = .now
        if let index = boosts.firstIndex(where: { $0.id == boost.id }) {
            boosts[index] = boost
        } else {
            boosts.insert(boost, at: 0)
        }
        engine.setBoosts(boosts)
        runtime.boostsDidChange()
        Task { [repository] in try? await repository.save(boost) }
    }

    func delete(_ id: Boost.ID) {
        let removed = boosts.first { $0.id == id }
        boosts.removeAll { $0.id == id }
        engine.setBoosts(boosts)
        if let removed {
            for tab in runtime.tabs.values {
                tab.applyBoostStyles([Boost(id: removed.id, name: removed.name, hostPattern: removed.hostPattern, isEnabled: false)])
            }
        }
        runtime.boostsDidChange()
        Task { [repository] in try? await repository.delete(id) }
    }
}

/// A closed tab that ⇧⌘T can bring back.
struct ClosedTab {
    let content: TabContent
    let container: SidebarContainer
    let windowID: WindowState.ID?
}

/// A transient message at the bottom of a window.
public struct Toast: Identifiable, Equatable {
    public let id = UUID()
    public let message: String
    public let symbol: String?
    public let actionTitle: String?
    let action: (() -> Void)?

    public static func == (lhs: Toast, rhs: Toast) -> Bool {
        lhs.id == rhs.id
    }
}
