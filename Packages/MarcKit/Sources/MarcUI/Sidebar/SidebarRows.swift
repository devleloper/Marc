import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Renders a sidebar item and, for expanded folders, its children.
struct SidebarNode: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    let depth: Int

    var body: some View {
        VStack(spacing: Metrics.Sidebar.rowSpacing) {
            row
                .padding(.leading, CGFloat(depth) * Metrics.Sidebar.nestingIndent)
            if case let .folder(folder) = item.content, folder.isExpanded {
                ForEach(window.workspace.children(of: item.id)) { child in
                    SidebarNode(window: window, item: child, depth: depth + 1)
                }
            }
        }
    }

    @ViewBuilder private var row: some View {
        switch item.content {
        case .tab: TabRow(window: window, item: item)
        case .folder: FolderRow(window: window, item: item)
        case .split: SplitRow(window: window, item: item)
        case .note: NoteRow(window: window, item: item)
        }
    }
}

/// Shared chrome for sidebar rows: hover/selection fill, drag source, drop target and menu.
private struct RowContainer<Content: View>: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: (_ isHovered: Bool) -> Content

    @State private var isHovered = false
    @State private var dropPosition: RowDropDelegate.Position?

    var body: some View {
        content(isHovered)
            .frame(height: Metrics.Sidebar.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rowBackground(isSelected: isSelected, isHovered: isHovered || dropPosition == .into)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.Sidebar.rowCornerRadius, style: .continuous))
            .onTapGesture(perform: action)
            .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
            .onDrag { SidebarDragPayload.provider(for: item.id) }
            .onDrop(of: SidebarDragPayload.types, delegate: RowDropDelegate(window: window, item: item, position: $dropPosition))
            .overlay(alignment: dropPosition == .after ? .bottom : .top) {
                if dropPosition == .before || dropPosition == .after {
                    DropIndicatorLine().offset(y: dropPosition == .before ? -3.5 : 3.5)
                }
            }
            .contextMenu { SidebarItemMenu(window: window, item: item) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct TabRow: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    @Environment(\.themePalette) private var palette

    var body: some View {
        let runtime = window.session?.runtime.tab(for: item.id)
        let content = item.tab ?? TabContent(url: nil)
        let isSelected = window.selectedItemID == item.id
        RowContainer(window: window, item: item, isSelected: isSelected, action: { window.select(item.id) }) { isHovered in
            HStack(spacing: Metrics.Sidebar.titleLeading) {
                FaviconView(
                    image: runtime?.favicon ?? favicon(for: content),
                    fallbackTitle: content.displayTitle,
                    isLoading: runtime?.isLoading == true && runtime?.favicon == nil,
                )
                RowTitle(window: window, item: item, title: title(for: content, runtime: runtime))
                    .foregroundStyle(isUnloadedPinned(runtime) ? palette.secondaryText : palette.primaryText)
                Spacer(minLength: 0)
                if let runtime, runtime.media.isPlaying || runtime.media.isMuted {
                    IconButton(
                        runtime.media.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        label: runtime.media.isMuted ? "Unmute" : "Mute",
                        size: 22,
                        symbolSize: 11,
                    ) {
                        runtime.setMuted(!runtime.media.isMuted)
                    }
                }
                if isHovered {
                    if item.tab?.hasLeftHome == true {
                        IconButton("arrow.uturn.backward", label: "Back to Pinned URL", size: 22, symbolSize: 11) {
                            window.select(item.id)
                            window.perform(.resetPinnedTab)
                        }
                    }
                    IconButton("xmark", label: item.container.section == .today ? "Archive Tab" : "Close Tab", size: 22, symbolSize: 11) {
                        close()
                    }
                    .transition(.opacity)
                }
            }
            .padding(.leading, Metrics.Sidebar.iconLeading)
            .padding(.trailing, 6)
        }
        .accessibilityLabel(content.displayTitle.isEmpty ? "Tab" : content.displayTitle)
        .accessibilityIdentifier("tabRow")
    }

    private func title(for content: TabContent, runtime: WebTab?) -> String {
        if let custom = content.customTitle, !custom.isEmpty { return custom }
        if let page = internalPage(for: content) { return page.title }
        if let title = runtime?.title, !title.isEmpty { return title }
        if !content.title.isEmpty { return content.title }
        return content.url?.displayHost ?? "New Tab"
    }

    private func internalPage(for content: TabContent) -> InternalPage? {
        content.url.flatMap(InternalPage.init(url:))
    }

    private func favicon(for content: TabContent) -> NSImage? {
        if let page = internalPage(for: content) {
            return NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(
                pointSize: 13,
                weight: .medium,
            ))
        }
        return content.faviconURL.flatMap { window.session?.engine.favicons.cachedImage(for: $0) }
    }

    private func isUnloadedPinned(_ runtime: WebTab?) -> Bool {
        item.container.section != .today && runtime?.hasWebView != true
    }

    private func close() {
        if window.selectedItemID == item.id {
            window.closeSelected()
        } else if item.container.section == .today {
            window.session?.archive([item.id], from: window)
        } else {
            window.session?.runtime.unload(item.id)
        }
    }
}

