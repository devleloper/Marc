import Foundation
import MarcCore
import WebKit

/// WebKit state shared by every tab of a profile: its isolated website data store and its web
/// extension controller.
public final class ProfileWebContext {
    public let profileID: Profile.ID?
    public let dataStore: WKWebsiteDataStore
    public let extensionController: WKWebExtensionController?

    public var isIncognito: Bool {
        profileID == nil
    }

    public init(profile: Profile) {
        profileID = profile.id
        dataStore = WKWebsiteDataStore(forIdentifier: profile.dataStoreID)
        let configuration = WKWebExtensionController.Configuration(identifier: profile.dataStoreID)
        extensionController = WKWebExtensionController(configuration: configuration)
    }

    /// A context whose data lives only in memory and disappears with its last window.
    /// Extensions are disabled in incognito windows.
    public init(incognito: Void = ()) {
        profileID = nil
        dataStore = .nonPersistent()
        extensionController = nil
    }

    func makeConfiguration(applicationName: String, autoplayAllowed: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.userContentController = WKUserContentController()
        configuration.applicationNameForUserAgent = applicationName
        configuration.upgradeKnownHostsToHTTPS = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = autoplayAllowed ? [] : .audio
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.isTextInteractionEnabled = true
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let extensionController {
            configuration.webExtensionController = extensionController
        }
        return configuration
    }

    /// Removes every kind of website data stored for `host` and its subdomains.
    public func removeData(forHost host: String, types: Set<String> = WKWebsiteDataStore.allWebsiteDataTypes()) async {
        let records = await dataStore.dataRecords(ofTypes: types)
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let matching = records.filter { record in
            record.displayName == domain || record.displayName.hasSuffix("." + domain) || domain.hasSuffix("." + record.displayName)
        }
        guard !matching.isEmpty else { return }
        await dataStore.removeData(ofTypes: types, for: matching)
    }

    public func removeAllData(modifiedSince date: Date = .distantPast) async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: date)
    }

    /// Number of sites with stored data, for the privacy settings summary.
    public func siteCount() async -> Int {
        await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()).count
    }
}

public extension WKWebsiteDataStore {
    static var cookieTypes: Set<String> {
        [WKWebsiteDataTypeCookies]
    }

    static var cacheTypes: Set<String> {
        [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache, WKWebsiteDataTypeOfflineWebApplicationCache]
    }
}
