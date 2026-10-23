import Foundation
import GRDB
import MarcCore

public struct GRDBWorkspaceRepository: WorkspaceRepository {
    private let writer: any DatabaseWriter

    public init(database: AppDatabase) {
        writer = database.writer
    }

    public func load() async throws -> WorkspaceSnapshot {
        try await writer.read { db in
            let profiles = try ProfileRecord.fetchAll(db).map(\.domain)
            let spaces = try SpaceRecord.fetchAll(db).map(\.domain)
            let items = try SidebarItemRecord.fetchAll(db).compactMap(\.domain)
            let windows = try WindowSessionRecord.order(Column("sortKey")).fetchAll(db).map(\.state)
            return WorkspaceSnapshot(workspace: Workspace(profiles: profiles, spaces: spaces, items: items), windows: windows)
        }
    }

    public func apply(_ changes: WorkspaceChanges) async throws {
        try await writer.write { db in
            for profile in changes.upsertedProfiles {
                try ProfileRecord(profile).upsert(db)
            }
            for space in changes.upsertedSpaces {
                try SpaceRecord(space).upsert(db)
            }
            for item in changes.upsertedItems {
                try SidebarItemRecord(item).upsert(db)
            }
            if !changes.deletedItemIDs.isEmpty {
                try SidebarItemRecord.deleteAll(db, keys: changes.deletedItemIDs.map(\.rawValue))
            }
            if !changes.deletedSpaceIDs.isEmpty {
                try SpaceRecord.deleteAll(db, keys: changes.deletedSpaceIDs.map(\.rawValue))
            }
            if !changes.deletedProfileIDs.isEmpty {
                try ProfileRecord.deleteAll(db, keys: changes.deletedProfileIDs.map(\.rawValue))
            }
        }
    }

    public func saveWindows(_ windows: [WindowState]) async throws {
        try await writer.write { db in
            try WindowSessionRecord.deleteAll(db)
            for (index, window) in windows.enumerated() {
                try WindowSessionRecord(id: window.id.rawValue, state: window, sortKey: Double(index)).insert(db)
            }
        }
    }
}

public struct GRDBArchiveRepository: ArchiveRepository {
    private let writer: any DatabaseWriter

    public init(database: AppDatabase) {
        writer = database.writer
    }

    public func add(_ tabs: [ArchivedTab]) async throws {
        try await writer.write { db in
            for tab in tabs {
                try ArchivedTabRecord(tab).upsert(db)
            }
        }
    }

    public func archivedTabs(profileID: Profile.ID?, limit: Int) async throws -> [ArchivedTab] {
        try await writer.read { db in
            var request = ArchivedTabRecord.order(Column("archivedAt").desc).limit(limit)
            if let profileID {
                request = request.filter(Column("profileID") == profileID.rawValue)
            }
            return try request.fetchAll(db).compactMap(\.domain)
        }
    }

    public func remove(_ ids: [ArchivedTab.ID]) async throws {
        try await writer.write { db in
            _ = try ArchivedTabRecord.deleteAll(db, keys: ids.map(\.rawValue))
        }
    }

    public func removeAll(profileID: Profile.ID?) async throws {
        try await writer.write { db in
            if let profileID {
                _ = try ArchivedTabRecord.filter(Column("profileID") == profileID.rawValue).deleteAll(db)
            } else {
                _ = try ArchivedTabRecord.deleteAll(db)
            }
        }
    }
}

public struct GRDBBoostRepository: BoostRepository {
    private let writer: any DatabaseWriter

    public init(database: AppDatabase) {
        writer = database.writer
    }

    public func allBoosts() async throws -> [Boost] {
        try await writer.read { db in
            try BoostRecord.order(Column("updatedAt").desc).fetchAll(db).map(\.payload)
        }
    }

    public func save(_ boost: Boost) async throws {
        try await writer.write { db in
            try BoostRecord(boost).upsert(db)
        }
    }

    public func delete(_ id: Boost.ID) async throws {
        try await writer.write { db in
            _ = try BoostRecord.deleteOne(db, key: id.rawValue)
        }
    }
}

public struct GRDBNoteRepository: NoteRepository {
    private let writer: any DatabaseWriter

    public init(database: AppDatabase) {
        writer = database.writer
    }

    public func note(_ id: Note.ID) async throws -> Note? {
        try await writer.read { db in
            try NoteRecord.fetchOne(db, key: id.rawValue)?.domain
        }
    }

    public func allNotes() async throws -> [Note] {
        try await writer.read { db in
            try NoteRecord.order(Column("updatedAt").desc).fetchAll(db).map(\.domain)
        }
    }

    public func save(_ note: Note) async throws {
        try await writer.write { db in
            try NoteRecord(note).upsert(db)
        }
    }

    public func delete(_ id: Note.ID) async throws {
        try await writer.write { db in
            _ = try NoteRecord.deleteOne(db, key: id.rawValue)
        }
    }
}
