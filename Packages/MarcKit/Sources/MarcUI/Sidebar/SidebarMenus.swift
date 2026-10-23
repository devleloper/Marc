import AppKit
import MarcCore
import MarcWebKit
import SwiftUI

/// Context menu of a sidebar item.
struct SidebarItemMenu: View {
    let window: BrowserWindowModel
    let item: SidebarItem

    var body: some View {
        switch item.content {
        case let .tab(tab): tabItems(tab)
        case .folder: folderItems
        case .split: splitItems
        case .note: noteItems
        }
    }

    @ViewBuilder
    private func tabItems(_ tab: TabContent) -> some View {
        let runtime = window.session?.runtime.tab(for: item.id)
        if let url = tab.url {
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                window.showToast("Copied Link", symbol: "link")
            }
        }
        Divider()
        Button("Rename…") { window.renamingItemID = item.id }
        if let runtime, runtime.media.hasMedia {
            Button(runtime.media.isMuted ? "Unmute" : "Mute") { runtime.setMuted(!runtime.media.isMuted) }
        }
        if tab.url?.isWebURL == true, window.isPersistent {
            Button("Customize Page…") {
                window.select(item.id)
                window.perform(.boostSite)
            }
        }
        Divider()
        splitItemsForTab
        if window.isPersistent {
            organizingItems(tab)
        }
        Divider()
        closingItems(runtime: runtime)
    }

    @ViewBuilder private var splitItemsForTab: some View {
        if let selected = window.selectedItemID, selected != item.id, window.workspace.items[selected]?.kind == .tab,
           item.container.section != .favorites, window.workspace.items[selected]?.container.section != .favorites {
            Button("Open in Split View") {
                try? window.store.update { try $0.split(selected, with: item.id) }
                window.select(item.id)
            }
        }
        if window.workspace.enclosingSplit(of: item.id) != nil {
            Button("Separate from Split View") { try? window.store.update { try $0.separateFromSplit(item.id) } }
        }
    }

    @ViewBuilder
    private func organizingItems(_ tab: TabContent) -> some View {
        Button("Duplicate") {
            if let id = try? window.store.update({ try $0.duplicateTab(item.id) }) { window.select(id) }
        }
        MoveToSpaceMenu(window: window, item: item)
        Divider()
        switch item.container.section {
        case .today:
            Button("Pin Tab") { try? window.store.update { try $0.pin(item.id) } }
            Button("Add to Favorites") { try? window.store.update { try $0.addToFavorites(item.id) } }
        case .pinned:
            Button("Unpin Tab", action: moveToToday)
            Button("Add to Favorites") { try? window.store.update { try $0.addToFavorites(item.id) } }
        case .favorites:
            Button("Remove from Favorites", action: moveToToday)
        }
        if tab.hasLeftHome {
            Button("Back to Pinned URL") {
                window.select(item.id)
                window.perform(.resetPinnedTab)
            }
        }
    }

    @ViewBuilder
    private func closingItems(runtime: WebTab?) -> some View {
        if item.container.section == .today {
            Button("Archive Tab") { window.session?.archive([item.id], from: window) }
            Button("Archive Tabs Below") { archiveBelow() }
                .disabled(tabsBelow.isEmpty)
        } else {
            Button("Close Tab") { window.session?.runtime.unload(item.id) }
                .disabled(runtime?.hasWebView != true)
            Button("Delete") { window.session?.archive([item.id], from: window) }
        }
    }

    private func moveToToday() {
        guard let space = window.state.spaceID else { return }
        try? window.store.update { try $0.unpin(item.id, into: space) }
    }

    private func toggleFolder(_ folder: FolderContent) {
        try? window.store.update { try $0.setFolderExpanded(item.id, !folder.isExpanded) }
    }

    @ViewBuilder private var folderItems: some View {
        Button("Rename…") { window.renamingItemID = item.id }
        if let folder = item.folder {
            Button(folder.isExpanded ? "Collapse" : "Expand") { toggleFolder(folder) }
        }
        Button("New Folder Inside") {
            let id = try? window.store.update {
                try $0.createFolder(named: "New Folder", at: SidebarDestination(container: item.container, parentID: item.id, index: .max))
            }
            window.renamingItemID = id
        }
        MoveToSpaceMenu(window: window, item: item)
        Divider()
        Button("Delete Folder and Its Tabs", role: .destructive) { window.session?.archive([item.id], from: window) }
    }

    @ViewBuilder private var splitItems: some View {
        if let panes = item.split?.layout.panes {
            Button("Separate All Tabs") {
                for pane in panes.dropFirst() {
                    try? window.store.update { try $0.separateFromSplit(pane) }
                }
            }
        }
        if item.container.section == .today, window.isPersistent {
            Button("Pin Split") { try? window.store.update { try $0.pin(item.id) } }
        }
        Divider()
        Button("Archive Split") { window.session?.archive([item.id], from: window) }
    }

    @ViewBuilder private var noteItems: some View {
        Button("Open") { window.select(item.id) }
        if window.isPersistent {
            MoveToSpaceMenu(window: window, item: item)
            if item.container.section == .today {
                Button("Pin Note") { try? window.store.update { try $0.pin(item.id) } }
            } else if let space = window.state.spaceID {
                Button("Unpin Note") { try? window.store.update { try $0.unpin(item.id, into: space) } }
            }
        }
        Divider()
        Button("Archive Note") { window.session?.archive([item.id], from: window) }
    }

    private var tabsBelow: [SidebarItem.ID] {
        let siblings = window.workspace.children(of: item.container, parent: item.parentID)
        guard let index = siblings.firstIndex(where: { $0.id == item.id }) else { return [] }
        return siblings[(index + 1)...].map(\.id)
    }

    private func archiveBelow() {
        window.session?.archive(tabsBelow, from: window)
    }
}

/// "Move to ▸" submenu listing the other Spaces.
struct MoveToSpaceMenu: View {
    let window: BrowserWindowModel
    let item: SidebarItem

    var body: some View {
        let spaces = window.workspace.orderedSpaces.filter { $0.id != item.container.spaceID }
        if !spaces.isEmpty {
            Menu("Move to") {
                ForEach(spaces) { space in
                    Button(space.name) {
                        let target = window.workspace.enclosingSplit(of: item.id) ?? item
                        let container: SidebarContainer = item.container.section == .pinned ? .pinned(space.id) : .today(space.id)
                        try? window.store.update { try $0.move(target.id, to: SidebarDestination(container: container, index: 0)) }
                    }
                }
            }
        }
    }
}

/// Menu for a Space's header and empty area.
struct SpaceBackgroundMenu: View {
    let window: BrowserWindowModel
    let space: Space

    var body: some View {
        Button("New Tab") { window.showCommandBar(.newTab) }
        if window.isPersistent {
            Button("New Folder") { window.perform(.newFolder) }
            Button("New Note") { window.perform(.newNote) }
            Divider()
            Button("Rename Space") { window.renamingSpaceID = space.id }
            Button("Edit Theme…") { window.editingThemeSpaceID = space.id }
            if window.workspace.spaces.count > 1 {
                Button("Delete Space", role: .destructive) { confirmDelete() }
            }
        }
        Divider()
        Button("Clear Today") { window.clearToday() }
    }

    private func confirmDelete() {
        guard let nsWindow = window.nsWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Delete “\(space.name)”?"
        alert.informativeText = "Its pinned and Today tabs will be archived."
        alert.addButton(withTitle: "Delete Space")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: nsWindow) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in window.deleteSpace(space.id) }
        }
    }
}
