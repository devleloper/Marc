import AppKit
import Foundation
import MarcCore
import MarcDesignSystem
import MarcWebKit
import Observation

/// State and intents of one browser window.
@Observable
public final class BrowserWindowModel: Identifiable {
    public enum Kind: Equatable {
        case standard
        case blank
        case incognito
        case little
    }

    public enum CommandBarPlacement: Equatable {
        /// Centered, opening results in a new tab (⌘T).
        case newTab
        /// Centered, prefilled with the current URL, navigating the current tab (⌘L).
        case currentTab
        /// Opens the result next to the selected tab in a split view (⌃⇧=).
        case split
    }

    public let id: WindowState.ID
    public let kind: Kind
    public let store: WorkspaceStore
    public var state: WindowState {
        didSet { if state != oldValue { session?.scheduleWindowSave() } }
    }

    public var isSidebarRevealed = false
    /// Direction of the last Space change, used by the sidebar pager animation.
    public private(set) var spaceChangeIsForward = true
    public var commandBar: CommandBarModel?
    public var peek: PeekModel?
    public var toasts: [Toast] = []
    public var isShowingLibrary = false
    public var renamingItemID: SidebarItem.ID?
    public var isCreatingSpace = false
    public var editingThemeSpaceID: Space.ID?
    public var assistant: AssistantModel?
    public var permissionPrompt: PermissionPrompt?
    public var passwordOffer: PasswordOffer?
    public var autofillOffer: AutofillOffer?
    public var boostEditor: BoostEditorModel?
    public var findFocusRequest = 0
    public var siteControlItemID: SidebarItem.ID?
    /// Set by the window controller; full screen hides the traffic lights, so the toolbar moves left.
    public var isFullScreen = false
    /// Incremented once a drag over the sidebar has gone quiet, so drop highlights reset even when
    /// SwiftUI doesn't deliver `dropExited`, which on macOS sometimes doesn't happen.
    public private(set) var dropHighlightResets = 0
    @ObservationIgnored private var dropWatchdog: Task<Void, Never>?
    public var renamingSpaceID: Space.ID?
    public var isShowingImport = false
    public var sourceViewer: SourceViewerModel?

    @ObservationIgnored public weak var session: BrowserSession?
    @ObservationIgnored private weak var previousSelectedTab: WebTab?
    @ObservationIgnored public weak var nsWindow: NSWindow?
    @ObservationIgnored public let incognitoContext: ProfileWebContext?

    init(session: BrowserSession, kind: Kind, store: WorkspaceStore, state: WindowState, incognitoContext: ProfileWebContext? = nil) {
        self.session = session
        self.kind = kind
        self.store = store
        self.state = state
        self.incognitoContext = incognitoContext
        id = state.id
    }

    // MARK: - Derived state

    public var workspace: Workspace {
        store.workspace
    }

    public var space: Space? {
        state.spaceID.flatMap { workspace.spaces[$0] }
    }

    public var profile: Profile? {
        space.flatMap { workspace.profiles[$0.profileID] }
    }

    public var isPersistent: Bool {
        kind == .standard
    }

    public var selectedItemID: SidebarItem.ID? {
        guard let id = state.selectedItemID, workspace.items[id] != nil else { return nil }
        return id
    }

    public var selectedItem: SidebarItem? {
        selectedItemID.flatMap { workspace.items[$0] }
    }

    /// The split the selection belongs to, if any.
    public var selectedSplit: SidebarItem? {
        selectedItemID.flatMap { workspace.enclosingSplit(of: $0) }
    }

    /// Leaves currently visible in the content area.
    public var displayedLeafIDs: [SidebarItem.ID] {
        if let split = selectedSplit?.split { return split.layout.panes }
        return selectedItemID.map { [$0] } ?? []
    }

    public var selectedTab: WebTab? {
        guard let id = selectedItemID, workspace.items[id]?.kind == .tab else { return nil }
        return session?.runtimeTab(for: id, in: self)
    }

    public func runtimeTab(for itemID: SidebarItem.ID) -> WebTab? {
        session?.runtimeTab(for: itemID, in: self)
    }

    public var isSidebarVisible: Bool {
        state.isSidebarVisible
    }

