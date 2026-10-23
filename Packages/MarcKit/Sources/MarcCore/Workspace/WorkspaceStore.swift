import Foundation
import Observation
import os

/// The single source of truth for the workspace. Views observe `workspace`; every change goes
/// through `update(_:)`, which applies a pure mutation, diffs the result and persists the
/// difference in order, off the main actor.
@MainActor
@Observable
public final class WorkspaceStore {
    public private(set) var workspace: Workspace

    @ObservationIgnored private let repository: any WorkspaceRepository
    @ObservationIgnored private let writes = SerialTaskQueue()
    @ObservationIgnored private let logger = Logger.marc("WorkspaceStore")
    @ObservationIgnored public var onPersistenceError: ((any Error) -> Void)?

    public init(workspace: Workspace, repository: any WorkspaceRepository) {
        self.workspace = workspace
        self.repository = repository
    }

    /// Applies `mutation` to a copy of the workspace. If it throws, nothing changes.
    @discardableResult
    public func update<Result>(_ mutation: (inout Workspace) throws -> Result) rethrows -> Result {
        var copy = workspace
        let result = try mutation(&copy)
        let changes = WorkspaceChanges(from: workspace, to: copy)
        guard !changes.isEmpty else { return result }
        workspace = copy
        persist(changes)
        return result
    }

    /// Waits until every pending write has reached the repository.
    public func flush() async {
        await writes.drain()
    }

    private func persist(_ changes: WorkspaceChanges) {
        let repository = repository
        writes.enqueue { [weak self] in
            do {
                try await repository.apply(changes)
            } catch {
                await self?.report(error)
            }
        }
    }

    private func report(_ error: any Error) {
        logger.error("Failed to persist workspace changes: \(error.localizedDescription, privacy: .public)")
        onPersistenceError?(error)
    }
}

/// Runs asynchronous operations one after another in submission order.
@MainActor
public final class SerialTaskQueue {
    private var tail: Task<Void, Never>?

    public init() {}

    public func enqueue(_ operation: @escaping @Sendable () async -> Void) {
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
        }
    }

    public func drain() async {
        await tail?.value
    }
}

public extension Logger {
    static func marc(_ category: String) -> Logger {
        Logger(subsystem: "dev.devleloper.Marc", category: category)
    }
}
