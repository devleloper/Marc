import AppKit
import Foundation
import MarcCore
import MarcWebKit
import Observation
import os

/// App-wide browser state shared by all windows: the workspace, tab runtimes, downloads,
/// settings and content stores. Windows are represented by `BrowserWindowModel`s; the app
/// target turns them into `NSWindow`s through `presentWindow`.
@Observable
public final class BrowserSession {
    public let store: WorkspaceStore
    public let settings: SettingsModel
    public let engine: WebEngine
    public let runtime: TabRuntimeRegistry
    public let downloads: DownloadCoordinator
    public let archive: ArchiveModel
    public let notes: NotesModel
    public let boosts: BoostsModel
    public let passwords: PasswordController
    public private(set) var windows: [BrowserWindowModel] = []
    public var keyWindowID: WindowState.ID?
    public var updateAvailable = false

    @ObservationIgnored public let services: SessionServices
    @ObservationIgnored let sitePreferences = SitePreferencesCache()
    @ObservationIgnored var recentlyClosed: [ClosedTab] = []
    @ObservationIgnored let restoredWindows: [WindowState]
    @ObservationIgnored private var maintenanceTask: Task<Void, Never>?
    @ObservationIgnored private var saveWindowsTask: Task<Void, Never>?
    @ObservationIgnored private var profileServicesCache: [Profile.ID: ProfileServices] = [:]
    @ObservationIgnored var extensionHosts: [Profile.ID: WebExtensionHost] = [:]
    @ObservationIgnored var extensionWindows: [WindowState.ID: ExtensionWindowAdapter] = [:]
    @ObservationIgnored let logger = Logger.marc("Session")

    /// Creates the `NSWindow` for a model. Set by the app.
    @ObservationIgnored public var presentWindow: ((BrowserWindowModel) -> Void)?
    @ObservationIgnored public var closeWindow: ((BrowserWindowModel) -> Void)?
    @ObservationIgnored public var showSettings: ((SettingsPane) -> Void)?
    @ObservationIgnored public var checkForUpdates: (() -> Void)?
    /// Plays the welcome intro, then the onboarding walkthrough. Set by the app.
    @ObservationIgnored public var showWelcome: (() -> Void)?

