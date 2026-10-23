import Foundation
import Testing
@testable import MarcCore

struct WorkspaceMutationTests {
    var workspace = Workspace.makeDefault()
    var spaceID: Space.ID { workspace.orderedSpaces[0].id }
    var profileID: Profile.ID { workspace.orderedProfiles[0].id }

    func tab(_ host: String) -> TabContent {
        TabContent(url: URL(string: "https://\(host)"), title: host)
    }

    func titles(_ container: SidebarContainer, parent: SidebarItem.ID? = nil, in workspace: Workspace) -> [String] {
        workspace.children(of: container, parent: parent).map { item in
            switch item.content {
            case let .tab(tab): tab.title
            case let .folder(folder): folder.name
            case .split: "split"
            case .note: "note"
            }
        }
    }

    @Test mutating func `new tabs go to the top of today`() throws {
        try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        try workspace.openTab(tab("b.com"), placement: .todayTop(spaceID))
        try workspace.openTab(tab("c.com"), placement: .todayTop(spaceID))
        #expect(titles(.today(spaceID), in: workspace) == ["c.com", "b.com", "a.com"])
    }

    @Test mutating func `pinning sets home URL and unpinning clears it`() throws {
        let id = try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        try workspace.pin(id)
        #expect(workspace.items[id]?.container == .pinned(spaceID))
        #expect(workspace.items[id]?.tab?.homeURL == URL(string: "https://a.com"))

        try workspace.unpin(id, into: spaceID)
        #expect(workspace.items[id]?.container == .today(spaceID))
        #expect(workspace.items[id]?.tab?.homeURL == nil)
    }

    @Test mutating func `favorites belong to the profile`() throws {
        let id = try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        try workspace.addToFavorites(id)
        #expect(workspace.favorites(for: profileID).map(\.id) == [id])
        #expect(workspace.profileID(for: id) == profileID)
    }

