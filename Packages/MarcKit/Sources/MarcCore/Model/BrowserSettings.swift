import Foundation

/// User preferences. Decoding tolerates missing keys so that settings written by older versions
/// keep working when new preferences are added.
public struct BrowserSettings: Hashable, Sendable, Codable {
    public var searchEngineID = SearchEngine.google.id
    public var showsSearchSuggestions = true
    public var archiveInterval = ArchiveInterval.twelveHours
    public var memorySaverInterval = MemorySaverInterval.thirtyMinutes
    public var opensExternalLinksInLittleWindow = true
    public var isContentBlockingEnabled = true
    public var websiteAppearance = WebsiteAppearance.automatic
    public var appIcon = AppIconStyle.marc
    public var offersToSavePasswords = true
    public var requiresAuthenticationForPasswords = true
    public var aiProvider = AIProviderKind.automatic
    public var claudeModel = AIProviderKind.defaultClaudeModel
    public var tidiesTabTitles = false
    public var tidiesDownloadNames = false
    public var hasCompletedOnboarding = false
    public var showsHoveredLinkStatus = true
    /// Look up the address of a hovered link or the selected Command Bar result ahead of time.
    public var preloadsLinkAddresses = true
    /// Move a playing video into Picture in Picture when switching away from its tab, as Arc does.
    public var opensPictureInPictureAutomatically = true
    /// Origins for which the user chose "Never Save" when offered to save a password.
    public var neverSavePasswordOrigins: [String] = []

    public init() {}

    public var searchEngine: SearchEngine {
        SearchEngine.builtIn(id: searchEngineID)
    }

    private enum CodingKeys: String, CodingKey {
        case searchEngineID
        case showsSearchSuggestions
        case archiveInterval
        case memorySaverInterval
        case opensExternalLinksInLittleWindow
        case isContentBlockingEnabled
        case websiteAppearance
        case appIcon
        case offersToSavePasswords
        case requiresAuthenticationForPasswords
        case aiProvider
        case claudeModel
        case tidiesTabTitles
        case tidiesDownloadNames
        case hasCompletedOnboarding
        case showsHoveredLinkStatus
        case preloadsLinkAddresses
        case opensPictureInPictureAutomatically
        case neverSavePasswordOrigins
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BrowserSettings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        searchEngineID = value(.searchEngineID, defaults.searchEngineID)
        showsSearchSuggestions = value(.showsSearchSuggestions, defaults.showsSearchSuggestions)
        archiveInterval = value(.archiveInterval, defaults.archiveInterval)
        memorySaverInterval = value(.memorySaverInterval, defaults.memorySaverInterval)
        opensExternalLinksInLittleWindow = value(.opensExternalLinksInLittleWindow, defaults.opensExternalLinksInLittleWindow)
        isContentBlockingEnabled = value(.isContentBlockingEnabled, defaults.isContentBlockingEnabled)
        websiteAppearance = value(.websiteAppearance, defaults.websiteAppearance)
        appIcon = value(.appIcon, defaults.appIcon)
        offersToSavePasswords = value(.offersToSavePasswords, defaults.offersToSavePasswords)
        requiresAuthenticationForPasswords = value(.requiresAuthenticationForPasswords, defaults.requiresAuthenticationForPasswords)
        aiProvider = value(.aiProvider, defaults.aiProvider)
        claudeModel = value(.claudeModel, defaults.claudeModel)
        tidiesTabTitles = value(.tidiesTabTitles, defaults.tidiesTabTitles)
        tidiesDownloadNames = value(.tidiesDownloadNames, defaults.tidiesDownloadNames)
        hasCompletedOnboarding = value(.hasCompletedOnboarding, defaults.hasCompletedOnboarding)
        showsHoveredLinkStatus = value(.showsHoveredLinkStatus, defaults.showsHoveredLinkStatus)
        preloadsLinkAddresses = value(.preloadsLinkAddresses, defaults.preloadsLinkAddresses)
        opensPictureInPictureAutomatically = value(.opensPictureInPictureAutomatically, defaults.opensPictureInPictureAutomatically)
        neverSavePasswordOrigins = value(.neverSavePasswordOrigins, defaults.neverSavePasswordOrigins)
    }
}

/// The icon Marc shows in the Dock and the app switcher while it runs.
public enum AppIconStyle: String, Hashable, Sendable, Codable, CaseIterable {
    /// The white tile: the app's own icon.
    case marc
    /// The deep indigo tile.
    case aurora
    /// Marc in light appearance, Aurora in dark appearance.
    case matchAppearance

    /// Asset names of the two icon images.
    public static let marcImageName = "AppIconMarc"
    public static let auroraImageName = "AppIconAurora"

    public var displayName: String {
        switch self {
        case .marc: "Marc"
        case .aurora: "Aurora"
        case .matchAppearance: "Match Appearance"
        }
    }

    /// The image to show for the current appearance, or `nil` for the app's own icon.
    public func imageName(isDarkAppearance: Bool) -> String? {
        switch self {
        case .marc: nil
        case .aurora: Self.auroraImageName
        case .matchAppearance: isDarkAppearance ? Self.auroraImageName : nil
        }
    }
}

public enum MemorySaverInterval: String, Hashable, Sendable, Codable, CaseIterable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case fourHours
    case never

    public var duration: TimeInterval? {
        switch self {
        case .fifteenMinutes: 15 * 60
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .fourHours: 4 * 60 * 60
        case .never: nil
        }
    }

    public var displayName: String {
        switch self {
        case .fifteenMinutes: "After 15 minutes"
        case .thirtyMinutes: "After 30 minutes"
        case .oneHour: "After 1 hour"
        case .fourHours: "After 4 hours"
        case .never: "Never"
        }
    }
}

public enum WebsiteAppearance: String, Hashable, Sendable, Codable, CaseIterable {
    case automatic
    case light
    case dark

    public var displayName: String {
        rawValue.capitalized
    }
}

public enum AIProviderKind: String, Hashable, Sendable, Codable, CaseIterable {
    /// On-device model when available, otherwise Claude when an API key is configured.
    case automatic
    case claude
    case onDevice
    case off

    public static let defaultClaudeModel = ClaudeModel.opus.rawValue

    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .claude: "Claude"
        case .onDevice: "On-Device (Apple Intelligence)"
        case .off: "Off"
        }
    }
}
