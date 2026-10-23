import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Library button, Space switcher and the `+` menu.
struct SidebarFooter: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            LibraryButton(window: window)
            Spacer(minLength: 0)
            if window.kind == .standard {
                SpaceSwitcher(window: window)
            } else {
                Text(window.kind == .incognito ? "Incognito" : "This Window")
                    .font(Typography.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 0)
            if window.kind == .standard {
                PlusMenu(window: window)
            } else {
                Color.clear.frame(width: Metrics.Sidebar.toolbarButtonSize)
            }
        }
        .padding(.horizontal, Metrics.Sidebar.inset)
        .frame(height: Metrics.Sidebar.footerHeight)
    }
}

private struct LibraryButton: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        let downloads = window.session?.downloads
        ZStack {
            IconButton(window.isShowingLibrary ? "books.vertical.fill" : "books.vertical", label: "Library") {
                window.isShowingLibrary.toggle()
            }
            if let downloads, downloads.activeCount > 0 {
                ProgressRing(fraction: downloads.overallProgress)
                    .frame(width: 26, height: 26)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityIdentifier("libraryButton")
    }
}

/// A row of Space icons; the current Space is emphasized. Accepts dropped tabs.
private struct SpaceSwitcher: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        let spaces = window.workspace.orderedSpaces
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                SpaceIconButton(window: window, space: space, isCurrent: space.id == window.state.spaceID, isCompact: spaces.count > 6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}

private struct SpaceIconButton: View {
    @Bindable var window: BrowserWindowModel
    let space: Space
    let isCurrent: Bool
    let isCompact: Bool
    @State private var isHovered = false
    @State private var isDropTargeted = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button { window.switchSpace(to: space.id) } label: {
            icon
                .frame(width: isCompact ? 21 : 24, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { isHovered = $0 }
        .help(space.name)
        .accessibilityLabel(space.name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .onDrop(of: SidebarDragPayload.types, delegate: SidebarDropDelegate(
            window: window,
            destination: SidebarDestination(container: .today(space.id), index: 0),
            isTargeted: $isDropTargeted,
        ))
        .onChange(of: window.dropHighlightResets) { isDropTargeted = false }
        .contextMenu {
            Button("Rename Space") {
                window.switchSpace(to: space.id)
                window.renamingSpaceID = space.id
            }
            Button("Edit Theme…") { window.editingThemeSpaceID = space.id }
            ProfileMenu(window: window, space: space)
        }
    }

    @ViewBuilder private var icon: some View {
        let opacity = isCurrent ? 1.0 : isHovered || isDropTargeted ? 0.75 : 0.45
        switch space.icon {
        case let .emoji(emoji):
            Text(emoji)
                .font(.system(size: 14))
                .opacity(isCurrent ? 1 : 0.6)
                .scaleEffect(isDropTargeted ? 1.3 : 1)
        case let .symbol(symbol):
            if symbol == "circle.fill" {
                Circle()
                    .fill(palette.primaryText.opacity(opacity))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isDropTargeted ? 1.6 : 1)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.primaryText.opacity(opacity))
                    .scaleEffect(isDropTargeted ? 1.3 : 1)
            }
        }
    }
}

/// "Change Profile" submenu for a Space.
struct ProfileMenu: View {
    let window: BrowserWindowModel
    let space: Space

    var body: some View {
        let profiles = window.workspace.orderedProfiles
        if profiles.count > 1 {
            Menu("Profile") {
                ForEach(profiles) { profile in
                    Button {
                        try? window.store.update { try $0.updateSpace(space.id) { $0.profileID = profile.id } }
                    } label: {
                        if profile.id == space.profileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }
        }
    }
}

/// The footer's `+`: New Space, New Folder, New Note, New Boost, New Split, New Tab.
private struct PlusMenu: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        Menu {
            Button { window.perform(.newSpace) } label: { Label("New Space", systemImage: "plus.rectangle.on.rectangle") }
            Button { window.perform(.newFolder) } label: { Label("New Folder", systemImage: "folder.badge.plus") }
            Divider()
            Button { window.perform(.newNote) } label: { Label("New Note", systemImage: "note.text.badge.plus") }
            Button { window.perform(.boostSite) } label: { Label("New Boost", systemImage: "paintbrush.pointed") }
                .disabled(!window.canPerform(.boostSite))
            Divider()
            Button { window.perform(.addSplit) } label: { Label("New Split", systemImage: "rectangle.split.2x1") }
                .disabled(!window.canPerform(.addSplit))
            Button { window.perform(.newTab) } label: { Label("New Tab", systemImage: "plus.square") }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.pressable)
        .menuIndicator(.hidden)
        .frame(width: Metrics.Sidebar.toolbarButtonSize, height: Metrics.Sidebar.toolbarButtonSize)
        .foregroundStyle(window.palette.icon)
        .help("New…")
        .accessibilityIdentifier("plusMenu")
    }
}
