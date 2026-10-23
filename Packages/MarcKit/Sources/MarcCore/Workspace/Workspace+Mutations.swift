import Foundation

public enum WorkspaceError: Error, Equatable, Sendable {
    case itemNotFound
    case spaceNotFound
    case profileNotFound
    case invalidDestination
    case lastSpace
    case lastProfile
    case notATab
    case split(SplitLayout.Error)
}

/// Where a newly created tab goes.
public enum TabPlacement: Hashable, Sendable {
    /// Top of the Space's Today list (Arc's default for new tabs).
    case todayTop(Space.ID)
    /// End of the Space's pinned section.
    case pinnedEnd(Space.ID)
    /// End of a profile's favorites.
    case favoritesEnd(Profile.ID)
    /// Directly below an existing item, in the same container and parent.
    case below(SidebarItem.ID)
    /// End of a folder.
    case inFolder(SidebarItem.ID)
    /// An exact drop location.
    case destination(SidebarDestination)
}

/// A drop location in the sidebar.
public struct SidebarDestination: Hashable, Sendable {
    public var container: SidebarContainer
    public var parentID: SidebarItem.ID?
    /// Index among the destination's children, computed as if the moved item were removed.
    public var index: Int

    public init(container: SidebarContainer, parentID: SidebarItem.ID? = nil, index: Int) {
        self.container = container
        self.parentID = parentID
        self.index = index
    }
}

public extension Workspace {
    // MARK: - Profiles

    @discardableResult
    mutating func addProfile(name: String, symbol: String = "person.crop.circle") -> Profile.ID {
        let profile = Profile(name: name, symbol: symbol, sortKey: (orderedProfiles.last?.sortKey ?? -1) + 1)
        profiles[profile.id] = profile
        return profile.id
    }

    mutating func updateProfile(_ id: Profile.ID, _ update: (inout Profile) -> Void) throws {
        guard var profile = profiles[id] else { throw WorkspaceError.profileNotFound }
        update(&profile)
        profiles[id] = profile
    }

    /// Deletes a profile, moving its Spaces to `replacement` and discarding its favorites.
    mutating func deleteProfile(_ id: Profile.ID, reassigningSpacesTo replacement: Profile.ID) throws {
        guard profiles[id] != nil, profiles[replacement] != nil, id != replacement else { throw WorkspaceError.profileNotFound }
        guard profiles.count > 1 else { throw WorkspaceError.lastProfile }
        for space in spaces.values where space.profileID == id {
            spaces[space.id]?.profileID = replacement
        }
        for item in favorites(for: id) {
            removeSubtree(item.id)
        }
        profiles[id] = nil
    }

    // MARK: - Spaces

    @discardableResult
    mutating func addSpace(
        name: String,
        profileID: Profile.ID,
        icon: SpaceIcon = .symbol("circle.fill"),
        theme: Theme = .default,
    ) throws -> Space.ID {
        guard profiles[profileID] != nil else { throw WorkspaceError.profileNotFound }
        let space = Space(
            profileID: profileID,
            name: name,
            icon: icon,
            theme: theme,
            sortKey: (orderedSpaces.last?.sortKey ?? -1) + 1,
        )
        spaces[space.id] = space
        return space.id
    }

    mutating func updateSpace(_ id: Space.ID, _ update: (inout Space) -> Void) throws {
        guard var space = spaces[id] else { throw WorkspaceError.spaceNotFound }
        update(&space)
        guard profiles[space.profileID] != nil else { throw WorkspaceError.profileNotFound }
        spaces[id] = space
    }

    /// Deletes a Space and returns the tabs it contained so they can be archived.
    @discardableResult
    mutating func deleteSpace(_ id: Space.ID) throws -> [SidebarItem] {
        guard spaces[id] != nil else { throw WorkspaceError.spaceNotFound }
        guard spaces.count > 1 else { throw WorkspaceError.lastSpace }
        let contained = items.values.filter { $0.container.spaceID == id }
        for item in contained {
            items[item.id] = nil
        }
        spaces[id] = nil
        return contained.filter { $0.kind == .tab }
    }

