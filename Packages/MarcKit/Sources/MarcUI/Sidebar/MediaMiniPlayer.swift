import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Controls for media playing in a tab other than the visible one.
struct MediaMiniPlayer: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.themePalette) private var palette

    var body: some View {
        if let (item, tab) = playingTab {
            HStack(spacing: 10) {
                FaviconView(image: tab.favicon, fallbackTitle: tab.title, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.media.title ?? tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(tab.media.artist ?? tab.url?.displayHost ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                .foregroundStyle(palette.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { window.select(item.id) }
                IconButton(
                    tab.media.isPlaying ? "pause.fill" : "play.fill",
                    label: tab.media.isPlaying ? "Pause" : "Play",
                    size: 24,
                    symbolSize: 12,
                ) {
                    tab.togglePlayback()
                }
                IconButton(
                    tab.media.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: tab.media.isMuted ? "Unmute" : "Mute",
                    size: 24,
                    symbolSize: 11,
                ) {
                    tab.setMuted(!tab.media.isMuted)
                }
                if tab.media.hasVideo {
                    IconButton("pip.enter", label: "Picture in Picture", size: 24, symbolSize: 11) {
                        tab.togglePictureInPicture()
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: Metrics.Sidebar.rowCornerRadius, style: .continuous).fill(palette.fieldFill))
            .padding(.horizontal, Metrics.Sidebar.inset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Now playing")
        }
    }

    /// The most recently active tab of this window's store that plays media and is not visible.
    private var playingTab: (SidebarItem, WebTab)? {
        guard let session = window.session else { return nil }
        let visible = Set(window.displayedLeafIDs)
        return window.workspace.items.values
            .compactMap { item -> (SidebarItem, WebTab)? in
                guard !visible.contains(item.id), let tab = session.runtime.tab(for: item.id), tab.media.isPlaying else { return nil }
                return (item, tab)
            }
            .max { $0.1.lastActiveAt < $1.1.lastActiveAt }
    }
}
