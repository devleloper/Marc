import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI
import UniformTypeIdentifiers

/// Sidebar drags carry the item identifier as text with a private prefix, so that the same drop
/// targets also accept links dragged from web pages and other apps.
enum SidebarDragPayload {
    static let prefix = "marc-sidebar-item:"
    static let types: [UTType] = [.plainText, .url, .fileURL]

    static func provider(for id: SidebarItem.ID) -> NSItemProvider {
        NSItemProvider(object: "\(prefix)\(id.rawValue.uuidString)" as NSString)
    }

    enum Content {
        case item(SidebarItem.ID)
        case url(URL)
    }

    /// Reads the first usable payload from a drop.
    @MainActor
    static func load(from info: DropInfo) async -> Content? {
        if let provider = info.itemProviders(for: [.url]).first,
           let url = await loadURL(from: provider), url.isWebURL || url.isFileURL {
            return .url(url)
        }
        guard let provider = info.itemProviders(for: [.plainText]).first, let text = await loadText(from: provider) else { return nil }
        if text.hasPrefix(prefix), let id = SidebarItem.ID(uuidString: String(text.dropFirst(prefix.count))) {
            return .item(id)
        }
        if case let .url(url) = URLInputClassifier().classify(text), url.isWebURL {
            return .url(url)
        }
        return nil
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: object as? String)
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? NSURL) as URL?)
            }
        }
    }
}

/// Drops onto a fixed destination (end of a section, the favorites grid).
struct SidebarDropDelegate: DropDelegate {
    let window: BrowserWindowModel
    let destination: SidebarDestination
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: SidebarDragPayload.types)
    }

    func dropEntered(info: DropInfo) {
        withAnimation(Motion.hover) { isTargeted = true }
    }

    func dropExited(info: DropInfo) {
        withAnimation(Motion.hover) { isTargeted = false }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let window = window
        let destination = destination
        Task { @MainActor in
            await SidebarDrop.perform(info: info, destination: destination, window: window)
        }
        return true
    }
}

/// Drops onto a row: before or after it, or into it when the row is a folder.
struct RowDropDelegate: DropDelegate {
    enum Position {
        case before
        case after
        case into
    }

    let window: BrowserWindowModel
    let item: SidebarItem
    @Binding var position: Position?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: SidebarDragPayload.types)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let height = Metrics.Sidebar.rowHeight
        let y = info.location.y
        let newPosition: Position = if item.kind == .folder, y > height * 0.25, y < height * 0.75 {
            .into
        } else {
            y < height / 2 ? .before : .after
        }
        if newPosition != position { position = newPosition }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        position = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let resolved = position ?? .after
        position = nil
        let workspace = window.workspace
        // Rows inside a split behave like the split itself.
        let anchor = workspace.enclosingSplit(of: item.id) ?? item
        let destination: SidebarDestination
        switch resolved {
        case .into:
            destination = SidebarDestination(container: anchor.container, parentID: anchor.id, index: .max)
        case .before, .after:
            let siblings = workspace.children(of: anchor.container, parent: anchor.parentID)
            let index = siblings.firstIndex { $0.id == anchor.id } ?? siblings.count
            destination = SidebarDestination(
                container: anchor.container,
                parentID: anchor.parentID,
                index: resolved == .before ? index : index + 1,
            )
        }
        let window = window
        Task { @MainActor in
            await SidebarDrop.perform(info: info, destination: destination, window: window)
        }
        return true
    }
}

enum SidebarDrop {
    @MainActor
    static func perform(info: DropInfo, destination: SidebarDestination, window: BrowserWindowModel) async {
        guard let payload = await SidebarDragPayload.load(from: info) else { return }
        switch payload {
        case let .item(id):
            guard window.workspace.items[id] != nil else { return }
            var adjusted = destination
            // Indices are computed with the moved item still present; compensate when it moves
            // down within the same parent.
            let siblings = window.workspace.children(of: destination.container, parent: destination.parentID)
            if let current = siblings.firstIndex(where: { $0.id == id }), current < destination.index {
                adjusted.index -= 1
            }
            withAnimation(Motion.listChange) {
                do {
                    try window.store.update { try $0.move(id, to: adjusted) }
                } catch {
                    NSSound.beep()
                }
            }
        case let .url(url):
            guard let itemID = try? window.store.update({ try $0.openTab(TabContent(url: url), placement: .destination(destination)) })
            else { return }
            window.runtimeTab(for: itemID)?.load(url, initiator: .user, transition: .link)
            window.select(itemID)
        }
    }
}