    mutating func moveSpace(_ id: Space.ID, to index: Int) throws {
        guard spaces[id] != nil else { throw WorkspaceError.spaceNotFound }
        var ordered = orderedSpaces.filter { $0.id != id }.map(\.id)
        ordered.insert(id, at: min(max(index, 0), ordered.count))
        for (position, spaceID) in ordered.enumerated() {
            spaces[spaceID]?.sortKey = Double(position)
        }
    }

    // MARK: - Creating items

    @discardableResult
    mutating func openTab(
        _ content: TabContent,
        placement: TabPlacement,
        id: SidebarItem.ID = SidebarItem.ID(),
        now: Date = .now,
    ) throws -> SidebarItem.ID {
        var content = content
        let destination: SidebarDestination
        switch placement {
        case let .todayTop(spaceID):
            guard spaces[spaceID] != nil else { throw WorkspaceError.spaceNotFound }
            destination = SidebarDestination(container: .today(spaceID), index: 0)
            content.homeURL = nil
        case let .pinnedEnd(spaceID):
            guard spaces[spaceID] != nil else { throw WorkspaceError.spaceNotFound }
            destination = SidebarDestination(container: .pinned(spaceID), index: .max)
            content.homeURL = content.homeURL ?? content.url
        case let .favoritesEnd(profileID):
            guard profiles[profileID] != nil else { throw WorkspaceError.profileNotFound }
            destination = SidebarDestination(container: .favorites(profileID), index: .max)
            content.homeURL = content.homeURL ?? content.url
        case let .below(anchorID):
            guard let anchor = items[anchorID] else { throw WorkspaceError.itemNotFound }
            let target = enclosingSplit(of: anchorID) ?? anchor
            let siblings = children(of: target.container, parent: target.parentID)
            let anchorIndex = siblings.firstIndex { $0.id == target.id } ?? siblings.count - 1
            destination = SidebarDestination(container: target.container, parentID: target.parentID, index: anchorIndex + 1)
            if target.container.section != .today { content.homeURL = content.homeURL ?? content.url }
        case let .inFolder(folderID):
            guard let folder = items[folderID], folder.kind == .folder else { throw WorkspaceError.invalidDestination }
            destination = SidebarDestination(container: folder.container, parentID: folderID, index: .max)
            content.homeURL = content.homeURL ?? content.url
        case let .destination(exact):
            destination = exact
            content.homeURL = exact.container.section == .today ? nil : content.homeURL ?? content.url
        }
        let item = SidebarItem(
            id: id,
            container: destination.container,
            parentID: destination.parentID,
            sortKey: 0,
            content: .tab(content),
            createdAt: now,
        )
        try insert(item, at: destination)
        return id
    }

    @discardableResult
    mutating func createFolder(named name: String, at destination: SidebarDestination, now: Date = .now) throws -> SidebarItem.ID {
        let folder = SidebarItem(
            container: destination.container,
            parentID: destination.parentID,
            sortKey: 0,
            content: .folder(FolderContent(name: name)),
            createdAt: now,
        )
        try insert(folder, at: destination)
        return folder.id
    }

    @discardableResult
    mutating func addNote(_ noteID: Note.ID, placement: TabPlacement, now: Date = .now) throws -> SidebarItem.ID {
        let destination: SidebarDestination
        switch placement {
        case let .todayTop(spaceID): destination = SidebarDestination(container: .today(spaceID), index: 0)
        case let .pinnedEnd(spaceID): destination = SidebarDestination(container: .pinned(spaceID), index: .max)
        case .favoritesEnd: throw WorkspaceError.invalidDestination
        case let .below(anchorID):
            guard let anchor = items[anchorID] else { throw WorkspaceError.itemNotFound }
            let index = children(of: anchor.container, parent: anchor.parentID).firstIndex { $0.id == anchorID } ?? 0
            destination = SidebarDestination(container: anchor.container, parentID: anchor.parentID, index: index + 1)
        case let .inFolder(folderID):
            guard let folder = items[folderID] else { throw WorkspaceError.itemNotFound }
            destination = SidebarDestination(container: folder.container, parentID: folderID, index: .max)
        case let .destination(exact):
            destination = exact
        }
        let item = SidebarItem(
            container: destination.container,
            parentID: destination.parentID,
            sortKey: 0,
            content: .note(noteID),
            createdAt: now,
        )
        try insert(item, at: destination)
        return item.id
    }