    @Test mutating func `folders only exist in pinned`() throws {
        #expect(throws: WorkspaceError.invalidDestination) {
            try workspace.createFolder(named: "Nope", at: SidebarDestination(container: .today(spaceID), index: 0))
        }
        let folder = try workspace.createFolder(named: "Work", at: SidebarDestination(container: .pinned(spaceID), index: 0))
        let id = try workspace.openTab(tab("a.com"), placement: .inFolder(folder))
        #expect(workspace.children(of: folder).map(\.id) == [id])
        #expect(workspace.items[id]?.tab?.homeURL != nil)
    }

    @Test mutating func `moving A folder moves its descendants`() throws {
        let otherSpace = try workspace.addSpace(name: "Work", profileID: profileID)
        let folder = try workspace.createFolder(named: "Docs", at: SidebarDestination(container: .pinned(spaceID), index: 0))
        let nested = try workspace.createFolder(
            named: "Nested",
            at: SidebarDestination(container: .pinned(spaceID), parentID: folder, index: 0),
        )
        let tabID = try workspace.openTab(tab("a.com"), placement: .inFolder(nested))

        try workspace.move(folder, to: SidebarDestination(container: .pinned(otherSpace), index: 0))
        #expect(workspace.items[tabID]?.container == .pinned(otherSpace))
        #expect(workspace.items[nested]?.container == .pinned(otherSpace))
    }

    @Test mutating func `cannot move A folder into itself`() throws {
        let folder = try workspace.createFolder(named: "A", at: SidebarDestination(container: .pinned(spaceID), index: 0))
        let child = try workspace.createFolder(named: "B", at: SidebarDestination(container: .pinned(spaceID), parentID: folder, index: 0))
        #expect(throws: WorkspaceError.invalidDestination) {
            try workspace.move(folder, to: SidebarDestination(container: .pinned(spaceID), parentID: child, index: 0))
        }
    }

    @Test mutating func `reordering uses destination index`() throws {
        let a = try workspace.openTab(tab("a.com"), placement: .pinnedEnd(spaceID))
        try workspace.openTab(tab("b.com"), placement: .pinnedEnd(spaceID))
        try workspace.openTab(tab("c.com"), placement: .pinnedEnd(spaceID))
        try workspace.move(a, to: SidebarDestination(container: .pinned(spaceID), index: 2))
        #expect(titles(.pinned(spaceID), in: workspace) == ["b.com", "c.com", "a.com"])
    }

    @Test mutating func `repeated insertions keep order when keys run out`() throws {
        let first = try workspace.openTab(tab("first.com"), placement: .pinnedEnd(spaceID))
        try workspace.openTab(tab("last.com"), placement: .pinnedEnd(spaceID))
        for index in 0 ..< 80 {
            let id = try workspace.openTab(tab("n\(index).com"), placement: .pinnedEnd(spaceID))
            try workspace.move(id, to: SidebarDestination(container: .pinned(spaceID), index: 1))
        }
        let order = titles(.pinned(spaceID), in: workspace)
        #expect(order.first == "first.com")
        #expect(order.last == "last.com")
        #expect(order[1] == "n79.com")
        #expect(workspace.children(of: .pinned(spaceID)).first?.id == first)
    }

    @Test mutating func `removing A folder returns its tabs`() throws {
        let folder = try workspace.createFolder(named: "A", at: SidebarDestination(container: .pinned(spaceID), index: 0))
        try workspace.openTab(tab("a.com"), placement: .inFolder(folder))
        try workspace.openTab(tab("b.com"), placement: .inFolder(folder))
        let removed = workspace.remove(folder)
        #expect(removed.count == 2)
        #expect(workspace.items.isEmpty)
    }

    @Test mutating func `clear today keeps pinned tabs`() throws {
        try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        try workspace.openTab(tab("b.com"), placement: .todayTop(spaceID))
        try workspace.openTab(tab("p.com"), placement: .pinnedEnd(spaceID))
        let removed = workspace.clearToday(in: spaceID)
        #expect(removed.count == 2)
        #expect(titles(.pinned(spaceID), in: workspace) == ["p.com"])
    }

    @Test mutating func `split takes the place of the target`() throws {
        let a = try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        let b = try workspace.openTab(tab("b.com"), placement: .todayTop(spaceID))
        let c = try workspace.openTab(tab("c.com"), placement: .todayTop(spaceID))
        try workspace.split(b, with: a)

        #expect(titles(.today(spaceID), in: workspace) == ["c.com", "split"])
        let split = try #require(workspace.enclosingSplit(of: a))
        #expect(split.split?.layout.panes == [b, a])
        #expect(workspace.selectableItems(in: spaceID).map(\.id) == [c, b, a])

        try workspace.split(a, with: c, axis: .vertical)
        #expect(workspace.enclosingSplit(of: c)?.split?.layout.panes == [b, a, c])
    }

    @Test mutating func `separating the second to last pane dissolves the split`() throws {
        let a = try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        let b = try workspace.openTab(tab("b.com"), placement: .todayTop(spaceID))
        try workspace.split(b, with: a)
        try workspace.separateFromSplit(a)

        #expect(workspace.items.values.contains { $0.kind == .split } == false)
        #expect(titles(.today(spaceID), in: workspace) == ["b.com", "a.com"])
    }

    @Test mutating func `removing A split pane updates the layout`() throws {
        let a = try workspace.openTab(tab("a.com"), placement: .todayTop(spaceID))
        let b = try workspace.openTab(tab("b.com"), placement: .todayTop(spaceID))
        let c = try workspace.openTab(tab("c.com"), placement: .todayTop(spaceID))
        try workspace.split(a, with: b)
        try workspace.split(b, with: c)
        workspace.remove(b)
        #expect(workspace.enclosingSplit(of: a)?.split?.layout.panes == [a, c])
    }

    @Test mutating func `splits reject favorites`() throws {
        let a = try workspace.openTab(tab("a.com"), placement: .favoritesEnd(profileID))
        let b = try workspace.openTab(tab("b.com"), placement: .todayTop(spaceID))
        #expect(throws: WorkspaceError.invalidDestination) { try workspace.split(b, with: a) }
    }

    @Test mutating func `archive candidates respect interval and exclusions`() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = try workspace.openTab(tab("old.com"), placement: .todayTop(spaceID), now: now.addingTimeInterval(-13 * 3600))
        let visible = try workspace.openTab(tab("visible.com"), placement: .todayTop(spaceID), now: now.addingTimeInterval(-13 * 3600))
        try workspace.openTab(tab("fresh.com"), placement: .todayTop(spaceID), now: now.addingTimeInterval(-3600))
        try workspace.openTab(tab("pinned.com"), placement: .pinnedEnd(spaceID), now: now.addingTimeInterval(-48 * 3600))

        let candidates = workspace.archiveCandidates(now: now, interval: .twelveHours, excluding: [visible])
        #expect(candidates.map(\.id) == [old])
        #expect(workspace.archiveCandidates(now: now, interval: .never, excluding: []).isEmpty)
    }

    @Test mutating func `deleting the last space is rejected`() {
        #expect(throws: WorkspaceError.lastSpace) { try workspace.deleteSpace(spaceID) }
    }

    @Test mutating func `deleting A profile reassigns spaces and drops favorites`() throws {
        let work = workspace.addProfile(name: "Work")
        let workSpace = try workspace.addSpace(name: "Work", profileID: work)
        try workspace.openTab(tab("fav.com"), placement: .favoritesEnd(work))
        try workspace.deleteProfile(work, reassigningSpacesTo: profileID)
        #expect(workspace.spaces[workSpace]?.profileID == profileID)
        #expect(workspace.favorites(for: work).isEmpty)
    }

    @Test mutating func `move space reorders spaces`() throws {
        let first = spaceID
        let second = try workspace.addSpace(name: "Second", profileID: profileID)
        try workspace.moveSpace(second, to: 0)
        #expect(workspace.orderedSpaces.map(\.id) == [second, first])
    }

    @Test func `changes diff upserts and deletes`() throws {
        var updated = workspace
        let id = try updated.openTab(tab("a.com"), placement: .todayTop(spaceID))
        let changes = WorkspaceChanges(from: workspace, to: updated)
        #expect(changes.upsertedItems.map(\.id) == [id])
        #expect(changes.deletedItemIDs.isEmpty)

        var removed = updated
        removed.remove(id)
        #expect(WorkspaceChanges(from: updated, to: removed).deletedItemIDs == [id])
        #expect(WorkspaceChanges(from: workspace, to: workspace).isEmpty)
    }
}
