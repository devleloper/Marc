import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The right side of the window: the selected page, a split, a note or an internal page, plus
/// the assistant and Boost editor panels.
struct ContentArea: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        HStack(spacing: Metrics.Content.splitSpacing) {
            ZStack {
                if let split = window.selectedSplit, let layout = split.split?.layout {
                    SplitContainer(window: window, splitID: split.id, layout: layout)
                } else if let item = window.selectedItem {
                    // No `.id(item.id)` here: keeping the same web container across tab switches lets
                    // it show recently used pages instantly (see WebContainerView).
                    ContentCard { PaneContent(window: window, itemID: item.id) }
                } else {
                    ContentCard { EmptyContentView(window: window) }
                }
                if let placesBefore = window.splitDropPlacesBefore {
                    SplitDropHighlight(placesBefore: placesBefore)
                }
            }
            .onDrop(of: SidebarDragPayload.types, delegate: ContentDropDelegate(window: window))

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
                    .id(noteID)
            case let .tab(content):
                if let url = content.url, let page = InternalPage(url: url) {
                    InternalPageView(window: window, page: page)
                        .id(itemID)
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
                WebContentView(
                    tab: tab,
                    token: token,
                    onSidebarDragUpdate: { window.updateSplitDrop(placesBefore: $0) },
                    onSidebarDrop: { id, placeBefore in window.split(with: .item(id), anchor: tab.id, placeBefore: placeBefore) },
                )
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