    @discardableResult
    mutating func duplicateTab(_ id: SidebarItem.ID, now: Date = .now) throws -> SidebarItem.ID {
        guard let item = items[id], var tab = item.tab, let spaceID = spaceID(for: item) else { throw WorkspaceError.notATab }
        tab.homeURL = nil
        return try openTab(tab, placement: .todayTop(spaceID), now: now)
    }

    // MARK: - Updating items

    mutating func updateTab(_ id: SidebarItem.ID, _ update: (inout TabContent) -> Void) throws {
        guard var tab = items[id]?.tab else { throw WorkspaceError.notATab }
        update(&tab)
        items[id]?.content = .tab(tab)
    }

    mutating func renameFolder(_ id: SidebarItem.ID, to name: String) throws {
        guard case var .folder(folder) = items[id]?.content else { throw WorkspaceError.itemNotFound }
        folder.name = name
        items[id]?.content = .folder(folder)
    }

    mutating func setFolderExpanded(_ id: SidebarItem.ID, _ isExpanded: Bool) throws {
        guard case var .folder(folder) = items[id]?.content else { throw WorkspaceError.itemNotFound }
        folder.isExpanded = isExpanded
        items[id]?.content = .folder(folder)
    }

    /// Records activity so that the item is not auto-archived.
    mutating func touch(_ id: SidebarItem.ID, at date: Date) {
        guard items[id] != nil else { return }
        items[id]?.lastActiveAt = date
        if let split = enclosingSplit(of: id) {
            items[split.id]?.lastActiveAt = date
        }
    }

    /// Restores a pinned or favorite tab's URL to its home URL.
    mutating func resetToHome(_ id: SidebarItem.ID) throws {
        try updateTab(id) { tab in
            if let homeURL = tab.homeURL { tab.url = homeURL }
        }
    }

    // MARK: - Moving items

    mutating func move(_ id: SidebarItem.ID, to destination: SidebarDestination) throws {
        guard let item = items[id] else { throw WorkspaceError.itemNotFound }
        try validate(kind: item.kind, at: destination, movingItem: id)
        if enclosingSplit(of: id) != nil {
            try detachFromSplit(id)
        }
        let siblings = children(of: destination.container, parent: destination.parentID).filter { $0.id != id }
        let key = sortKey(forInsertionAt: destination.index, among: siblings)
        relocateSubtree(id, to: destination.container)
        items[id]?.parentID = destination.parentID
        items[id]?.sortKey = key
        adjustHomeURL(for: id, in: destination.container)
    }

    mutating func pin(_ id: SidebarItem.ID) throws {
        guard let item = items[id], let spaceID = spaceID(for: item) else { throw WorkspaceError.itemNotFound }
        let target = enclosingSplit(of: id) ?? item
        try move(target.id, to: SidebarDestination(container: .pinned(spaceID), index: .max))
    }

    mutating func unpin(_ id: SidebarItem.ID, into spaceID: Space.ID) throws {
        guard let item = items[id] else { throw WorkspaceError.itemNotFound }
        let target = enclosingSplit(of: id) ?? item
        try move(target.id, to: SidebarDestination(container: .today(spaceID), index: 0))
    }

    mutating func addToFavorites(_ id: SidebarItem.ID) throws {
        guard let item = items[id], item.kind == .tab, let profileID = profileID(for: id) else { throw WorkspaceError.notATab }
        try move(id, to: SidebarDestination(container: .favorites(profileID), index: .max))
    }

    // MARK: - Removing items

    /// Removes an item with its descendants and returns the removed tabs (for archiving).
    @discardableResult
    mutating func remove(_ id: SidebarItem.ID) -> [SidebarItem] {
        guard items[id] != nil else { return [] }
        if enclosingSplit(of: id) != nil {
            try? detachFromSplit(id)
        }
        return removeSubtree(id).filter { $0.kind == .tab }
    }

    /// Removes every root item of a Space's Today list.
    @discardableResult
    mutating func clearToday(in spaceID: Space.ID) -> [SidebarItem] {
        children(of: .today(spaceID)).flatMap { remove($0.id) }
    }

