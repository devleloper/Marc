import Foundation
import LocalAuthentication
import MarcCore

/// Touch ID, Apple Watch or the account password.
public struct DeviceOwnerAuthenticator: UserAuthenticator {
    public init() {}

    public func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Macs without a passcode cannot gate access; refuse rather than reveal silently.
            return false
        }
        return await (try? context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Settings stored as JSON in user defaults.
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; it is not annotated Sendable.
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "BrowserSettings") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> BrowserSettings {
        guard let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(BrowserSettings.self, from: data) else {
            return BrowserSettings()
        }
        return settings
    }

    public func save(_ settings: BrowserSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Fetches OpenSearch suggestion JSON (`[query, [suggestion, …]]`).
public struct SearchSuggestionClient: SearchSuggestionProvider {
    private let session: URLSession

    public init(session: URLSession = SearchSuggestionClient.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public func suggestions(for query: String, engine: SearchEngine) async throws -> [String] {
        guard let url = engine.suggestionsURL(for: query) else { return [] }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return Self.parse(data)
    }

    static func parse(_ data: Data) -> [String] {
        let object = (try? JSONSerialization.jsonObject(with: data))
            ?? String(data: data, encoding: .isoLatin1).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
        guard let array = object as? [Any], array.count >= 2, let suggestions = array[1] as? [Any] else { return [] }
        return suggestions.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
}

/// Downloads subscribed filter lists with conditional requests.
public struct FilterListDownloader: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(_ source: FilterListSource, etag: String?) async throws -> FilterListFetchResult {
        var request = URLRequest(url: source.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 304 { return .notModified }
        guard http.statusCode == 200, let contents = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }
        return .updated(contents: contents, etag: http.value(forHTTPHeaderField: "ETag"))
    }
}

/// Well-known locations of other browsers' data, used to preselect files in open panels.
public enum BrowserDataLocations {
    static var home: URL {
        // Inside the sandbox the home directory points into the container; the real one comes
        // from the password database.
        if let directory = getpwuid(getuid())?.pointee.pw_dir {
            return URL(fileURLWithFileSystemRepresentation: directory, isDirectory: true, relativeTo: nil)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static var arcSidebar: URL {
        home.appending(path: "Library/Application Support/Arc/StorableSidebar.json")
    }

    public static var chromeBookmarks: URL {
        home.appending(path: "Library/Application Support/Google/Chrome/Default/Bookmarks")
    }

    public static var chromeHistory: URL {
        home.appending(path: "Library/Application Support/Google/Chrome/Default/History")
    }

    public static var safariBookmarks: URL {
        home.appending(path: "Library/Safari/Bookmarks.plist")
    }

    public static var safariHistory: URL {
        home.appending(path: "Library/Safari/History.db")
    }
}
