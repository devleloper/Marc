import Foundation
import MarcCore
import Observation
import WebKit

/// App-wide WebKit services: one web context per profile, content blocking, boosts and
/// favicons.
@Observable
public final class WebEngine {
    public let contentBlocker: ContentBlocker
    public let favicons: FaviconLoader
    @ObservationIgnored public let preresolver = HostPreresolver()
    public private(set) var boosts: [Boost] = []
    public var isContentBlockingEnabled = true

    @ObservationIgnored public let applicationName: String
    @ObservationIgnored private var contexts: [Profile.ID: ProfileWebContext] = [:]

    public init(
        contentBlocker: ContentBlocker,
        favicons: FaviconLoader,
        applicationName: String = WebEngine.safariCompatibleApplicationName(),
    ) {
        self.contentBlocker = contentBlocker
        self.favicons = favicons
        self.applicationName = applicationName
    }

    public func context(for profile: Profile) -> ProfileWebContext {
        if let existing = contexts[profile.id] { return existing }
        let context = ProfileWebContext(profile: profile)
        contexts[profile.id] = context
        return context
    }

    public func existingContext(for profileID: Profile.ID) -> ProfileWebContext? {
        contexts[profileID]
    }

    public var loadedContexts: [ProfileWebContext] {
        Array(contexts.values)
    }

    public func makeIncognitoContext() -> ProfileWebContext {
        ProfileWebContext()
    }

    /// Forgets a profile's context and deletes its website data store. Every tab of the profile
    /// must have been closed first.
    public func deleteWebsiteData(for profile: Profile) async throws {
        contexts[profile.id] = nil
        try await WKWebsiteDataStore.remove(forIdentifier: profile.dataStoreID)
    }

    public var environment: WebTabEnvironment {
        WebTabEnvironment(
            applicationName: applicationName,
            contentRuleLists: { [weak self] in self?.contentBlocker.ruleLists ?? [] },
            isContentBlockingEnabled: { [weak self] in self?.isContentBlockingEnabled ?? false },
            boosts: { [weak self] host in self?.boosts(for: host) ?? [] },
            favicons: favicons,
            preresolve: { [weak self] url in self?.preresolver.preresolve(url) },
        )
    }

    public func setBoosts(_ boosts: [Boost]) {
        self.boosts = boosts
    }

    public func boosts(for host: String) -> [Boost] {
        guard !host.isEmpty else { return [] }
        return boosts.filter { $0.isEnabled && $0.matches(host: host) }
    }

    /// Sites tailor content to Safari; advertising a Safari-compatible version keeps them from
    /// serving degraded pages to an unknown WebKit browser.
    public nonisolated static func safariCompatibleApplicationName() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "Version/\(version.majorVersion).\(version.minorVersion) Safari/605.1.15"
    }
}

/// Owns the live `WebTab` for every loaded sidebar item.
@Observable
public final class TabRuntimeRegistry {
    public private(set) var tabs: [SidebarItem.ID: WebTab] = [:]
    @ObservationIgnored public weak var delegate: (any WebTabDelegate)?
    @ObservationIgnored public weak var extensionBridge: (any WebTabExtensionBridge)?
    /// Called whenever a runtime is created or closed, so extensions can be notified.
    @ObservationIgnored public var onTabOpened: ((WebTab) -> Void)?
    @ObservationIgnored public var onTabClosed: ((WebTab) -> Void)?
    @ObservationIgnored private let engine: WebEngine

    public init(engine: WebEngine) {
        self.engine = engine
    }

    public func tab(for id: SidebarItem.ID) -> WebTab? {
        tabs[id]
    }

    /// The runtime for a tab, created on first use. A tab moved to a Space of another profile
    /// gets a new runtime in that profile's data store.
    public func tab(id: SidebarItem.ID, url: URL?, title: String, context: ProfileWebContext) -> WebTab {
        if let existing = tabs[id] {
            if existing.context === context { return existing }
            existing.close()
            onTabClosed?(existing)
        }
        let tab = WebTab(id: id, context: context, environment: engine.environment, url: url, title: title)
        register(tab)
        return tab
    }

    private func register(_ tab: WebTab) {
        tab.delegate = delegate
        tab.extensionBridge = extensionBridge
        tabs[tab.id] = tab
        onTabOpened?(tab)
    }

    public func makePopupTab(id: SidebarItem.ID, context: ProfileWebContext, configuration: WKWebViewConfiguration) -> WebTab {
        let tab = WebTab(id: id, context: context, environment: engine.environment, popupConfiguration: configuration)
        register(tab)
        return tab
    }

    public func close(_ id: SidebarItem.ID) {
        guard let tab = tabs.removeValue(forKey: id) else { return }
        tab.close()
        onTabClosed?(tab)
    }

    public func unload(_ id: SidebarItem.ID) {
        tabs[id]?.unload()
    }

    /// Unloads web views idle for longer than `interval` that are not visible and not playing
    /// or capturing media. Returns the identifiers of unloaded tabs.
    @discardableResult
    public func unloadInactive(
        olderThan interval: TimeInterval,
        now: Date = .now,
        excluding visible: Set<SidebarItem.ID>,
    ) -> [SidebarItem.ID] {
        let threshold = now.addingTimeInterval(-interval)
        let candidates = tabs.values.filter { tab in
            tab.hasWebView && !visible.contains(tab.id) && tab.lastActiveAt < threshold
                && !tab.media.isPlaying && tab.cameraState == .none && tab.microphoneState == .none
        }
        candidates.forEach { $0.unload() }
        return candidates.map(\.id)
    }

    public func boostsDidChange() {
        tabs.values.forEach { $0.boostsDidChange() }
    }

    /// Content rules apply from the next navigation in each tab.
    public func contentRulesDidChange() {
        for tab in tabs.values {
            if let url = tab.url { tab.prepareForNavigation(to: url) }
        }
    }

    public func closeAll(in context: ProfileWebContext) {
        for (id, tab) in tabs where tab.context === context {
            tab.close()
            tabs[id] = nil
            onTabClosed?(tab)
        }
    }
}
