import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Favorite tiles shared by every Space of the profile.
struct FavoritesGrid: View {
    @Bindable var window: BrowserWindowModel
    let profileID: Profile.ID
    @State private var isDropTargeted = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        let favorites = window.workspace.favorites(for: profileID)
        Group {
            if favorites.isEmpty {
                // An empty drop zone appears only while dragging, as in Arc.
                RoundedRectangle(cornerRadius: Metrics.Sidebar.favoriteCornerRadius, style: .continuous)
                    .strokeBorder(palette.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(height: isDropTargeted ? Metrics.Sidebar.favoriteTileHeight : 0)
                    .opacity(isDropTargeted ? 1 : 0)
            } else {
                let columns = min(favorites.count, Metrics.Sidebar.maximumFavoriteColumns)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.Sidebar.favoriteSpacing), count: columns),
                    spacing: Metrics.Sidebar.favoriteSpacing,
                ) {
                    ForEach(favorites) { item in
                        FavoriteTile(window: window, item: item)
                    }
                }
            }
        }
        .onDrop(of: SidebarDragPayload.types, delegate: SidebarDropDelegate(
            window: window,
            destination: SidebarDestination(container: .favorites(profileID), index: favorites.count),
            isTargeted: $isDropTargeted,
        ))
        .animation(Motion.listChange, value: favorites.map(\.id))
    }
}

private struct FavoriteTile: View {
    @Bindable var window: BrowserWindowModel
    let item: SidebarItem
    @State private var isHovered = false
    @Environment(\.themePalette) private var palette

    var body: some View {
        let runtime = window.session?.runtime.tab(for: item.id)
        let isSelected = window.selectedItemID == item.id
        Button { window.select(item.id) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Metrics.Sidebar.favoriteCornerRadius, style: .continuous)
                    .fill(isSelected ? palette.selectedFill : isHovered ? palette.selectedFill.opacity(0.75) : palette.fieldFill)
                FaviconView(
                    image: runtime?.favicon ?? cachedFavicon,
                    fallbackTitle: item.tab?.displayTitle ?? "",
                    size: 18,
                    isLoading: runtime?.isLoading == true && runtime?.favicon == nil,
                )
                if runtime?.media.isPlaying == true {
                    Image(systemName: runtime?.media.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
            }
            .frame(height: Metrics.Sidebar.favoriteTileHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
        .help(item.tab?.displayTitle ?? "")
        .accessibilityLabel(item.tab?.displayTitle ?? "Favorite")
        .onDrag { SidebarDragPayload.provider(for: item.id) }
        .contextMenu { SidebarItemMenu(window: window, item: item) }
    }

    private var cachedFavicon: NSImage? {
        item.tab?.faviconURL.flatMap { window.session?.engine.favicons.cachedImage(for: $0) }
    }
}
