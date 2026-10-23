import Foundation

/// Stores saved logins. Passwords are kept in a secure store and only returned on request.
public protocol CredentialStore: Sendable {
    func credentials(for origin: String) async throws -> [Credential]
    func allCredentials() async throws -> [Credential]
    func password(for credential: Credential) async throws -> String?
    func save(_ credential: Credential, password: String) async throws
    func delete(_ credential: Credential) async throws
    func markUsed(_ credential: Credential, at date: Date) async throws
}

/// Small secrets such as API keys.
public protocol SecretStore: Sendable {
    func secret(for key: String) throws -> String?
    func setSecret(_ value: String?, for key: String) throws
}

public protocol SettingsStore: Sendable {
    func load() -> BrowserSettings
    func save(_ settings: BrowserSettings)
}

public protocol SearchSuggestionProvider: Sendable {
    func suggestions(for query: String, engine: SearchEngine) async throws -> [String]
}

/// Requests user presence (Touch ID or password) before revealing secrets.
public protocol UserAuthenticator: Sendable {
    func authenticate(reason: String) async -> Bool
}
