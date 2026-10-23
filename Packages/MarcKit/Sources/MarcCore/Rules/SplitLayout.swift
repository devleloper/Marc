import Foundation

/// The arrangement of tabs inside a split view, modeled as a tree of groups. Each group lays out
/// its children along one axis with relative fractions that always sum to 1.
public struct SplitLayout: Hashable, Sendable, Codable {
    public static let maximumPanes = 4
    public static let minimumFraction = 0.15

    public enum Axis: String, Hashable, Sendable, Codable {
        /// Children side by side.
        case horizontal
        /// Children stacked top to bottom.
        case vertical
    }

    public indirect enum Node: Hashable, Sendable, Codable {
        case pane(SidebarItem.ID)
        case group(Group)
    }

    public struct Group: Hashable, Sendable, Codable {
        public var axis: Axis
        public var children: [Node]
        public var fractions: [Double]

        init(axis: Axis, children: [Node]) {
            self.axis = axis
            self.children = children
            fractions = Array(repeating: 1 / Double(children.count), count: children.count)
        }
    }

    public enum Error: Swift.Error, Equatable {
        case tooManyPanes
        case paneNotFound
        case duplicatePane
    }

    public private(set) var root: Node

    public init(panes: [SidebarItem.ID], axis: Axis = .horizontal) {
        precondition(panes.count >= 2 && panes.count <= Self.maximumPanes, "A split holds 2...4 panes")
        root = .group(Group(axis: axis, children: panes.map(Node.pane)))
    }

    init(root: Node) {
        self.root = root
    }

    /// Panes in reading order.
    public var panes: [SidebarItem.ID] {
        Self.collectPanes(root)
    }

    public func contains(_ pane: SidebarItem.ID) -> Bool {
        panes.contains(pane)
    }

    /// Inserts `pane` next to `target`. When the target's group already runs along `axis` the new
    /// pane joins that group; otherwise the target is replaced by a new group.
    public mutating func insert(
        _ pane: SidebarItem.ID,
        adjacentTo target: SidebarItem.ID,
        axis: Axis,
        after: Bool = true,
    ) throws {
        guard panes.count < Self.maximumPanes else { throw Error.tooManyPanes }
        guard !contains(pane) else { throw Error.duplicatePane }
        guard let newRoot = Self.inserting(pane, adjacentTo: target, axis: axis, after: after, in: root) else {
            throw Error.paneNotFound
        }
        root = newRoot
    }

    /// Removes `pane`. Returns `nil` when fewer than two panes would remain, signalling that the
    /// split should be dissolved.
    public func removing(_ pane: SidebarItem.ID) -> SplitLayout? {
        guard contains(pane), let newRoot = Self.removing(pane, from: root), case .group = newRoot else { return nil }
        return SplitLayout(root: newRoot)
    }

    public mutating func replace(_ pane: SidebarItem.ID, with replacement: SidebarItem.ID) throws {
        guard contains(pane) else { throw Error.paneNotFound }
        guard !contains(replacement) else { throw Error.duplicatePane }
        root = Self.mapPanes(root) { $0 == pane ? replacement : $0 }
    }

    public mutating func swap(_ first: SidebarItem.ID, _ second: SidebarItem.ID) throws {
        guard contains(first), contains(second) else { throw Error.paneNotFound }
        root = Self.mapPanes(root) { id in
            if id == first { return second }
            if id == second { return first }
            return id
        }
    }

    /// Moves the divider between child `index` and `index + 1` of the group at `path` so that the
    /// child at `index` takes `fraction` of the pair's combined space.
    public mutating func resizeDivider(groupPath path: [Int], index: Int, fraction: Double) {
        root = Self.updatingGroup(at: path[...], in: root) { group in
            guard group.children.indices.contains(index + 1) else { return }
            let pair = group.fractions[index] + group.fractions[index + 1]
            let minimum = Self.minimumFraction * pair
            let leading = min(max(fraction * pair, minimum), pair - minimum)
            group.fractions[index] = leading
            group.fractions[index + 1] = pair - leading
        }
    }

    /// Resets every group to equal fractions.
    public mutating func equalize() {
        root = Self.equalized(root)
    }

    // MARK: - Tree operations

    private static func collectPanes(_ node: Node) -> [SidebarItem.ID] {
        switch node {
        case let .pane(id): [id]
        case let .group(group): group.children.flatMap(collectPanes)
        }
    }

    private static func inserting(
        _ pane: SidebarItem.ID,
        adjacentTo target: SidebarItem.ID,
        axis: Axis,
        after: Bool,
        in node: Node,
    ) -> Node? {
        switch node {
        case let .pane(id):
            guard id == target else { return nil }
            let children: [Node] = after ? [.pane(id), .pane(pane)] : [.pane(pane), .pane(id)]
            return .group(Group(axis: axis, children: children))
        case var .group(group):
            for (index, child) in group.children.enumerated() {
                if case .pane(target) = child, group.axis == axis {
                    let insertionIndex = after ? index + 1 : index
                    group.children.insert(.pane(pane), at: insertionIndex)
                    group.fractions = Array(repeating: 1 / Double(group.children.count), count: group.children.count)
                    return .group(group)
                }
                if let replaced = inserting(pane, adjacentTo: target, axis: axis, after: after, in: child) {
                    group.children[index] = replaced
                    return .group(group)
                }
            }
            return nil
        }
    }

    private static func removing(_ pane: SidebarItem.ID, from node: Node) -> Node? {
        switch node {
        case let .pane(id):
            return id == pane ? nil : node
        case var .group(group):
            var children: [Node] = []
            var fractions: [Double] = []
            for (child, fraction) in zip(group.children, group.fractions) {
                if let remaining = removing(pane, from: child) {
                    children.append(remaining)
                    fractions.append(fraction)
                }
            }
            if children.isEmpty { return nil }
            if children.count == 1 { return children[0] }
            let total = fractions.reduce(0, +)
            group.children = children
            group.fractions = fractions.map { $0 / total }
            return .group(group)
        }
    }

    private static func mapPanes(_ node: Node, _ transform: (SidebarItem.ID) -> SidebarItem.ID) -> Node {
        switch node {
        case let .pane(id):
            return .pane(transform(id))
        case var .group(group):
            group.children = group.children.map { mapPanes($0, transform) }
            return .group(group)
        }
    }

    private static func updatingGroup(at path: ArraySlice<Int>, in node: Node, _ update: (inout Group) -> Void) -> Node {
        guard case var .group(group) = node else { return node }
        if let first = path.first {
            guard group.children.indices.contains(first) else { return node }
            group.children[first] = updatingGroup(at: path.dropFirst(), in: group.children[first], update)
        } else {
            update(&group)
        }
        return .group(group)
    }

    private static func equalized(_ node: Node) -> Node {
        guard case var .group(group) = node else { return node }
        group.children = group.children.map(equalized)
        group.fractions = Array(repeating: 1 / Double(group.children.count), count: group.children.count)
        return .group(group)
    }
}
