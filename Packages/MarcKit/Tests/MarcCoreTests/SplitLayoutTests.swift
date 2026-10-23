import Foundation
import Testing
@testable import MarcCore

struct SplitLayoutTests {
    let a = SidebarItem.ID()
    let b = SidebarItem.ID()
    let c = SidebarItem.ID()
    let d = SidebarItem.ID()
    let e = SidebarItem.ID()

    func rootGroup(_ layout: SplitLayout) throws -> SplitLayout.Group {
        guard case let .group(group) = layout.root else { throw SplitLayout.Error.paneNotFound }
        return group
    }

    @Test func `starts with equal fractions`() throws {
        let layout = SplitLayout(panes: [a, b, c])
        let group = try rootGroup(layout)
        #expect(group.fractions.allSatisfy { abs($0 - 1.0 / 3) < 0.0001 })
        #expect(layout.panes == [a, b, c])
    }

    @Test func `inserting along the same axis joins the group`() throws {
        var layout = SplitLayout(panes: [a, b])
        try layout.insert(c, adjacentTo: a, axis: .horizontal)
        #expect(layout.panes == [a, c, b])
        let group = try rootGroup(layout)
        #expect(group.children.count == 3)
    }

    @Test func `inserting along the other axis nests a group`() throws {
        var layout = SplitLayout(panes: [a, b])
        try layout.insert(c, adjacentTo: b, axis: .vertical, after: false)
        #expect(layout.panes == [a, c, b])
        guard case let .group(root) = layout.root, case let .group(nested) = root.children[1] else {
            Issue.record("expected nested group")
            return
        }
        #expect(nested.axis == .vertical)
    }

    @Test func `limits panes to four`() throws {
        var layout = SplitLayout(panes: [a, b, c, d])
        #expect(throws: SplitLayout.Error.tooManyPanes) { try layout.insert(e, adjacentTo: a, axis: .horizontal) }
    }

    @Test func `rejects duplicates and unknown targets`() throws {
        var layout = SplitLayout(panes: [a, b])
        #expect(throws: SplitLayout.Error.duplicatePane) { try layout.insert(b, adjacentTo: a, axis: .horizontal) }
        #expect(throws: SplitLayout.Error.paneNotFound) { try layout.insert(c, adjacentTo: d, axis: .horizontal) }
    }

    @Test func `removing collapses single child groups`() throws {
        var layout = SplitLayout(panes: [a, b])
        try layout.insert(c, adjacentTo: b, axis: .vertical)
        let removed = try #require(layout.removing(c))
        #expect(removed.panes == [a, b])
        let root = try rootGroup(removed)
        #expect(root.children == [.pane(a), .pane(b)])
        #expect(abs(root.fractions.reduce(0, +) - 1) < 0.0001)
    }

    @Test func `removing down to one pane dissolves`() {
        #expect(SplitLayout(panes: [a, b]).removing(a) == nil)
    }

    @Test func `resizing clamps to minimum fraction`() throws {
        var layout = SplitLayout(panes: [a, b])
        layout.resizeDivider(groupPath: [], index: 0, fraction: 0.01)
        let group = try rootGroup(layout)
        #expect(abs(group.fractions[0] - SplitLayout.minimumFraction) < 0.0001)
        #expect(abs(group.fractions.reduce(0, +) - 1) < 0.0001)
    }

    @Test func `swap and replace keep structure`() throws {
        var layout = SplitLayout(panes: [a, b, c])
        try layout.swap(a, c)
        #expect(layout.panes == [c, b, a])
        try layout.replace(b, with: d)
        #expect(layout.panes == [c, d, a])
    }

    @Test func `round trips through codable`() throws {
        var layout = SplitLayout(panes: [a, b])
        try layout.insert(c, adjacentTo: a, axis: .vertical)
        let data = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(SplitLayout.self, from: data) == layout)
    }
}
