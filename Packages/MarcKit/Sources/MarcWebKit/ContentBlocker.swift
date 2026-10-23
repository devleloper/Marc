import Foundation
import MarcCore
import Observation
import os
import WebKit

/// Downloads filter lists, converts them to WebKit rule lists and keeps the compiled lists.
@Observable
public final class ContentBlocker {
    public enum Status: Equatable {
        case idle
        case updating
        case ready(ruleCount: Int, updatedAt: Date?)
        case failed(String)
    }

    public private(set) var ruleLists: [WKContentRuleList] = []
    public private(set) var status = Status.idle

    @ObservationIgnored public var onRuleListsChanged: (() -> Void)?
    @ObservationIgnored private let store: WKContentRuleListStore
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fetch: @Sendable (FilterListSource, String?) async throws -> FilterListFetchResult
    @ObservationIgnored private let logger = Logger.marc("ContentBlocker")
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    static let builtInIdentifier = "marc.builtin"
    static let subscriptionsIdentifier = "marc.subscriptions"
    static let refreshInterval: TimeInterval = 4 * 24 * 60 * 60

    public init(directory: URL, fetch: @escaping @Sendable (FilterListSource, String?) async throws -> FilterListFetchResult) {
        self.directory = directory
        self.fetch = fetch
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = WKContentRuleListStore(url: directory.appending(path: "Compiled", directoryHint: .isDirectory)) ?? .default()
    }

    /// Loads compiled lists, compiling the built-in rules if needed, then refreshes stale
    /// subscriptions in the background.
    public func start(sources: [FilterListSource]) {
        refreshTask?.cancel()
        refreshTask = Task {
            var lists: [WKContentRuleList] = []
            var builtIn = await compiledList(Self.builtInIdentifier)
            if builtIn == nil {
                builtIn = try? await compile([FilterListSource.builtInRules], identifier: Self.builtInIdentifier)
            }
            if let builtIn { lists.append(builtIn) }
            if let subscriptions = await compiledList(Self.subscriptionsIdentifier) {
                lists.append(subscriptions)
            }
            publish(lists, updatedAt: manifest.updatedAt)
            if manifest.isStale(for: sources, interval: Self.refreshInterval) {
                await refresh(sources: sources)
            }
        }
    }

    /// Downloads (conditionally) and recompiles the subscribed lists.
    public func refresh(sources: [FilterListSource]) async {
        status = .updating
        var manifest = manifest
        var texts: [String] = []
        for source in sources {
            let cacheURL = directory.appending(path: "\(source.id).txt")
            do {
                switch try await fetch(source, manifest.etags[source.id]) {
                case let .updated(contents, etag):
                    try contents.write(to: cacheURL, atomically: true, encoding: .utf8)
                    manifest.etags[source.id] = etag
                    texts.append(contents)
                case .notModified:
                    if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) { texts.append(cached) }
                }
            } catch {
                logger.error("Failed to download \(source.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
                if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) { texts.append(cached) }
            }
        }

        do {
            var lists = ruleLists.filter { $0.identifier == Self.builtInIdentifier }
            if texts.isEmpty {
                try? await store.removeContentRuleList(forIdentifier: Self.subscriptionsIdentifier)
            } else {
                try await lists.append(compile(texts, identifier: Self.subscriptionsIdentifier))
            }
            manifest.updatedAt = .now
            manifest.sourceIDs = sources.map(\.id)
            self.manifest = manifest
            publish(lists, updatedAt: manifest.updatedAt)
        } catch {
            logger.error("Failed to compile rules: \(error.localizedDescription, privacy: .public)")
            status = .failed(error.localizedDescription)
        }
    }

    private func compile(_ lists: [String], identifier: String) async throws -> WKContentRuleList {
        let converted = try await Task.detached(priority: .utility) {
            try FilterListConverter().convert(lists)
        }.value
        logger.info("Compiling \(converted.ruleCount) rules (\(converted.skippedLineCount) lines skipped)")
        guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: converted.json) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return list
    }

    private func compiledList(_ identifier: String) async -> WKContentRuleList? {
        try? await store.contentRuleList(forIdentifier: identifier)
    }

    private func publish(_ lists: [WKContentRuleList], updatedAt: Date?) {
        ruleLists = lists
        status = .ready(ruleCount: lists.count, updatedAt: updatedAt)
        onRuleListsChanged?()
    }

    // MARK: - Manifest

    private struct Manifest: Codable {
        var etags: [String: String] = [:]
        var updatedAt: Date?
        var sourceIDs: [String] = []

        func isStale(for sources: [FilterListSource], interval: TimeInterval) -> Bool {
            guard let updatedAt, Set(sourceIDs) == Set(sources.map(\.id)) else { return true }
            return Date.now.timeIntervalSince(updatedAt) > interval
        }
    }

    private var manifestURL: URL {
        directory.appending(path: "manifest.json")
    }

    private var manifest: Manifest {
        get {
            guard let data = try? Data(contentsOf: manifestURL) else { return Manifest() }
            return (try? JSONDecoder().decode(Manifest.self, from: data)) ?? Manifest()
        }
        set {
            try? JSONEncoder().encode(newValue).write(to: manifestURL, options: .atomic)
        }
    }
}
