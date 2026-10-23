import Foundation
import MarcCore
import Security

/// Thin wrapper over generic-password Keychain items.
///
/// Items are created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so they never sync or
/// migrate to another device and are unreadable while the Mac is locked. Community builds are
/// ad-hoc signed and therefore cannot use the data-protection keychain (it requires an
/// application identifier); macOS may ask the user to confirm access after the app is rebuilt.
struct Keychain: Sendable {
    let service: String

    enum Error: Swift.Error, Equatable {
        case unexpectedStatus(OSStatus)
        case malformedItem
    }

    struct Item {
        let account: String
        let label: String?
        let metadata: Data?
    }

    func save(account: String, secret: Data, label: String? = nil, metadata: Data? = nil) throws {
        var attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let label { attributes[kSecAttrLabel as String] = label }
        if let metadata { attributes[kSecAttrGeneric as String] = metadata }

        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let query = baseQuery(account: account).merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Error.unexpectedStatus(addStatus) }
        default:
            throw Error.unexpectedStatus(status)
        }
    }

    func secret(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw Error.malformedItem }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Error.unexpectedStatus(status)
        }
    }

    func items() throws -> [Item] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let entries = result as? [[String: Any]] else { throw Error.malformedItem }
            return entries.compactMap { entry in
                guard let account = entry[kSecAttrAccount as String] as? String else { return nil }
                return Item(
                    account: account,
                    label: entry[kSecAttrLabel as String] as? String,
                    metadata: entry[kSecAttrGeneric as String] as? Data,
                )
            }
        case errSecItemNotFound:
            return []
        default:
            throw Error.unexpectedStatus(status)
        }
    }

    func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.unexpectedStatus(status) }
    }

    func deleteAll() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.unexpectedStatus(status) }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// API keys and other small secrets.
public struct KeychainSecretStore: SecretStore {
    private let keychain: Keychain

    public init(service: String = "dev.devleloper.Marc.secrets") {
        keychain = Keychain(service: service)
    }

    public func secret(for key: String) throws -> String? {
        try keychain.secret(account: key).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func setSecret(_ value: String?, for key: String) throws {
        if let value, !value.isEmpty {
            try keychain.save(account: key, secret: Data(value.utf8), label: "Marc – \(key)")
        } else {
            try keychain.delete(account: key)
        }
    }

    public static let anthropicAPIKey = "anthropic-api-key"
}

/// Saved passwords of one profile. Metadata (origin, username, dates) lives in the item's
/// generic attribute so that listing logins never reads a password.
public struct KeychainCredentialStore: CredentialStore {
    private let keychain: Keychain

    public init(profileID: Profile.ID, servicePrefix: String = "dev.devleloper.Marc.credentials") {
        keychain = Keychain(service: "\(servicePrefix).\(profileID.rawValue.uuidString)")
    }

    public func credentials(for origin: String) async throws -> [Credential] {
        try await allCredentials().filter { $0.origin == origin }
    }

    public func allCredentials() async throws -> [Credential] {
        let decoder = JSONDecoder()
        return try keychain.items()
            .compactMap { item in item.metadata.flatMap { try? decoder.decode(Credential.self, from: $0) } }
            .sorted { ($0.origin, $0.username) < ($1.origin, $1.username) }
    }

    public func password(for credential: Credential) async throws -> String? {
        try keychain.secret(account: credential.id.rawValue.uuidString).flatMap { String(data: $0, encoding: .utf8) }
    }

    public func save(_ credential: Credential, password: String) async throws {
        try keychain.save(
            account: credential.id.rawValue.uuidString,
            secret: Data(password.utf8),
            label: "Marc – \(credential.origin)",
            metadata: JSONEncoder().encode(credential),
        )
    }

    public func delete(_ credential: Credential) async throws {
        try keychain.delete(account: credential.id.rawValue.uuidString)
    }

    public func markUsed(_ credential: Credential, at date: Date) async throws {
        guard let password = try await password(for: credential) else { return }
        var updated = credential
        updated.lastUsedAt = date
        try await save(updated, password: password)
    }

    /// Removes every saved password of the profile.
    public func deleteAll() throws {
        try keychain.deleteAll()
    }
}
