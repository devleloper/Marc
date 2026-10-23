import Foundation

/// Chooses what a window shows after its selected item goes away.
public enum SelectionPolicy {
    /// Arc keeps the position: it selects the item that took the removed item's place, or the
    /// previous one when the removed item was last.
    public static func replacement(
        forRemoved removedID: SidebarItem.ID,
        orderBeforeRemoval: [SidebarItem.ID],
        remaining: [SidebarItem.ID],
    ) -> SidebarItem.ID? {
        guard !remaining.isEmpty else { return nil }
        let remainingSet = Set(remaining)
        guard let index = orderBeforeRemoval.firstIndex(of: removedID) else { return remaining.first }
        let after = orderBeforeRemoval[orderBeforeRemoval.index(after: index)...].first { remainingSet.contains($0) }
        let before = orderBeforeRemoval[..<index].last { remainingSet.contains($0) }
        return after ?? before
    }

    /// The item `offset` positions away from `current`, wrapping around.
    public static func neighbor(of current: SidebarItem.ID?, offset: Int, in order: [SidebarItem.ID]) -> SidebarItem.ID? {
        guard !order.isEmpty else { return nil }
        guard let current, let index = order.firstIndex(of: current) else { return order.first }
        let count = order.count
        return order[((index + offset) % count + count) % count]
    }
}
