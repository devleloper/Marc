import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// One Space in the sidebar: header, pinned tree, the Today divider, "New Tab" and Today tabs.
struct SpacePageView: View {
    @Bindable var window: BrowserWindowModel
    let space: Space
    @State private var isHovered = false
    @State private var pinnedDropTargeted = false
    @State private var todayDropTargeted = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        let pinned = window.workspace.children(of: .pinned(space.id))
        let today = window.workspace.children(of: .today(space.id))
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                SpaceHeader(window: window, space: space)

                LazyVStack(spacing: Metrics.Sidebar.rowSpacing) {
                    ForEach(pinned) { item in
                        SidebarNode(window: window, item: item, depth: 0)
                    }
                }
                .animation(Motion.listChange, value: pinned.map(\.id))

                if window.kind == .standard {
                    TodayDivider(isSidebarHovered: isHovered, isEmpty: today.isEmpty) { window.clearToday() }
                        .onDrop(of: SidebarDragPayload.types, delegate: SidebarDropDelegate(
                            window: window,
                            destination: SidebarDestination(container: .pinned(space.id), index: pinned.count),
                            isTargeted: $pinnedDropTargeted,
                        ))
                        .overlay(alignment: .top) {
                            if pinnedDropTargeted { DropIndicatorLine() }
                        }
                }

                NewTabRow { window.showCommandBar(.newTab) }
                    .padding(.bottom, Metrics.Sidebar.rowSpacing)

                LazyVStack(spacing: Metrics.Sidebar.rowSpacing) {
                    ForEach(today) { item in
                        SidebarNode(window: window, item: item, depth: 0)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(Motion.listChange, value: today.map(\.id))

                // The remaining space accepts drops at the end of Today.
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .contentShape(Rectangle())
                    .onDrop(of: SidebarDragPayload.types, delegate: SidebarDropDelegate(
                        window: window,
                        destination: SidebarDestination(container: .today(space.id), index: today.count),
                        isTargeted: $todayDropTargeted,
                    ))
                    .overlay(alignment: .top) {
                        if todayDropTargeted { DropIndicatorLine() }
                    }
                    .contextMenu { SpaceBackgroundMenu(window: window, space: space) }
            }
            .padding(.horizontal, Metrics.Sidebar.inset)
        }
        .scrollIndicators(.never)
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(space.name) Space")
    }
}

struct SpaceHeader: View {
    @Bindable var window: BrowserWindowModel
    let space: Space
    @State private var draftName = ""
    @FocusState private var isEditing: Bool
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            if case let .emoji(emoji) = space.icon {
                Text(emoji).font(.system(size: 12))
            }
            if window.renamingSpaceID == space.id {
                TextField("Space Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(palette.primaryText)
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onExitCommand { window.renamingSpaceID = nil }
                    .focusOnAppear($isEditing)
                    .onAppear { draftName = space.name }
                    .onChange(of: isEditing) { _, editing in if !editing { commit() } }
            } else {
                Text(space.name)
                    .font(Typography.sectionHeader)
                    .foregroundStyle(palette.secondaryText.opacity(0.9))
                    .lineLimit(1)
                    .onTapGesture(count: 2) { window.renamingSpaceID = space.id }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .frame(height: 30)
        .contextMenu { SpaceBackgroundMenu(window: window, space: space) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("spaceHeader")
        .popover(isPresented: isEditingTheme, arrowEdge: .trailing) {
            ThemeEditor(theme: themeBinding)
        }
    }

    private var isEditingTheme: Binding<Bool> {
        Binding(
            get: { window.editingThemeSpaceID == space.id },
            set: { if !$0 { window.editingThemeSpaceID = nil } },
        )
    }

    private var themeBinding: Binding<Theme> {
        Binding(
            get: { window.workspace.spaces[space.id]?.theme ?? space.theme },
            set: { newTheme in try? window.store.update { try $0.updateSpace(space.id) { $0.theme = newTheme } } },
        )
    }

    private func commit() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { try? window.store.update { try $0.updateSpace(space.id) { $0.name = name } } }
        window.renamingSpaceID = nil
    }
}

struct TodayDivider: View {
    let isSidebarHovered: Bool
    let isEmpty: Bool
    let clear: () -> Void
    @State private var isClearHovered = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(palette.separator)
                .frame(height: 1)
            if isSidebarHovered, !isEmpty {
                Button(action: clear) {
                    Text("Clear")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isClearHovered ? palette.secondaryText : palette.tertiaryText)
                }
                .buttonStyle(.plain)
                .onHover { isClearHovered = $0 }
                .help("Archive all Today tabs (⇧⌘K)")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 25)
        .contentShape(Rectangle())
    }
}

struct NewTabRow: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Sidebar.titleLeading) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: Metrics.Sidebar.iconSize)
                Text("New Tab").font(Typography.rowLabel)
                Spacer()
            }
            .foregroundStyle(palette.secondaryText)
            .padding(.leading, Metrics.Sidebar.iconLeading)
            .frame(height: Metrics.Sidebar.rowHeight)
            .rowBackground(isSelected: false, isHovered: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
        .accessibilityIdentifier("newTabRow")
    }
}

struct DropIndicatorLine: View {
    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
    }
}
