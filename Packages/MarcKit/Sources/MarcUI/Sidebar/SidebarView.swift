import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI
import WebKit

/// The left column: toolbar, address field, favorites, the Space pager and the footer.
struct SidebarView: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            SidebarToolbar(window: window)
            if window.isCreatingSpace {
                CreateSpaceForm(window: window)
                    .transition(.opacity)
            } else {
                AddressField(window: window)
                    .padding(.horizontal, Metrics.Sidebar.inset)
                if let profile = window.profile, !window.workspace.favorites(for: profile.id).isEmpty || window.kind == .standard {
                    FavoritesGrid(window: window, profileID: profile.id)
                        .padding(.horizontal, Metrics.Sidebar.inset)
                        .padding(.top, Metrics.Sidebar.favoriteSpacing)
                }
                if window.isShowingLibrary {
                    LibraryPanel(window: window)
                        .padding(.top, 8)
                        .transition(.opacity)
                } else {
                    SpacePager(window: window)
                        .padding(.top, 8)
                }
                SidebarFooterStack(window: window)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(Motion.listChange, value: window.isShowingLibrary)
        .animation(Motion.listChange, value: window.isCreatingSpace)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar")
        .accessibilityIdentifier("sidebar")
    }
}

/// Mini player, update notice and footer.
private struct SidebarFooterStack: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        VStack(spacing: 8) {
            MediaMiniPlayer(window: window)
            if window.session?.updateAvailable == true {
                PillButton("New Version Available") { window.perform(.checkForUpdates) }
                    .padding(.horizontal, Metrics.Sidebar.inset)
            }
            SidebarFooter(window: window)
        }
    }
}

/// Window controls row: room for the traffic lights, sidebar toggle and navigation buttons.
struct SidebarToolbar: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        let tab = window.selectedTab
        HStack(spacing: 2) {
            Color.clear.frame(width: 75)
            IconButton("sidebar.left", label: "Toggle Sidebar") { window.toggleSidebar() }
            Spacer(minLength: 0)
            IconButton("arrow.left", label: "Back") { tab?.goBack() }
                .disabled(tab?.canGoBack != true)
            IconButton("arrow.right", label: "Forward") { tab?.goForward() }
                .disabled(tab?.canGoForward != true)
            if tab?.isLoading == true {
                IconButton("xmark", label: "Stop Loading") { tab?.stopLoading() }
            } else {
                IconButton("arrow.clockwise", label: "Reload") { tab?.reload() }
                    .disabled(tab == nil)
            }
        }
        .padding(.trailing, 6)
        .frame(height: Metrics.Sidebar.toolbarHeight)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }
}

/// The address field. Empty: "Search or Enter URL…"; loaded: host plus status, with copy-link
/// and site-control buttons.
struct AddressField: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.themePalette) private var palette
    @State private var isHovered = false

    var body: some View {
        let tab = window.selectedTab
        HStack(spacing: 6) {
            if let url = tab?.url, url.scheme != InternalPage.scheme {
                Button { window.showCommandBar(.currentTab) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            if url.scheme == "https", tab?.hasOnlySecureContent == false {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                            } else if url.scheme == "http" {
                                Image(systemName: "lock.open.fill").font(.system(size: 9)).foregroundStyle(palette.secondaryText)
                            }
                            Text(url.displayHost ?? url.absoluteString)
                                .font(Typography.addressHost)
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if let status = statusText(for: tab) {
                            Text(status)
                                .font(Typography.addressDetail)
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Address, \(url.absoluteString)")
                .accessibilityIdentifier("addressField")
                IconButton("link", label: "Copy URL", size: 28, symbolSize: 13) { window.copyCurrentURL() }
                IconButton("slider.horizontal.3", label: "Site Controls", size: 28, symbolSize: 13) {
                    window.siteControlItemID = window.selectedItemID
                }
                .popover(isPresented: siteControlsBinding, arrowEdge: .bottom) {
                    if let tab { SiteControlsPopover(window: window, tab: tab) }
                }
            } else {
                Button { window.showCommandBar(window.selectedTab == nil ? .newTab : .currentTab) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                        Text("Search or Enter URL…").font(Typography.addressHost)
                        Spacer()
                    }
                    .foregroundStyle(palette.secondaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addressField")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: Metrics.Sidebar.addressFieldHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Sidebar.rowCornerRadius, style: .continuous)
                .fill(isHovered ? palette.selectedFill.opacity(0.75) : palette.fieldFill),
        )
        .overlay(alignment: .bottom) {
            if let tab, tab.isLoading {
                LoadingBar(progress: tab.estimatedProgress)
                    .padding(.horizontal, 10)
            }
        }
        .onHover { hovering in withAnimation(Motion.hover) { isHovered = hovering } }
    }

    private var siteControlsBinding: Binding<Bool> {
        Binding(
            get: { window.siteControlItemID != nil && window.siteControlItemID == window.selectedItemID },
            set: { if !$0 { window.siteControlItemID = nil } },
        )
    }

    private func statusText(for tab: WebTab?) -> String? {
        guard let tab else { return nil }
        if tab.media.isPlaying { return tab.media.isMuted ? "Muted" : "Playing Audio" }
        if tab.cameraState == .active || tab.microphoneState == .active { return "Using Camera or Microphone" }
        if tab.zoom != 1 { return "Zoom \(Int((tab.zoom * 100).rounded()))%" }
        return nil
    }
}

private struct LoadingBar: View {
    let progress: Double
    @Environment(\.themePalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(palette.primaryText.opacity(0.35))
                .frame(width: max(proxy.size.width * progress, 12), height: 2)
                .animation(.easeOut(duration: 0.25), value: progress)
        }
        .frame(height: 2)
        .padding(.bottom, 2)
    }
}
