import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The right side of the window: the selected page, a split, a note or an internal page, plus
/// the assistant and Boost editor panels.
struct ContentArea: View {
    @Bindable var window: BrowserWindowModel
    @State private var splitDropEdge: Edge?

    var body: some View {
        HStack(spacing: Metrics.Content.splitSpacing) {
            ZStack {
                if let split = window.selectedSplit, let layout = split.split?.layout {
                    SplitContainer(window: window, splitID: split.id, layout: layout)
                } else if let item = window.selectedItem {
                    ContentCard { PaneContent(window: window, itemID: item.id) }
                        .id(item.id)
                } else {
                    ContentCard { EmptyContentView(window: window) }
                }
                if let edge = splitDropEdge {
                    SplitDropHighlight(edge: edge)
                }
            }
            .onDrop(of: SidebarDragPayload.types, delegate: ContentDropDelegate(window: window, edge: $splitDropEdge))

            if let assistant = window.assistant {
                AssistantPanel(window: window, assistant: assistant)
                    .frame(width: 340)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let editor = window.boostEditor {
                BoostEditorPanel(window: window, editor: editor)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Motion.surface, value: window.assistant != nil)
        .animation(Motion.surface, value: window.boostEditor != nil)
    }
}

/// Everything shown inside one content card for one sidebar leaf.
struct PaneContent: View {
    @Bindable var window: BrowserWindowModel
    let itemID: SidebarItem.ID
    @State private var token = UUID()

    var body: some View {
        if let item = window.workspace.items[itemID] {
            switch item.content {
            case let .note(noteID):
                NoteEditorView(window: window, noteID: noteID)
            case let .tab(content):
                if let url = content.url, let page = InternalPage(url: url) {
                    InternalPageView(window: window, page: page)
                } else if let tab = window.runtimeTab(for: itemID) {
                    WebPane(window: window, tab: tab, token: token)
                } else {
                    EmptyContentView(window: window)
                }
            case .folder, .split:
                EmptyContentView(window: window)
            }
        }
    }
}

/// A thin bar along the top of the page while it loads, so progress is visible even with the
/// sidebar hidden. It eases forward with WebKit's estimate, resets without sliding backward when a
/// new load starts, and fades out once the page is done.
private struct LoadingBar: View {
    let tab: WebTab
    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(LinearGradient(
                    colors: [BrandColors.violet, BrandColors.sky, BrandColors.teal],
                    startPoint: .leading,
                    endPoint: .trailing,
                ))
                .frame(width: max(proxy.size.width * progress, 24), height: 2.5)
                .opacity(tab.isLoading ? 1 : 0)
                .animation(.easeOut(duration: tab.isLoading ? 0.15 : 0.4), value: tab.isLoading)
        }
        .frame(height: 2.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { progress = tab.estimatedProgress }
        .onChange(of: tab.estimatedProgress) { old, new in
            if new < old {
                var reset = Transaction()
                reset.disablesAnimations = true
                withTransaction(reset) { progress = new }
            } else {
                withAnimation(.easeOut(duration: 0.25)) { progress = new }
            }
        }
    }
}

private struct WebPane: View {
    @Bindable var window: BrowserWindowModel
    let tab: WebTab
    let token: UUID

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let host = tab.host, host != AnyHashable(token) {
                OtherWindowPlaceholder { tab.host = token }
            } else {
                WebContentView(tab: tab, token: token)
                    .opacity(tab.failure == nil ? 1 : 0)
                    .accessibilityLabel(tab.title.isEmpty ? "Web content" : tab.title)
                    .accessibilityIdentifier("webContent")
                LoadingBar(tab: tab)
            }
            if let failure = tab.failure {
                FailureView(tab: tab, failure: failure)
            }
            if tab.find.isActive {
                FindBar(window: window, tab: tab)
                    .padding(10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let offer = window.passwordOffer, offer.tabID == tab.id {
                PasswordOfferBanner(window: window, offer: offer)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let prompt = window.permissionPrompt, window.selectedItemID == tab.id {
                PermissionPromptView(prompt: prompt)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let offer = window.autofillOffer, offer.tabID == tab.id {
                AutofillPopover(window: window, offer: offer)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let link = tab.hoveredLink, window.session?.settings.settings.showsHoveredLinkStatus == true {
                LinkStatusBar(url: link)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .animation(Motion.hover, value: tab.find.isActive)
        .animation(Motion.surface, value: window.passwordOffer?.id)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            if window.selectedItemID != tab.id { window.select(tab.id) }
        })
    }
}

private struct OtherWindowPlaceholder: View {
    let showHere: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "macwindow.on.rectangle").font(.system(size: 30)).foregroundStyle(.secondary)
            Text("This tab is open in another window").font(.system(size: 14, weight: .semibold))
            Button("Show Here", action: showHere)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct EmptyContentView: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            palette.backgroundGradient.opacity(0.35)
            Rectangle().fill(.background.opacity(0.92))
            VStack(spacing: 14) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Press ⌘T to search or open a site")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Button("New Tab") { window.showCommandBar(.newTab) }
                    .buttonStyle(.pressable)
                    .foregroundStyle(.tint)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyContent")
    }
}

struct LinkStatusBar: View {
    let url: URL

    var body: some View {
        Text(url.absoluteString)
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            .frame(maxWidth: 520, alignment: .leading)
    }
}

/// Drop a tab or link on the left or right half of the content to view it side by side.
private struct ContentDropDelegate: DropDelegate {
    let window: BrowserWindowModel
    @Binding var edge: Edge?

    func validateDrop(info: DropInfo) -> Bool {
        window.selectedItem?.kind == .tab && window.kind != .little && info.hasItemsConforming(to: SidebarDragPayload.types)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let width = window.nsWindow?.contentView?.bounds.width ?? 1000
        let newEdge: Edge = info.location.x < (width - (window.isSidebarVisible ? window.state.sidebarWidth : 0)) / 2 ? .leading : .trailing
        if edge != newEdge { withAnimation(Motion.hover) { edge = newEdge } }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        withAnimation(Motion.hover) { edge = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let placeBefore = edge == .leading
        edge = nil
        guard let anchor = window.selectedItemID else { return false }
        let window = window
        Task { @MainActor in
            guard let payload = await SidebarDragPayload.load(from: info) else { return }
            let otherID: SidebarItem.ID
            switch payload {
            case let .item(id):
                guard id != anchor, window.workspace.items[id]?.kind == .tab else { return }
                if window.workspace.items[id]?.container.section == .favorites {
                    guard let duplicate = try? window.store.update({ try $0.duplicateTab(id) }) else { return }
                    otherID = duplicate
                } else {
                    otherID = id
                }
            case let .url(url):
                guard let spaceID = window.state.spaceID,
                      let id = try? window.store.update({ try $0.openTab(TabContent(url: url), placement: .todayTop(spaceID)) })
                else { return }
                window.runtimeTab(for: id)?.load(url, initiator: .user, transition: .link)
                otherID = id
            }
            withAnimation(Motion.surface) {
                try? window.store.update { try $0.split(anchor, with: otherID, axis: .horizontal, placeAfter: !placeBefore) }
            }
            window.select(otherID)
        }
        return true
    }
}

private struct SplitDropHighlight: View {
    let edge: Edge

    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: Metrics.Content.cornerStyle)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: Metrics.Content.cornerRadius, style: Metrics.Content.cornerStyle).strokeBorder(
                    Color.accentColor,
                    lineWidth: 2,
                ))
                .frame(width: proxy.size.width / 2)
                .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
        }
        .allowsHitTesting(false)
    }
}
