import Foundation

/// The persisted difference between two workspace values.
public struct WorkspaceChanges: Hashable, Sendable {
    public var upsertedProfiles: [Profile] = []
    public var deletedProfileIDs: [Profile.ID] = []
    public var upsertedSpaces: [Space] = []
    public var deletedSpaceIDs: [Space.ID] = []
    public var upsertedItems: [SidebarItem] = []
    public var deletedItemIDs: [SidebarItem.ID] = []

    public init() {}

    public init(from old: Workspace, to new: Workspace) {
        (upsertedProfiles, deletedProfileIDs) = Self.diff(old.profiles, new.profiles)
        (upsertedSpaces, deletedSpaceIDs) = Self.diff(old.spaces, new.spaces)
        (upsertedItems, deletedItemIDs) = Self.diff(old.items, new.items)
    }

    public var isEmpty: Bool {
        upsertedProfiles.isEmpty && deletedProfileIDs.isEmpty
            && upsertedSpaces.isEmpty && deletedSpaceIDs.isEmpty
            && upsertedItems.isEmpty && deletedItemIDs.isEmpty
    }

    private static func diff<Key: Hashable, Value: Equatable>(_ old: [Key: Value], _ new: [Key: Value]) -> ([Value], [Key]) {
        let upserted = new.compactMap { key, value in old[key] == value ? nil : value }
        let deleted = old.keys.filter { new[$0] == nil }
        return (upserted, deleted)
    }
}
