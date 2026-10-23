import AppKit
import Foundation
import MarcCore
import MarcPersistence
import MarcPlatform
import MarcUI
import MarcWebKit
import os

/// The composition root: builds every concrete dependency and the browser session.
@MainActor
final class AppEnvironment {
    let session: BrowserSession
    let updater: Updater
    let isUITesting: Bool

    private init(session: BrowserSession, updater: Updater, isUITesting: Bool) {
        self.session = session
        self.updater = updater
        self.isUITesting = isUITesting
    }

    static func make() async throws -> AppEnvironment {
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let locations = try isUITesting
            ? StorageLocations(root: FileManager.default.temporaryDirectory.appending(path: "MarcUITests-\(UUID().uuidString)"))
            : StorageLocations.applicationSupport()
        try locations.createDirectories()

        let appDatabase = try isUITesting ? AppDatabase.inMemory() : AppDatabase.open(at: locations.appDatabase)
        let workspaceRepository = GRDBWorkspaceRepository(database: appDatabase)
        let snapshot = try await workspaceRepository.load()

        let settingsStore = makeSettingsStore(isUITesting: isUITesting)
        let secrets = KeychainSecretStore()
        let credentialPrefix = isUITesting ? "dev.devleloper.Marc.uitests.credentials" : "dev.devleloper.Marc.credentials"
        let profileServices = ProfileServicesFactory(locations: locations, inMemory: isUITesting, credentialPrefix: credentialPrefix)
        let claude = ClaudeLanguageModelProvider(
            apiKey: { try? secrets.secret(for: KeychainSecretStore.anthropicAPIKey) },
            model: { settingsStore.load().claudeModel },
        )
        let services = SessionServices(
            workspaceRepository: workspaceRepository,
            archive: GRDBArchiveRepository(database: appDatabase),
            notes: GRDBNoteRepository(database: appDatabase),
            boosts: GRDBBoostRepository(database: appDatabase),
            settingsStore: settingsStore,
            secrets: secrets,
            suggestions: SearchSuggestionClient(),
            authenticator: DeviceOwnerAuthenticator(),
            languageModels: LanguageModelResolver(claude: claude, onDevice: OnDeviceLanguageModelProvider()),
            profileServices: { profileServices.services(for: $0) },
            removeProfileData: { profile in profileServices.removeData(for: profile) },
            extensionsDirectory: { locations.profileDirectory($0.id).appending(path: "Extensions", directoryHint: .isDirectory) },
            importers: makeImporters(),
            isUITesting: isUITesting,
        )
        let session = BrowserSession(snapshot: snapshot, services: services, engine: makeEngine(locations: locations))
        return AppEnvironment(session: session, updater: Updater(isEnabled: !isUITesting), isUITesting: isUITesting)
    }

    /// UI tests start from clean preferences without onboarding or network-dependent features.
    private static func makeSettingsStore(isUITesting: Bool) -> UserDefaultsSettingsStore {
        guard isUITesting else { return UserDefaultsSettingsStore() }
        let suite = "dev.devleloper.Marc.uitests"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = UserDefaultsSettingsStore(defaults: defaults)
        var settings = BrowserSettings()
        settings.hasCompletedOnboarding = true
        settings.isContentBlockingEnabled = false
        settings.showsSearchSuggestions = false
        store.save(settings)
        return store
    }

    private static func makeImporters() -> ImportServices {
        ImportServices(
            readHistory: { source, url in
                source == .safari
                    ? try ExternalHistoryReader.safariHistory(databaseAt: url)
                    : try ExternalHistoryReader.chromeHistory(databaseAt: url)
            },
            suggestedLocation: { source in
                switch source {
                case .arc: BrowserDataLocations.arcSidebar
                case .chrome: BrowserDataLocations.chromeBookmarks
                case .safari: BrowserDataLocations.safariBookmarks
                case .bookmarksFile: nil
                }
            },
        )
    }

    private static func makeEngine(locations: StorageLocations) -> WebEngine {
        let downloader = FilterListDownloader()
        let contentBlocker = ContentBlocker(directory: locations.contentBlockingDirectory) { source, etag in
            try await downloader.download(source, etag: etag)
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let favicons = FaviconLoader(directory: caches.appending(path: "Marc/Favicons", directoryHint: .isDirectory))
        return WebEngine(contentBlocker: contentBlocker, favicons: favicons)
    }
}

/// Opens each profile's database on first use and removes a profile's data when it is deleted.
@MainActor
private final class ProfileServicesFactory {
    private let locations: StorageLocations
    private let inMemory: Bool
    private let credentialPrefix: String
    private let logger = Logger(subsystem: "dev.devleloper.Marc", category: "Profiles")

    init(locations: StorageLocations, inMemory: Bool, credentialPrefix: String) {
        self.locations = locations
        self.inMemory = inMemory
        self.credentialPrefix = credentialPrefix
    }

    func services(for profile: Profile) -> ProfileServices {
        let database: ProfileDatabase
        do {
            database = try inMemory ? ProfileDatabase.inMemory() : ProfileDatabase.open(at: locations.profileDatabase(profile.id))
        } catch {
            // Keep the browser usable; browsing data of this session will not be saved.
            logger.error("Could not open the profile database: \(error.localizedDescription, privacy: .public)")
            database = try! ProfileDatabase.inMemory() // swiftlint:disable:this force_try
        }
        return ProfileServices(
            history: GRDBHistoryRepository(database: database),
            downloads: GRDBDownloadRepository(database: database),
            siteData: GRDBSiteDataRepository(database: database),
            credentials: KeychainCredentialStore(profileID: profile.id, servicePrefix: credentialPrefix),
        )
    }

    func removeData(for profile: Profile) {
        try? KeychainCredentialStore(profileID: profile.id, servicePrefix: credentialPrefix).deleteAll()
        do {
            try locations.removeProfileData(profile.id)
        } catch {
            logger.error("Could not remove profile data: \(error.localizedDescription, privacy: .public)")
        }
    }
}