    // MARK: - Split view

    /// Shows `otherID` next to `targetID` in a split. Creates the split if needed.
    mutating func split(
        _ targetID: SidebarItem.ID,
        with otherID: SidebarItem.ID,
        axis: SplitLayout.Axis = .horizontal,
        placeAfter: Bool = true,
    ) throws {
        guard targetID != otherID,
              let target = items[targetID], target.kind == .tab,
              let other = items[otherID], other.kind == .tab
        else { throw WorkspaceError.notATab }
        // Favorites cannot hold splits; callers duplicate a favorite into Today first.
        guard target.container.section != .favorites, other.container.section != .favorites else {
            throw WorkspaceError.invalidDestination
        }

        if let existing = enclosingSplit(of: targetID), case var .split(content) = existing.content {
            if enclosingSplit(of: otherID)?.id == existing.id { return }
            do {
                try content.layout.insert(otherID, adjacentTo: targetID, axis: axis, after: placeAfter)
            } catch let error as SplitLayout.Error {
                throw WorkspaceError.split(error)
            }
            if enclosingSplit(of: otherID) != nil { try detachFromSplit(otherID) }
            items[existing.id]?.content = .split(content)
            relocateSubtree(otherID, to: existing.container)
            items[otherID]?.parentID = existing.id
            items[otherID]?.sortKey = Double(content.layout.panes.count)
            adjustHomeURL(for: otherID, in: existing.container)
            return
        }

        if enclosingSplit(of: otherID) != nil { try detachFromSplit(otherID) }
        guard let anchor = items[targetID] else { throw WorkspaceError.itemNotFound }
        let panes = placeAfter ? [targetID, otherID] : [otherID, targetID]
        let splitItem = SidebarItem(
            container: anchor.container,
            parentID: anchor.parentID,
            sortKey: anchor.sortKey,
            content: .split(SplitContent(layout: SplitLayout(panes: panes, axis: axis))),
            createdAt: .now,
        )
        items[splitItem.id] = splitItem
        for (index, paneID) in panes.enumerated() {
            relocateSubtree(paneID, to: anchor.container)
            items[paneID]?.parentID = splitItem.id
            items[paneID]?.sortKey = Double(index)
            adjustHomeURL(for: paneID, in: anchor.container)
        }
    }

    /// Takes a tab out of its split and places it directly below the split.
    mutating func separateFromSplit(_ id: SidebarItem.ID) throws {
        guard let split = enclosingSplit(of: id) else { throw WorkspaceError.invalidDestination }
        let siblings = children(of: split.container, parent: split.parentID)
        let splitIndex = siblings.firstIndex { $0.id == split.id } ?? 0
        try detachFromSplit(id)
        let destination = SidebarDestination(container: split.container, parentID: split.parentID, index: splitIndex + 1)
        let remaining = children(of: split.container, parent: split.parentID).filter { $0.id != id }
        let key = sortKey(forInsertionAt: destination.index, among: remaining)
        items[id]?.parentID = split.parentID
        items[id]?.sortKey = key
    }

    mutating func updateSplitLayout(_ splitID: SidebarItem.ID, _ update: (inout SplitLayout) throws -> Void) throws {
        guard case var .split(content) = items[splitID]?.content else { throw WorkspaceError.itemNotFound }
        do {
            try update(&content.layout)
        } catch let error as SplitLayout.Error {
            throw WorkspaceError.split(error)
        }
        items[splitID]?.content = .split(content)
    }

    // MARK: - Archive candidates

    /// Today tabs whose last activity is older than the interval. Items in `excluding` (for example
    /// tabs visible in a window) are never archived.
    func archiveCandidates(now: Date, interval: ArchiveInterval, excluding: Set<SidebarItem.ID>) -> [SidebarItem] {
        guard let duration = interval.duration else { return [] }
        let threshold = now.addingTimeInterval(-duration)
        return items.values.filter { item in
            guard case .today = item.container, item.parentID == nil, !excluding.contains(item.id) else { return false }
            if item.kind == .split, children(of: item.id).contains(where: { excluding.contains($0.id) }) { return false }
            return item.lastActiveAt < threshold
        }
    }
}

// MARK: - Internal helpers

