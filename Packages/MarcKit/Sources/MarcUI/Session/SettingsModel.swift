import Foundation
import MarcCore
import MarcWebKit
import Observation

/// Observable user preferences, saved on every change.
@Observable
public final class SettingsModel {
    public var settings: BrowserSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            onChange?(oldValue, settings)
        }
    }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored var onChange: ((BrowserSettings, BrowserSettings) -> Void)?

    public init(store: any SettingsStore) {
        self.store = store
        settings = store.load()
    }
}

/// Synchronous access to per-site settings and permissions, backed by the profile database.
/// Values are loaded once per profile and kept in memory; writes go through to the database.
@Observable
final class SitePreferencesCache {
    private var settings: [Profile.ID: [String: SiteSettings]] = [:]
    private var permissions: [Profile.ID: [String: [SitePermissionKind: PermissionDecision]]] = [:]
    @ObservationIgnored private var loaded: Set<Profile.ID> = []

    func load(_ profileID: Profile.ID, from repository: any SiteDataRepository) async {
        guard loaded.insert(profileID).inserted else { return }
        let allSettings = await (try? repository.allSettings()) ?? []
        let allPermissions = await (try? repository.allPermissions()) ?? []
        settings[profileID] = Dictionary(allSettings.map { ($0.host, $0) }) { _, latest in latest }
        var grouped: [String: [SitePermissionKind: PermissionDecision]] = [:]
        for permission in allPermissions {
            grouped[permission.host, default: [:]][permission.kind] = permission.decision
        }
        permissions[profileID] = grouped
    }

    func settings(for host: String, profileID: Profile.ID?) -> SiteSettings {
        guard let profileID else { return SiteSettings(host: host) }
        return settings[profileID]?[host.lowercased()] ?? SiteSettings(host: host.lowercased())
    }

    func decision(for host: String, kind: SitePermissionKind, profileID: Profile.ID?) -> PermissionDecision? {
        guard let profileID else { return nil }
        return permissions[profileID]?[host.lowercased()]?[kind]
    }

    func permissions(for host: String, profileID: Profile.ID?) -> [SitePermissionKind: PermissionDecision] {
        guard let profileID else { return [:] }
        return permissions[profileID]?[host.lowercased()] ?? [:]
    }

    func update(_ newSettings: SiteSettings, profileID: Profile.ID, repository: any SiteDataRepository) {
        settings[profileID, default: [:]][newSettings.host.lowercased()] = newSettings
        Task { try? await repository.saveSettings(newSettings) }
    }

    func setDecision(
        _ decision: PermissionDecision?,
        for host: String,
        kind: SitePermissionKind,
        profileID: Profile.ID,
        repository: any SiteDataRepository,
    ) {
        permissions[profileID, default: [:]][host.lowercased(), default: [:]][kind] = decision
        Task { try? await repository.setPermission(decision, for: host, kind: kind) }
    }

    func clear(host: String, profileID: Profile.ID, repository: any SiteDataRepository) {
        settings[profileID]?[host.lowercased()] = nil
        permissions[profileID]?[host.lowercased()] = nil
        Task { try? await repository.removeAll(for: host) }
    }
}
