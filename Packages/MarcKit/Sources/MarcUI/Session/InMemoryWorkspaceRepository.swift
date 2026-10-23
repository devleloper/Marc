import Foundation
import MarcCore
import MarcWebKit

/// Backs windows whose tabs must not be saved: incognito, blank and Little windows.
struct InMemoryWorkspaceRepository: WorkspaceRepository {
    func load() async throws -> WorkspaceSnapshot {
        WorkspaceSnapshot(workspace: Workspace(), windows: [])
    }

    func apply(_ changes: WorkspaceChanges) async throws {}

    func saveWindows(_ windows: [WindowState]) async throws {}
}

extension Workspace {
    /// A one-Space workspace for a window that keeps its tabs to itself.
    static func ephemeral(named name: String, profile: Profile, theme: Theme) -> Workspace {
        let space = Space(profileID: profile.id, name: name, icon: .symbol("rectangle.on.rectangle"), theme: theme)
        return Workspace(profiles: [profile], spaces: [space])
    }
}
