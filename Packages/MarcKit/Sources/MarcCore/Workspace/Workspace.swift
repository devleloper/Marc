import Foundation

/// The complete structure of the user's browser: profiles, Spaces and the sidebar tree.
/// `Workspace` is a value; all changes go through the mutating methods in
/// `Workspace+Mutations.swift` so that they can be validated, diffed and persisted.
public struct Workspace: Hashable, Sendable {
    public internal(set) var profiles: [Profile.ID: Profile]
    public internal(set) var spaces: [Space.ID: Space]
    public internal(set) var items: [SidebarItem.ID: SidebarItem]

    public init(profiles: [Profile] = [], spaces: [Space] = [], items: [SidebarItem] = []) {
        self.profiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        self.spaces = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    /// A first-launch workspace with one profile and one Space.
    public static func makeDefault() -> Workspace {
        let profile = Profile(name: "Personal", symbol: "person.crop.circle")
        let space = Space(profileID: profile.id, name: "Personal", icon: .symbol("sparkles"), theme: .default)
        return Workspace(profiles: [profile], spaces: [space])
    }

    public var isEmpty: Bool {
        profiles.isEmpty || spaces.isEmpty
    }

    // MARK: - Profiles and Spaces

    public var orderedProfiles: [Profile] {
        profiles.values.sorted { ($0.sortKey, $0.createdAt) < ($1.sortKey, $1.createdAt) }
    }

    public var orderedSpaces: [Space] {
        spaces.values.sorted { ($0.sortKey, $0.id) < ($1.sortKey, $1.id) }
    }

    public func spaces(in profileID: Profile.ID) -> [Space] {
        orderedSpaces.filter { $0.profileID == profileID }
    }

    public func profile(for spaceID: Space.ID) -> Profile? {
        spaces[spaceID].flatMap { profiles[$0.profileID] }
    }

    /// The profile whose data store an item uses.
    public func profileID(for itemID: SidebarItem.ID) -> Profile.ID? {
        guard let item = items[itemID] else { return nil }
        switch item.container {
        case let .favorites(profileID): return profileID
        case let .pinned(spaceID), let .today(spaceID): return spaces[spaceID]?.profileID
        }
    }

    // MARK: - Tree queries

    /// Direct children of a container root or of a parent item, ordered.
    public func children(of container: SidebarContainer, parent: SidebarItem.ID? = nil) -> [SidebarItem] {
        items.values
            .filter { $0.container == container && $0.parentID == parent }
            .sorted { ($0.sortKey, $0.createdAt) < ($1.sortKey, $1.createdAt) }
    }

    /// Direct children of a folder or split.
    public func children(of itemID: SidebarItem.ID) -> [SidebarItem] {
        guard let item = items[itemID] else { return [] }
        return children(of: item.container, parent: itemID)
    }

    public func descendants(of itemID: SidebarItem.ID) -> [SidebarItem] {
        children(of: itemID).flatMap { [$0] + descendants(of: $0.id) }
    }

    public func isDescendant(_ itemID: SidebarItem.ID, of ancestorID: SidebarItem.ID) -> Bool {
        var current = items[itemID]?.parentID
        while let parentID = current {
            if parentID == ancestorID { return true }
            current = items[parentID]?.parentID
        }
        return false
    }

    public func favorites(for profileID: Profile.ID) -> [SidebarItem] {
        children(of: .favorites(profileID))
    }

    /// The split that contains `itemID`, if any.
    public func enclosingSplit(of itemID: SidebarItem.ID) -> SidebarItem? {
        guard let parentID = items[itemID]?.parentID, let parent = items[parentID], parent.kind == .split else { return nil }
        return parent
    }

    /// Items a window can select: tabs and notes, in sidebar order (favorites, pinned with
    /// expanded folders, today). Tabs inside a split are listed in pane order.
    public func selectableItems(in spaceID: Space.ID) -> [SidebarItem] {
        guard let space = spaces[spaceID] else { return [] }
        let roots = favorites(for: space.profileID) + children(of: .pinned(spaceID)) + children(of: .today(spaceID))
        return roots.flatMap(selectableLeaves)
    }

    private func selectableLeaves(of item: SidebarItem) -> [SidebarItem] {
        switch item.content {
        case .tab, .note:
            [item]
        case let .folder(folder):
            folder.isExpanded ? children(of: item.id).flatMap(selectableLeaves) : []
        case let .split(split):
            split.layout.panes.compactMap { items[$0] }
        }
    }

    /// All tab items in a Space, including collapsed folders and splits.
    public func allTabs(in spaceID: Space.ID) -> [SidebarItem] {
        items.values.filter { $0.container.spaceID == spaceID && $0.kind == .tab }
    }
}