    public init(snapshot: WorkspaceSnapshot, services: SessionServices, engine: WebEngine) {
        let store = WorkspaceStore(workspace: snapshot.workspace, repository: services.workspaceRepository)
        if snapshot.workspace.isEmpty {
            // First launch: create and persist the default profile and Space.
            store.update { $0 = Workspace.makeDefault() }
        }
        self.store = store
        self.services = services
        self.engine = engine
        restoredWindows = snapshot.windows
        settings = SettingsModel(store: services.settingsStore)
        runtime = TabRuntimeRegistry(engine: engine)
        archive = ArchiveModel(repository: services.archive)
        notes = NotesModel(repository: services.notes)
        boosts = BoostsModel(repository: services.boosts, engine: engine, runtime: runtime)
        let profileLookup = ProfileServicesLookup()
        downloads = DownloadCoordinator(repository: { profileLookup.resolve?($0)?.downloads })
        passwords = PasswordController(authenticator: services.authenticator)
        profileLookup.resolve = { [weak self] profileID in
            guard let self, let profile = store.workspace.profiles[profileID] else { return nil }
            return profileServices(for: profile)
        }
        passwords.session = self
        runtime.delegate = self
        engine.isContentBlockingEnabled = settings.settings.isContentBlockingEnabled
        settings.onChange = { [weak self] old, new in self?.settingsDidChange(from: old, to: new) }
        store.onPersistenceError = { [weak self] error in
            self?.logger.error("Workspace persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Startup

    /// Loads secondary data, restores windows and starts background maintenance.
    public func start() async {
        engine.preresolver.isEnabled = { [weak self] in self?.settings.settings.preloadsLinkAddresses ?? false }
        startExtensions()
        restoreWindows()
        engine.contentBlocker.onRuleListsChanged = { [weak self] in self?.runtime.contentRulesDidChange() }
        if settings.settings.isContentBlockingEnabled {
            engine.contentBlocker.start(sources: enabledFilterLists)
        }
        async let archiveLoad: Void = archive.reload()
        async let notesLoad: Void = notes.loadAll()
        async let boostsLoad: Void = boosts.load()
        _ = await (archiveLoad, notesLoad, boostsLoad)
        for profile in store.workspace.orderedProfiles {
            let services = profileServices(for: profile)
            await sitePreferences.load(profile.id, from: services.siteData)
            await downloads.loadHistory(for: profile.id)
        }
        downloads.onFinished = { [weak self] download, profileID in self?.downloadDidFinish(download, profileID: profileID) }
        startMaintenance()
        Task { [weak self] in await self?.fillMissingFavicons() }
    }

    var enabledFilterLists: [FilterListSource] {
        services.filterLists.filter(\.isEnabledByDefault)
    }

    private func restoreWindows() {
        let restorable = restoredWindows.filter { state in
            state.kind == .standard && (state.spaceID.map { store.workspace.spaces[$0] != nil } ?? false)
        }
        if restorable.isEmpty || services.isUITesting {
            openWindow()
        } else {
            for state in restorable {
                let window = BrowserWindowModel(session: self, kind: .standard, store: store, state: state)
                windows.append(window)
                presentWindow?(window)
                notifyExtensionsOfWindow(window, opened: true)
            }
        }
    }

    // MARK: - Windows

    @discardableResult
    public func openWindow(spaceID: Space.ID? = nil) -> BrowserWindowModel {
        let space = spaceID ?? keyWindow?.state.spaceID ?? store.workspace.orderedSpaces.first?.id
        let state = WindowState(spaceID: space, sortKey: Double(windows.count))
        let window = BrowserWindowModel(session: self, kind: .standard, store: store, state: state)
        windows.append(window)
        presentWindow?(window)
        notifyExtensionsOfWindow(window, opened: true)
        scheduleWindowSave()
        return window
    }

    /// A window whose tabs are not saved. Incognito windows also use an isolated, non-persistent
    /// data store.
    @discardableResult
    public func openEphemeralWindow(kind: BrowserWindowModel.Kind, url: URL? = nil) -> BrowserWindowModel {
        let profile = keyWindow?.profile ?? store.workspace.orderedProfiles[0]
        let (name, theme): (String, Theme) = switch kind {
        case .incognito: ("Incognito", .incognito)
        case .little: ("Little Window", keyWindow?.space?.theme ?? .default)
        default: ("This Window", keyWindow?.space?.theme ?? .default)
        }
        let workspace = Workspace.ephemeral(named: name, profile: profile, theme: theme)
        let privateStore = WorkspaceStore(workspace: workspace, repository: InMemoryWorkspaceRepository())
        let state = WindowState(kind: kind == .little ? .little : .standard, spaceID: workspace.orderedSpaces.first?.id)
        let window = BrowserWindowModel(
            session: self,
            kind: kind,
            store: privateStore,
            state: state,
            incognitoContext: kind == .incognito ? engine.makeIncognitoContext() : nil,
        )
        windows.append(window)
        if let url {
            window.open(url, placement: .newTab, select: true)
        }
        presentWindow?(window)
        notifyExtensionsOfWindow(window, opened: true)
        return window
    }

    public func windowDidBecomeKey(_ window: BrowserWindowModel) {
        keyWindowID = window.id
        notifyExtensionsOfFocus(window)
    }

    public func windowDidClose(_ window: BrowserWindowModel) {
        notifyExtensionsOfWindow(window, opened: false)
        windows.removeAll { $0 === window }
        if window.store !== store {
            for item in window.store.workspace.items.values {
                runtime.close(item.id)
            }
        }
        if keyWindowID == window.id { keyWindowID = windows.last?.id }
        scheduleWindowSave()
    }

    public var keyWindow: BrowserWindowModel? {
        windows.first { $0.id == keyWindowID } ?? windows.first { $0.kind == .standard } ?? windows.first
    }

    /// The window that shows a tab, preferring the key window.
    func window(showing itemID: SidebarItem.ID) -> BrowserWindowModel? {
        let candidates = windows.filter { $0.displayedLeafIDs.contains(itemID) }
        return candidates.first { $0.id == keyWindowID } ?? candidates.first
    }

    /// The window whose store contains a tab.
    func window(containing itemID: SidebarItem.ID) -> BrowserWindowModel? {
        if let showing = window(showing: itemID) { return showing }
        return windows.first { $0.store.workspace.items[itemID] != nil && $0.store !== store }
            ?? (store.workspace.items[itemID] != nil ? keyWindow : nil)
    }

    func scheduleWindowSave() {
        saveWindowsTask?.cancel()
        saveWindowsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            await saveWindowsNow()
        }
    }

    public func saveWindowsNow() async {
        let states = windows.filter { $0.store === store && $0.kind == .standard }.map(\.state)
        do {
            try await services.workspaceRepository.saveWindows(states)
        } catch {
            logger.error("Failed to save windows: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Flushes pending writes before the app terminates.
    public func prepareForTermination() async {
        saveWindowsTask?.cancel()
        await saveWindowsNow()
        await store.flush()
    }

    // MARK: - Profiles

    public func profileServices(for profile: Profile) -> ProfileServices {
        if let cached = profileServicesCache[profile.id] { return cached }
        let created = services.profileServices(profile)
        profileServicesCache[profile.id] = created
        return created
    }

    func profileServices(for profileID: Profile.ID?) -> ProfileServices? {
        guard let profileID, let profile = store.workspace.profiles[profileID] else { return nil }
        return profileServices(for: profile)
    }

    public func deleteProfile(_ profileID: Profile.ID, reassigningTo replacement: Profile.ID) async {
        guard let profile = store.workspace.profiles[profileID] else { return }
        let context = engine.existingContext(for: profileID)
        do {
            try store.update { try $0.deleteProfile(profileID, reassigningSpacesTo: replacement) }
        } catch {
            return
        }
        if let context { runtime.closeAll(in: context) }
        profileServicesCache[profileID] = nil
        try? await engine.deleteWebsiteData(for: profile)
        await services.removeProfileData(profile)
    }

    // MARK: - Tabs

    /// The web context a tab of `window` uses.
    func context(for itemID: SidebarItem.ID, in window: BrowserWindowModel) -> ProfileWebContext? {
        if let incognito = window.incognitoContext { return incognito }
        guard let profileID = window.store.workspace.profileID(for: itemID), let profile = window.store.workspace.profiles[profileID] else {
            return nil
        }
        return engine.context(for: profile)
    }

    /// The runtime for a tab, created on first use.
    func runtimeTab(for itemID: SidebarItem.ID, in window: BrowserWindowModel) -> WebTab? {
        guard let item = window.store.workspace.items[itemID], let tab = item.tab, let context = context(for: itemID, in: window) else {
            return nil
        }
        return runtime.tab(id: itemID, url: tab.url, title: tab.title, context: context)
    }

    /// Removes tabs from a store: today tabs go to the Archive, everything is unloaded.
    func archive(_ itemIDs: [SidebarItem.ID], from window: BrowserWindowModel) {
        let workspace = window.store.workspace
        var archived: [ArchivedTab] = []
        for itemID in itemIDs {
            guard let item = workspace.items[itemID] else { continue }
            let profileID = workspace.profileID(for: itemID)
            let removed = window.store.update { $0.remove(itemID) }
            for tab in removed {
                runtime.close(tab.id)
                guard let content = tab.tab else { continue }
                recentlyClosed.append(ClosedTab(content: content, container: tab.container, windowID: window.id))
                if window.store === store, let url = content.url, url.isWebURL, let profileID {
                    archived.append(ArchivedTab(
                        spaceID: item.container.spaceID,
                        profileID: profileID,
                        title: content.displayTitle,
                        url: url,
                        faviconURL: content.faviconURL,
                    ))
                }
            }
        }
        if recentlyClosed.count > 50 { recentlyClosed.removeFirst(recentlyClosed.count - 50) }
        archive.add(archived)
    }

    // MARK: - Favicons

    /// Fetches site icons for saved tabs that have never loaded, so the sidebar shows real icons
    /// instead of letter tiles. Requests go through the cookie-less favicon session, a few at a time.
    func fillMissingFavicons() async {
        let missing = Array(store.workspace.tabsMissingFavicons())
        for batch in stride(from: 0, to: missing.count, by: 4).map({ missing[$0 ..< min($0 + 4, missing.count)] }) {
            guard !Task.isCancelled else { return }
            let found = await withTaskGroup(of: URL?.self) { group in
                for (iconURL, _) in batch {
                    group.addTask { await self.engine.favicons.image(for: iconURL) != nil ? iconURL : nil }
                }
                var found = Set<URL>()
                for await url in group {
                    if let url { found.insert(url) }
                }
                return found
            }
            let updates = batch.filter { found.contains($0.key) }
            guard !updates.isEmpty else { continue }
            store.update { workspace in
                for (iconURL, itemIDs) in updates {
                    for id in itemIDs {
                        try? workspace.updateTab(id) { if $0.faviconURL == nil { $0.faviconURL = iconURL } }
                    }
                }
            }
        }
    }

    // MARK: - Maintenance

    private func startMaintenance() {
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.runMaintenance()
            }
        }
    }

    /// Archives expired Today tabs and unloads idle web views.
    func runMaintenance(now: Date = .now) {
        let visible = Set(windows.flatMap(\.displayedLeafIDs))
        let candidates = store.workspace.archiveCandidates(now: now, interval: settings.settings.archiveInterval, excluding: visible)
        if !candidates.isEmpty, let window = windows.first(where: { $0.store === store }) {
            archive(candidates.map(\.id), from: window)
        }
        if let interval = settings.settings.memorySaverInterval.duration {
            runtime.unloadInactive(olderThan: interval, now: now, excluding: visible)
        }
    }

    // MARK: - Settings

    private func settingsDidChange(from old: BrowserSettings, to new: BrowserSettings) {
        if old.isContentBlockingEnabled != new.isContentBlockingEnabled {
            engine.isContentBlockingEnabled = new.isContentBlockingEnabled
            if new.isContentBlockingEnabled { engine.contentBlocker.start(sources: enabledFilterLists) }
            runtime.contentRulesDidChange()
        }
    }

    // MARK: - Downloads

    private func downloadDidFinish(_ download: Download, profileID: Profile.ID?) {
        keyWindow?.showToast("Downloaded \(download.fileName)", symbol: "arrow.down.circle")
        guard settings.settings.tidiesDownloadNames, settings.settings.aiProvider != .off else { return }
        Task { await tidyDownloadName(download) }
    }

    private func tidyDownloadName(_ download: Download) async {
        guard let provider = await services.languageModels.provider(for: settings.settings.aiProvider) else { return }
        let request = AIPrompts.tidyFileName(download.fileName, sourceURL: download.sourceURL, pageTitle: nil)
        guard let response = try? await provider.complete(request),
              let name = AIResponseParser.fileName(response, originalName: download.fileName),
              name != download.fileName
        else { return }
        downloads.rename(download.id, to: name)
    }
}

/// Resolves profile services lazily; lets the download coordinator be created before the
/// session finishes initializing.
private final class ProfileServicesLookup {
    var resolve: ((Profile.ID) -> ProfileServices?)?
}
