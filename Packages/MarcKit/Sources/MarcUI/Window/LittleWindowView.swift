import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The compact window for quick links: a slim bar with the site and a button that moves the
/// page into the main browser.
struct LittleWindowView: View {
    @Bindable var window: BrowserWindowModel
    @State private var token = UUID()

    var body: some View {
        let palette = window.palette
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Color.clear.frame(width: 64)
                if let tab = window.selectedTab {
                    FaviconView(image: tab.favicon, fallbackTitle: tab.title, isLoading: tab.isLoading && tab.favicon == nil)
                    Button { window.showCommandBar(.currentTab) } label: {
                        Text(tab.url?.displayHost ?? "New Window")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                IconButton("link", label: "Copy URL", size: 26, symbolSize: 12) { window.copyCurrentURL() }
                IconButton("arrow.up.forward.app", label: "Open in Marc", size: 26, symbolSize: 12) { openInMainWindow() }
                    .disabled(window.selectedTab?.url == nil)
                    .accessibilityIdentifier("openInMarc")
            }
            .padding(.horizontal, 8)
            .frame(height: Metrics.Window.littleToolbarHeight)
            .gesture(WindowDragGesture())

            ContentCard {
                if let item = window.selectedItem {
                    PaneContent(window: window, itemID: item.id)
                } else {
                    EmptyContentView(window: window)
                }
            }
            .padding([.horizontal, .bottom], 6)
        }
        .background(ThemeBackground(palette: palette, grain: 0))
        .overlay {
            if let commandBar = window.commandBar {
                VStack {
                    CommandBarView(model: commandBar, window: window)
                        .frame(maxWidth: 480)
                        .padding(.top, 60)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
        .environment(\.themePalette, palette)
    }

    /// Moves the tab, with its live web view, into the main window's current Space.
    private func openInMainWindow() {
        guard let session = window.session, let item = window.selectedItem, let content = item.tab else { return }
        let target = session.windows.first { $0.kind == .standard && $0.store === session.store } ?? session.openWindow()
        guard let spaceID = target.state.spaceID,
              (try? target.store.update({ try $0.openTab(content, placement: .todayTop(spaceID), id: item.id) })) != nil
        else { return }
        window.store.update { $0.remove(item.id) }
        target.select(item.id)
        target.nsWindow?.makeKeyAndOrderFront(nil)
        window.nsWindow?.performClose(nil)
    }
}