/// A title that turns into a text field while renaming.
private struct RowTitle: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    let title: String
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if window.renamingItemID == item.id {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(Typography.tabTitle)
                .focused($isFocused)
                .onSubmit(commit)
                .onExitCommand { window.renamingItemID = nil }
                .focusOnAppear($isFocused)
                .onAppear { draft = title }
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
        } else {
            Text(title)
                .font(Typography.tabTitle)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func commit() {
        guard window.renamingItemID == item.id else { return }
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        window.renamingItemID = nil
        switch item.content {
        case .folder:
            if !name.isEmpty { try? window.store.update { try $0.renameFolder(item.id, to: name) } }
        case .tab:
            try? window.store.update { try $0.updateTab(item.id) { $0.customTitle = name.isEmpty ? nil : name } }
        case let .note(noteID):
            if let note = window.session?.notes.notes[noteID] {
                window.session?.notes.update(noteID, title: name, content: note.content)
            }
        case .split:
            break
        }
    }
}

struct FolderRow: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    @Environment(\.themePalette) private var palette

    var body: some View {
        let folder = item.folder ?? FolderContent(name: "")
        RowContainer(window: window, item: item, isSelected: false, action: toggle) { _ in
            HStack(spacing: Metrics.Sidebar.titleLeading) {
                Image(systemName: folder.isExpanded ? "folder" : "folder.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.icon)
                    .frame(width: Metrics.Sidebar.iconSize)
                RowTitle(window: window, item: item, title: folder.name)
                    .foregroundStyle(palette.primaryText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.tertiaryText)
                    .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                    .padding(.trailing, 10)
            }
            .padding(.leading, Metrics.Sidebar.iconLeading)
        }
        .accessibilityLabel("\(folder.name) folder, \(folder.isExpanded ? "expanded" : "collapsed")")
    }

    private func toggle() {
        guard let folder = item.folder else { return }
        withAnimation(Motion.listChange) {
            try? window.store.update { try $0.setFolderExpanded(item.id, !folder.isExpanded) }
        }
    }
}

/// A split shown as one row with a segment per pane.
struct SplitRow: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    @Environment(\.themePalette) private var palette

    var body: some View {
        let panes = item.split?.layout.panes ?? []
        let isSelected = panes.contains { $0 == window.selectedItemID }
        RowContainer(window: window, item: item, isSelected: isSelected, action: { window.select(panes.first) }) { _ in
            HStack(spacing: 0) {
                ForEach(Array(panes.enumerated()), id: \.element) { index, paneID in
                    if index > 0 {
                        Rectangle().fill(palette.separator).frame(width: 1, height: 18)
                    }
                    SplitSegment(window: window, paneID: paneID)
                }
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel("Split view with \(panes.count) tabs")
    }
}

private struct SplitSegment: View {
    @Bindable var window: BrowserWindowModel
    let paneID: SidebarItem.ID
    @Environment(\.themePalette) private var palette

    var body: some View {
        let content = window.workspace.items[paneID]?.tab
        let runtime = window.session?.runtime.tab(for: paneID)
        let isFocused = window.selectedItemID == paneID
        HStack(spacing: 6) {
            FaviconView(
                image: runtime?.favicon ?? content?.faviconURL.flatMap { window.session?.engine.favicons.cachedImage(for: $0) },
                fallbackTitle: content?.displayTitle ?? "",
            )
            Text(runtime?.title.isEmpty == false ? runtime!.title : content?.displayTitle ?? "")
                .font(.system(size: 12, weight: isFocused ? .semibold : .medium))
                .foregroundStyle(isFocused ? palette.primaryText : palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { window.select(paneID) }
    }
}

struct NoteRow: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    @Environment(\.themePalette) private var palette

    var body: some View {
        let note: Note? = if case let .note(id) = item.content {
            window.session?.notes.notes[id]
        } else {
            nil
        }
        RowContainer(
            window: window,
            item: item,
            isSelected: window.selectedItemID == item.id,
            action: { window.select(item.id) },
        ) { isHovered in
            HStack(spacing: Metrics.Sidebar.titleLeading) {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.icon)
                    .frame(width: Metrics.Sidebar.iconSize)
                Text(note?.displayTitle ?? "Untitled Note")
                    .font(Typography.tabTitle)
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isHovered {
                    IconButton("xmark", label: "Archive Note", size: 22, symbolSize: 11) {
                        window.session?.archive([item.id], from: window)
                    }
                }
            }
            .padding(.leading, Metrics.Sidebar.iconLeading)
            .padding(.trailing, 6)
        }
        .accessibilityLabel(note?.displayTitle ?? "Note")
    }
}