extension Workspace {
    func spaceID(for item: SidebarItem) -> Space.ID? {
        if let spaceID = item.container.spaceID { return spaceID }
        guard let profileID = item.container.profileID else { return nil }
        return spaces(in: profileID).first?.id
    }

    mutating func insert(_ item: SidebarItem, at destination: SidebarDestination) throws {
        try validate(kind: item.kind, at: destination, movingItem: nil)
        var item = item
        item.sortKey = sortKey(forInsertionAt: destination.index, among: children(of: destination.container, parent: destination.parentID))
        items[item.id] = item
    }

    func validate(kind: SidebarItem.Kind, at destination: SidebarDestination, movingItem: SidebarItem.ID?) throws {
        switch destination.container {
        case let .favorites(profileID):
            guard profiles[profileID] != nil else { throw WorkspaceError.profileNotFound }
        case let .pinned(spaceID), let .today(spaceID):
            guard spaces[spaceID] != nil else { throw WorkspaceError.spaceNotFound }
        }
        if let parentID = destination.parentID {
            guard let parent = items[parentID], parent.kind == .folder, parent.container == destination.container else {
                throw WorkspaceError.invalidDestination
            }
            if let movingItem, movingItem == parentID || isDescendant(parentID, of: movingItem) {
                throw WorkspaceError.invalidDestination
            }
            guard kind != .split || destination.container.section == .pinned else { throw WorkspaceError.invalidDestination }
        } else {
            guard destination.container.allowedRootKinds.contains(kind) else { throw WorkspaceError.invalidDestination }
        }
    }

    /// Computes a key that orders a new item at `index` among `siblings`, renumbering the siblings
    /// when floating-point precision runs out.
    mutating func sortKey(forInsertionAt index: Int, among siblings: [SidebarItem]) -> Double {
        let position = min(max(index, 0), siblings.count)
        let lower = position > 0 ? siblings[position - 1].sortKey : nil
        let upper = position < siblings.count ? siblings[position].sortKey : nil
        switch (lower, upper) {
        case (nil, nil):
            return 0
        case let (lower?, nil):
            return lower + 1
        case let (nil, upper?):
            return upper - 1
        case let (lower?, upper?) where upper - lower > 1e-9:
            return (lower + upper) / 2
        default:
            for (offset, sibling) in siblings.enumerated() {
                items[sibling.id]?.sortKey = Double(offset < position ? offset : offset + 1)
            }
            return Double(position)
        }
    }

    /// Updates the container of an item and all of its descendants.
    mutating func relocateSubtree(_ id: SidebarItem.ID, to container: SidebarContainer) {
        let subtree = [id] + descendants(of: id).map(\.id)
        for itemID in subtree {
            items[itemID]?.container = container
        }
    }

    @discardableResult
    mutating func removeSubtree(_ id: SidebarItem.ID) -> [SidebarItem] {
        var subtree = descendants(of: id)
        if let item = items[id] { subtree.insert(item, at: 0) }
        for item in subtree {
            items[item.id] = nil
        }
        return subtree
    }

    /// Removes a tab from its split's layout, dissolving the split when one pane remains.
    mutating func detachFromSplit(_ id: SidebarItem.ID) throws {
        guard let split = enclosingSplit(of: id), case let .split(content) = split.content else { return }
        if let layout = content.layout.removing(id) {
            items[split.id]?.content = .split(SplitContent(layout: layout))
            items[id]?.parentID = split.parentID
            return
        }
        let remainingID = content.layout.panes.first { $0 != id }
        items[id]?.parentID = split.parentID
        if let remainingID {
            items[remainingID]?.parentID = split.parentID
            items[remainingID]?.sortKey = split.sortKey
        }
        items[split.id] = nil
    }

    mutating func adjustHomeURL(for id: SidebarItem.ID, in container: SidebarContainer) {
        let subtree = [id] + descendants(of: id).map(\.id)
        for itemID in subtree {
            guard var tab = items[itemID]?.tab else { continue }
            switch container.section {
            case .today: tab.homeURL = nil
            case .pinned, .favorites: tab.homeURL = tab.homeURL ?? tab.url
            }
            items[itemID]?.content = .tab(tab)
        }
    }
}