    public var palette: ThemePalette {
        let theme = space?.theme ?? .default
        let systemIsDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return ThemePalette(
            themeColors: theme.colors.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue) },
            isDark: theme.prefersDarkChrome(systemIsDark: systemIsDark),
        )
    }

    // MARK: - Selection

    public func select(_ itemID: SidebarItem.ID?) {
        guard let spaceID = state.spaceID else { return }
        commandBar = nil
        guard let itemID, let item = workspace.items[itemID] else {
            state.selection[spaceID] = nil
            return
        }
        if let itemSpace = item.container.spaceID, itemSpace != spaceID {
            state.spaceID = itemSpace
        }
        if let currentSpace = state.spaceID {
            state.selection[currentSpace] = itemID
        }
        let now = Date.now
        let previous = previousSelectedTab
        store.update { $0.touch(itemID, at: now) }
        let current = item.kind == .tab ? session?.runtimeTab(for: itemID, in: self) : nil
        if let tab = current {
            tab.markActive(at: now)
            tab.loadIfNeeded()
            if previous !== tab { session?.notifyExtensionsOfActivation(tab, previous: previous) }
            previousSelectedTab = tab
        }
        updatePictureInPicture(leaving: previous, showing: current)
    }

    /// Arc-style automatic Picture in Picture: a video playing in the tab being left moves into
    /// Picture in Picture, and comes back when its tab is shown again.
    private func updatePictureInPicture(leaving previous: WebTab?, showing current: WebTab?) {
        guard previous !== current else { return }
        if let current, current.media.isInPictureInPicture { current.exitPictureInPicture() }
        guard let previous, Self.shouldMoveToPictureInPicture(
            previous.media,
            isStillVisible: displayedLeafIDs.contains(previous.id),
            isEnabled: session?.settings.settings.opensPictureInPictureAutomatically == true,
        ) else { return }
        previous.enterPictureInPicture()
    }

    static func shouldMoveToPictureInPicture(_ media: MediaState, isStillVisible: Bool, isEnabled: Bool) -> Bool {
        isEnabled && media.isPlaying && media.hasVideo && !media.isInPictureInPicture && !isStillVisible
    }

    public func switchSpace(to spaceID: Space.ID) {
        guard workspace.spaces[spaceID] != nil, spaceID != state.spaceID else { return }
        let order = workspace.orderedSpaces.map(\.id)
        spaceChangeIsForward = (order.firstIndex(of: spaceID) ?? 0) > (state.spaceID.flatMap(order.firstIndex(of:)) ?? 0)
        state.spaceID = spaceID
        isCreatingSpace = false
        var current: WebTab?
        if let selected = selectedItemID, workspace.items[selected]?.kind == .tab {
            current = session?.runtimeTab(for: selected, in: self)
            current?.loadIfNeeded()
        }
        updatePictureInPicture(leaving: previousSelectedTab, showing: current)
        if let current { previousSelectedTab = current }
    }

    /// Archives a Space's tabs and deletes it; windows showing it move to another Space.
    public func deleteSpace(_ spaceID: Space.ID) {
        guard let session, workspace.spaces.count > 1 else { return }
        let roots = workspace.items.values.filter { $0.container.spaceID == spaceID && $0.parentID == nil }.map(\.id)
        session.archive(roots, from: self)
        let fallback = workspace.orderedSpaces.first { $0.id != spaceID }?.id
        for window in session.windows where window.state.spaceID == spaceID {
            window.state.spaceID = fallback
        }
        _ = try? store.update { try $0.deleteSpace(spaceID) }
    }

    public func switchSpace(offset: Int) {
        let spaces = workspace.orderedSpaces
        guard let index = spaces.firstIndex(where: { $0.id == state.spaceID }) else { return }
        let target = index + offset
        guard spaces.indices.contains(target) else { return }
        switchSpace(to: spaces[target].id)
    }

    public func switchSpace(number: Int) {
        let spaces = workspace.orderedSpaces
        guard spaces.indices.contains(number - 1) else { return }
        switchSpace(to: spaces[number - 1].id)
    }

    /// ⌥⌘↓ / ⌥⌘↑ move through visible tabs.
    public func selectNeighbor(offset: Int) {
        guard let spaceID = state.spaceID else { return }
        let order = workspace.selectableItems(in: spaceID).map(\.id)
        select(SelectionPolicy.neighbor(of: selectedItemID, offset: offset, in: order))
    }

    /// ⌘1…⌘9 select by position; ⌘9 selects the last item.
    public func selectItem(number: Int) {
        guard let spaceID = state.spaceID else { return }
        let order = workspace.selectableItems(in: spaceID).map(\.id)
        guard !order.isEmpty else { return }
        select(number == 9 ? order.last : order.indices.contains(number - 1) ? order[number - 1] : nil)
    }

    // MARK: - Opening

    public enum OpenPlacement {
        case newTab
        case backgroundTab
        case currentTab
        case splitWithSelection
    }

    /// Opens `url` in this window.
    @discardableResult
    public func open(
        _ url: URL,
        placement: OpenPlacement,
        select shouldSelect: Bool = true,
        initiator: NavigationSafetyPolicy.Initiator = .user,
    ) -> SidebarItem.ID? {
        if url.scheme == InternalPage.scheme, InternalPage(url: url) == nil { return nil }
        guard let spaceID = state.spaceID else { return nil }
        if placement == .currentTab, let tab = selectedTab {
            tab.load(url, initiator: initiator, transition: initiator == .user ? .typed : .link)
            return tab.id
        }
        let anchor = placement == .splitWithSelection ? selectedItemID.flatMap(splittableAnchor) : selectedItemID
        guard let itemID = try? store.update({ try $0.openTab(TabContent(url: url), placement: .todayTop(spaceID)) }) else { return nil }
        let tab = session?.runtimeTab(for: itemID, in: self)
        if placement == .splitWithSelection, let anchor, workspace.items[anchor]?.kind == .tab {
            try? store.update { try $0.split(anchor, with: itemID) }
        }
        if url.scheme != InternalPage.scheme {
            tab?.load(url, initiator: initiator, transition: initiator == .user ? .typed : .link)
        }
        if shouldSelect || placement == .splitWithSelection {
            select(itemID)
        }
        return itemID
    }

    // MARK: - Commands

    public func showCommandBar(_ placement: CommandBarPlacement) {
        guard let session else { return }
        let initialText = placement == .currentTab ? (selectedTab?.url?.absoluteString ?? "") : ""
        commandBar = CommandBarModel(window: self, session: session, placement: placement, initialText: initialText)
    }

    public func dismissCommandBar() {
        commandBar = nil
    }

    /// A tab that can anchor a split. Favorites can't hold splits, so a favorite's page opens as a
    /// Today tab first and that tab anchors the split.
    func splittableAnchor(_ id: SidebarItem.ID) -> SidebarItem.ID? {
        guard let item = workspace.items[id], let content = item.tab else { return nil }
        guard item.container.section == .favorites else { return id }
        guard let spaceID = state.spaceID,
              let copy = try? store.update({ try $0.openTab(
                  TabContent(url: content.url, title: content.title, faviconURL: content.faviconURL),
                  placement: .todayTop(spaceID),
              ) })
        else { return nil }
        if let url = content.url { runtimeTab(for: copy)?.load(url, initiator: .user, transition: .link) }
        return copy
    }

    /// Clicking into a split pane makes it the selected pane, so pane commands act on it.
    func focusPane(_ tabID: SidebarItem.ID) {
        guard selectedItemID != tabID, let split = selectedSplit?.split, split.layout.panes.contains(tabID) else { return }
        select(tabID)
    }

    /// Called on every drop update over the sidebar; when updates stop, drop highlights reset.
    func noteDropActivity(quietPeriod: Duration = .milliseconds(1200)) {
        dropWatchdog?.cancel()
        dropWatchdog = Task { [weak self] in
            try? await Task.sleep(for: quietPeriod)
            guard !Task.isCancelled else { return }
            self?.dropHighlightResets += 1
        }
    }

    public func toggleSidebar() {
        state.isSidebarVisible.toggle()
        isSidebarRevealed = false
    }

    /// ⌘W: archives the selected Today tab, unloads a pinned tab or favorite, closes a note.
    public func closeSelected() {
        guard let item = selectedItem, let spaceID = state.spaceID else {
            if workspace.items.isEmpty, kind != .standard { nsWindow?.performClose(nil) }
            return
        }
        let order = workspace.selectableItems(in: spaceID).map(\.id)
        switch item.container.section {
        case .today:
            session?.archive([item.id], from: self)
            if kind != .standard, workspace.items.isEmpty {
                nsWindow?.performClose(nil)
                return
            }
        case .pinned, .favorites:
            session?.runtime.unload(item.id)
            if item.tab?.hasLeftHome == true { try? store.update { try $0.resetToHome(item.id) } }
        }
        let remaining = workspace.selectableItems(in: spaceID).map(\.id).filter { $0 != item.id }
        let next = SelectionPolicy.replacement(forRemoved: item.id, orderBeforeRemoval: order, remaining: remaining)
        state.selection[spaceID] = nil
        if let next { select(next) }
    }

    public func clearToday() {
        guard let spaceID = state.spaceID else { return }
        let ids = workspace.children(of: .today(spaceID)).map(\.id)
        let selected = selectedItemID
        session?.archive(ids, from: self)
        if let selected, workspace.items[selected] == nil {
            state.selection[spaceID] = nil
        }
        showToast("Cleared \(ids.count) tab\(ids.count == 1 ? "" : "s")", symbol: "archivebox")
    }

    public func restoreLastClosedTab() {
        guard let session, let closed = session.recentlyClosed.popLast(), let url = closed.content.url else { return }
        open(url, placement: .newTab)
    }

    public func copyCurrentURL(format: CopyFormat = .plain) {
        guard let tab = selectedTab, let url = tab.url else { return }
        let string = switch format {
        case .plain: url.absoluteString
        case .markdown: url.markdownLink(title: tab.title)
        case .quote: "\u{201C}\(tab.title)\u{201D}\n\(url.absoluteString)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        showToast(format == .plain ? "Copied URL" : "Copied Link", symbol: "link")
    }

    public enum CopyFormat {
        case plain
        case markdown
        case quote
    }

    public func showToast(_ message: String, symbol: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        let toast = Toast(message: message, symbol: symbol, actionTitle: actionTitle, action: action)
        toasts = [toast]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            self?.toasts.removeAll { $0.id == toast.id }
        }
    }

    // MARK: - Zoom

    public func adjustZoom(_ direction: ZoomDirection) {
        guard let tab = selectedTab, let host = tab.url?.host(percentEncoded: false), let session else { return }
        let next: Double = switch direction {
        case .in: SiteSettings.nextZoom(after: tab.zoom, zoomingIn: true)
        case .out: SiteSettings.nextZoom(after: tab.zoom, zoomingIn: false)
        case .reset: 1
        }
        tab.setZoom(next)
        if let profileID = profile?.id, isPersistent, let services = session.profileServices(for: profileID) {
            var siteSettings = session.sitePreferences.settings(for: host, profileID: profileID)
            siteSettings.zoom = next == 1 ? nil : next
            session.sitePreferences.update(siteSettings, profileID: profileID, repository: services.siteData)
        }
        showToast("\(Int((next * 100).rounded()))%", symbol: "plus.magnifyingglass")
    }

    public enum ZoomDirection {
        case `in`
        case out
        case reset
    }
}

/// A site asking for camera or microphone access.
public struct PermissionPrompt: Identifiable {
    public let id = UUID()
    public let origin: String
    public let kinds: [SitePermissionKind]
    let respond: (_ allow: Bool, _ remember: Bool) -> Void
}

/// "Save password for …?" banner.
public struct PasswordOffer: Identifiable {
    public let id = UUID()
    public let tabID: SidebarItem.ID
    public let profileID: Profile.ID
    public let origin: String
    public let username: String
    let password: String
    public let existing: Credential?
}

/// Saved logins offered next to a focused login field.
public struct AutofillOffer: Identifiable {
    public let id = UUID()
    public let tabID: SidebarItem.ID
    public let profileID: Profile.ID
    public let rect: CGRect
    public let credentials: [Credential]
    public let suggestedPassword: String?
}
