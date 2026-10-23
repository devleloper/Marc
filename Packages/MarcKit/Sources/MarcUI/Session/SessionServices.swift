import Foundation
import MarcCore
import MarcWebKit

/// Browsing-data services of one profile.
public struct ProfileServices {
    public let history: any HistoryRepository
    public let downloads: any DownloadRepository
    public let siteData: any SiteDataRepository
    public let credentials: any CredentialStore

    public init(
        history: any HistoryRepository,
        downloads: any DownloadRepository,
        siteData: any SiteDataRepository,
        credentials: any CredentialStore,
    ) {
        self.history = history
        self.downloads = downloads
        self.siteData = siteData
        self.credentials = credentials
    }
}

/// Everything the UI needs from the outside world, assembled by the app's composition root.
public struct SessionServices {
    public let workspaceRepository: any WorkspaceRepository
    public let archive: any ArchiveRepository
    public let notes: any NoteRepository
    public let boosts: any BoostRepository
    public let settingsStore: any SettingsStore
    public let secrets: any SecretStore
    public let suggestions: any SearchSuggestionProvider
    public let authenticator: any UserAuthenticator
    public let languageModels: LanguageModelResolver
    /// Returns (creating on first use) the services of a profile.
    public let profileServices: (Profile) -> ProfileServices
    /// Deletes a profile's databases, passwords and files.
    public let removeProfileData: (Profile) async -> Void
    /// Where a profile's installed web extensions are stored.
    public let extensionsDirectory: (Profile) -> URL
    public let importers: ImportServices
    public let filterLists: [FilterListSource]
    public let isUITesting: Bool

    public init(
        workspaceRepository: any WorkspaceRepository,
        archive: any ArchiveRepository,
        notes: any NoteRepository,
        boosts: any BoostRepository,
        settingsStore: any SettingsStore,
        secrets: any SecretStore,
        suggestions: any SearchSuggestionProvider,
        authenticator: any UserAuthenticator,
        languageModels: LanguageModelResolver,
        profileServices: @escaping (Profile) -> ProfileServices,
        removeProfileData: @escaping (Profile) async -> Void,
        extensionsDirectory: @escaping (Profile) -> URL,
        importers: ImportServices,
        filterLists: [FilterListSource] = FilterListSource.all,
        isUITesting: Bool = false,
    ) {
        self.workspaceRepository = workspaceRepository
        self.archive = archive
        self.notes = notes
        self.boosts = boosts
        self.settingsStore = settingsStore
        self.secrets = secrets
        self.suggestions = suggestions
        self.authenticator = authenticator
        self.languageModels = languageModels
        self.profileServices = profileServices
        self.removeProfileData = removeProfileData
        self.extensionsDirectory = extensionsDirectory
        self.importers = importers
        self.filterLists = filterLists
        self.isUITesting = isUITesting
    }
}

/// Reads other browsers' data. File access happens through user-selected URLs.
public struct ImportServices {
    public let readHistory: (BrowserImport.Source, URL) throws -> [ImportedHistoryEntry]
    public let suggestedLocation: (BrowserImport.Source) -> URL?

    public init(
        readHistory: @escaping (BrowserImport.Source, URL) throws -> [ImportedHistoryEntry],
        suggestedLocation: @escaping (BrowserImport.Source) -> URL?,
    ) {
        self.readHistory = readHistory
        self.suggestedLocation = suggestedLocation
    }
}
