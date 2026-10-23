import Foundation

public struct ImportSummary: Hashable, Sendable {
    public var spaces = 0
    public var tabs = 0
    public var folders = 0
    public var favorites = 0
    public var historyEntries = 0

    public init() {}
}

public extension Workspace {
    /// Merges imported data. Arc Spaces become new Spaces (sharing profiles the way they did in
    /// Arc); plain bookmark trees go into one pinned folder in `targetSpace`.
    @discardableResult
    mutating func apply(_ imported: BrowserImport, targetSpace: Space.ID, now: Date = .now) throws -> ImportSummary {
        guard let target = spaces[targetSpace] else { throw WorkspaceError.spaceNotFound }
        var summary = ImportSummary()
        var profileMap: [ImportedProfileKey: Profile.ID] = [.default: target.profileID]

        func profile(for key: ImportedProfileKey) -> Profile.ID {
            if let existing = profileMap[key] { return existing }
            let name = if case let .named(name) = key {
                "\(imported.source.displayName) – \(name)"
            } else {
                imported.source.displayName
            }
            let id = addProfile(name: name)
            profileMap[key] = id
            return id
        }

        for space in imported.spaces {
            let spaceID = try addSpace(
                name: space.name,
                profileID: profile(for: space.profile),
                icon: space.icon ?? .symbol("circle.fill"),
                theme: space.theme ?? .default,
            )
            summary.spaces += 1
            try insert(space.pinned, into: .pinned(spaceID), parent: nil, summary: &summary, now: now)
            // Today lists are newest-first; inserting oldest-first at the top preserves order.
            for node in space.today.reversed() {
                try insertToday(node, spaceID: spaceID, summary: &summary, now: now)
            }
        }

        for (key, links) in imported.favorites {
            let profileID = profile(for: key)
            var existing = Set(favorites(for: profileID).compactMap { $0.tab?.url })
            for link in links where existing.insert(link.url).inserted {
                try openTab(TabContent(url: link.url, title: link.title), placement: .favoritesEnd(profileID), now: now)
                summary.favorites += 1
            }
        }

        if !imported.bookmarks.isEmpty {
            let folderID = try createFolder(
                named: "\(imported.source.displayName) Bookmarks",
                at: SidebarDestination(container: .pinned(targetSpace), index: .max),
                now: now,
            )
            summary.folders += 1
            try insert(imported.bookmarks, into: .pinned(targetSpace), parent: folderID, summary: &summary, now: now)
            try setFolderExpanded(folderID, false)
        }

        summary.historyEntries = imported.history.count
        return summary
    }

    private mutating func insert(
        _ nodes: [ImportedNode],
        into container: SidebarContainer,
        parent: SidebarItem.ID?,
        summary: inout ImportSummary,
        now: Date,
    ) throws {
        for node in nodes {
            let destination = SidebarDestination(container: container, parentID: parent, index: .max)
            switch node {
            case let .link(link):
                let item = SidebarItem(
                    container: container,
                    parentID: parent,
                    sortKey: 0,
                    content: .tab(TabContent(url: link.url, title: link.title, homeURL: link.url)),
                    createdAt: now,
                )
                try insert(item, at: destination)
                summary.tabs += 1
            case let .folder(name, children):
                let folderID = try createFolder(named: name, at: destination, now: now)
                summary.folders += 1
                try insert(children, into: container, parent: folderID, summary: &summary, now: now)
            case let .split(links, axis):
                var tabIDs: [SidebarItem.ID] = []
                for link in links {
                    let item = SidebarItem(
                        container: container,
                        parentID: parent,
                        sortKey: 0,
                        content: .tab(TabContent(url: link.url, title: link.title, homeURL: link.url)),
                        createdAt: now,
                    )
                    try insert(item, at: destination)
                    tabIDs.append(item.id)
                    summary.tabs += 1
                }
                try makeSplit(tabIDs, axis: axis)
            }
        }
    }

    private mutating func insertToday(_ node: ImportedNode, spaceID: Space.ID, summary: inout ImportSummary, now: Date) throws {
        switch node {
        case let .link(link):
            try openTab(TabContent(url: link.url, title: link.title), placement: .todayTop(spaceID), now: now)
            summary.tabs += 1
        case let .folder(_, children):
            // Today has no folders; flatten.
            for child in children.reversed() {
                try insertToday(child, spaceID: spaceID, summary: &summary, now: now)
            }
        case let .split(links, axis):
            var tabIDs: [SidebarItem.ID] = []
            for link in links.reversed() {
                try tabIDs.insert(openTab(TabContent(url: link.url, title: link.title), placement: .todayTop(spaceID), now: now), at: 0)
                summary.tabs += 1
            }
            try makeSplit(tabIDs, axis: axis)
        }
    }

    private mutating func makeSplit(_ tabIDs: [SidebarItem.ID], axis: SplitLayout.Axis) throws {
        guard let first = tabIDs.first, tabIDs.count > 1 else { return }
        var previous = first
        for id in tabIDs.dropFirst() {
            try split(previous, with: id, axis: axis)
            previous = id
        }
    }
}
