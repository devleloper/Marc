import AppKit
import Foundation
import MarcCore
import MarcWebKit
import WebKit

/// Presents a browser window to web extensions.
final class ExtensionWindowAdapter: NSObject, WKWebExtensionWindow {
    weak var model: BrowserWindowModel?

    init(model: BrowserWindowModel) {
        self.model = model
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let model, let spaceID = model.state.spaceID else { return [] }
        return model.workspace.selectableItems(in: spaceID)
            .filter { $0.kind == .tab }
            .compactMap { model.runtimeTab(for: $0.id) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        model?.selectedTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        model?.kind == .little ? .popup : .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = model?.nsWindow else { return .normal }
        if window.isMiniaturized { return .minimized }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        return .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        model?.kind == .incognito
    }

    func frame(for context: WKWebExtensionContext) -> CGRect {
        model?.nsWindow?.frame ?? .null
    }

    func screenFrame(for context: WKWebExtensionContext) -> CGRect {
        model?.nsWindow?.screen?.frame ?? NSScreen.main?.frame ?? .null
    }

    func focus(for context: WKWebExtensionContext) async throws {
        model?.nsWindow?.makeKeyAndOrderFront(nil)
    }

    func close(for context: WKWebExtensionContext) async throws {
        model?.nsWindow?.performClose(nil)
    }
}

extension BrowserSession {
    /// The extension host of a profile, created and loaded on first use.
    public func extensionHost(for profile: Profile) -> WebExtensionHost? {
        if let existing = extensionHosts[profile.id] { return existing }
        guard let controller = engine.context(for: profile).extensionController else { return nil }
        let host = WebExtensionHost(controller: controller, directory: services.extensionsDirectory(profile))
        host.delegate = self
        extensionHosts[profile.id] = host
        Task { await host.loadInstalled() }
        return host
    }

    func extensionHost(for tab: WebTab) -> WebExtensionHost? {
        guard let profileID = tab.context.profileID else { return nil }
        return extensionHosts[profileID]
    }

    func adapter(for window: BrowserWindowModel) -> ExtensionWindowAdapter {
        if let existing = extensionWindows[window.id] { return existing }
        let adapter = ExtensionWindowAdapter(model: window)
        extensionWindows[window.id] = adapter
        return adapter
    }

    /// Starts extension hosts and connects tab lifecycle notifications.
    func startExtensions() {
        runtime.extensionBridge = self
        runtime.onTabOpened = { [weak self] tab in self?.extensionHost(for: tab)?.controller.didOpenTab(tab) }
        runtime.onTabClosed = { [weak self] tab in self?.extensionHost(for: tab)?.controller.didCloseTab(tab, windowIsClosing: false) }
        for profile in store.workspace.orderedProfiles {
            _ = extensionHost(for: profile)
        }
    }

    func notifyExtensionsOfActivation(_ tab: WebTab, previous: WebTab?) {
        guard let host = extensionHost(for: tab) else { return }
        host.controller.didActivateTab(tab, previousActiveTab: previous?.context === tab.context ? previous : nil)
    }

    func notifyExtensionsOfChange(_ tab: WebTab) {
        extensionHost(for: tab)?.controller.didChangeTabProperties([.title, .URL, .loading], for: tab)
    }

    func notifyExtensionsOfWindow(_ window: BrowserWindowModel, opened: Bool) {
        guard window.kind != .incognito, let profile = window.profile, let host = extensionHost(for: profile) else { return }
        let adapter = adapter(for: window)
        if opened {
            host.controller.didOpenWindow(adapter)
        } else {
            host.controller.didCloseWindow(adapter)
            extensionWindows[window.id] = nil
        }
    }

    func notifyExtensionsOfFocus(_ window: BrowserWindowModel) {
        guard window.kind != .incognito, let profile = window.profile else { return }
        extensionHost(for: profile)?.controller.didFocusWindow(adapter(for: window))
    }
}

extension BrowserSession: WebTabExtensionBridge {
    public func extensionWindow(for tab: WebTab) -> (any WKWebExtensionWindow)? {
        window(containing: tab.id).map(adapter(for:))
    }

    public func extensionIndex(of tab: WebTab) -> Int {
        guard let window = window(containing: tab.id), let spaceID = window.state.spaceID else { return 0 }
        return window.workspace.selectableItems(in: spaceID).filter { $0.kind == .tab }.firstIndex { $0.id == tab.id } ?? 0
    }

    public func isSelected(_ tab: WebTab) -> Bool {
        windows.contains { $0.selectedItemID == tab.id }
    }

    public func isPinned(_ tab: WebTab) -> Bool {
        guard let item = window(containing: tab.id)?.workspace.items[tab.id] else { return false }
        return item.container.section != .today
    }

    public func activate(_ tab: WebTab) {
        guard let window = window(containing: tab.id) else { return }
        window.select(tab.id)
        window.nsWindow?.makeKeyAndOrderFront(nil)
    }

    public func close(_ tab: WebTab) {
        guard let window = window(containing: tab.id) else { return }
        archive([tab.id], from: window)
    }
}

extension BrowserSession: WebExtensionHostDelegate {
    public func openWindows(for host: WebExtensionHost) -> [any WKWebExtensionWindow] {
        windows.filter { $0.kind != .incognito }.map(adapter(for:))
    }

    public func focusedWindow(for host: WebExtensionHost) -> (any WKWebExtensionWindow)? {
        keyWindow.map(adapter(for:))
    }

    public func host(_ host: WebExtensionHost, openTabWith configuration: WKWebExtension.TabConfiguration) -> (any WKWebExtensionTab)? {
        let target = (configuration.window as? ExtensionWindowAdapter)?.model ?? keyWindow
        guard let target, let url = configuration.url, let id = target.open(
            url,
            placement: configuration.shouldBeActive ? .newTab : .backgroundTab,
            select: configuration.shouldBeActive,
            initiator: .webContent,
        ) else {
            return nil
        }
        return runtime.tab(for: id)
    }

    public func host(
        _ host: WebExtensionHost,
        openWindowWith configuration: WKWebExtension.WindowConfiguration,
    ) -> (any WKWebExtensionWindow)? {
        let window = configuration.shouldBePrivate ? openEphemeralWindow(kind: .incognito) : openWindow()
        for url in configuration.tabURLs {
            window.open(url, placement: .newTab, initiator: .webContent)
        }
        return adapter(for: window)
    }

    public func host(_ host: WebExtensionHost, openOptionsPage url: URL) {
        keyWindow?.open(url, placement: .newTab, initiator: .user)
    }

    public func host(_ host: WebExtensionHost, confirm title: String, details: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = details
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Cancel")
        if let window = keyWindow?.nsWindow {
            return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    public func host(_ host: WebExtensionHost, presentPopover popover: NSPopover) {
        guard let window = keyWindow, let contentView = window.nsWindow?.contentView else { return }
        let width = window.isSidebarVisible ? window.state.sidebarWidth : 260
        let top: CGFloat = 46
        let rect = contentView.isFlipped
            ? NSRect(x: 8, y: top, width: width - 16, height: 36)
            : NSRect(x: 8, y: contentView.bounds.height - top - 36, width: width - 16, height: 36)
        popover.behavior = .transient
        popover.show(relativeTo: rect, of: contentView, preferredEdge: .maxX)
    }
}
