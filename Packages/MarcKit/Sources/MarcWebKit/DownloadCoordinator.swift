import AppKit
import Foundation
import MarcCore
import Observation
import os
import WebKit

/// Tracks WebKit downloads: chooses safe destinations, reports progress and persists each
/// download in its profile's history.
@Observable
public final class DownloadCoordinator: NSObject {
    public private(set) var downloads: [Download] = []

    @ObservationIgnored public var onFinished: ((Download, Profile.ID?) -> Void)?
    @ObservationIgnored private var active: [ObjectIdentifier: ActiveDownload] = [:]
    @ObservationIgnored private let repository: (Profile.ID) -> (any DownloadRepository)?
    @ObservationIgnored private let directory: () -> URL
    @ObservationIgnored private let logger = Logger.marc("Downloads")

    private struct ActiveDownload {
        let id: Download.ID
        let profileID: Profile.ID?
        let download: WKDownload
        var observation: NSKeyValueObservation?
    }

    public init(
        directory: @escaping () -> URL = { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] },
        repository: @escaping (Profile.ID) -> (any DownloadRepository)?,
    ) {
        self.directory = directory
        self.repository = repository
    }

    public var activeCount: Int {
        downloads.count { $0.state.isActive }
    }

    /// Overall progress of active downloads, `nil` when nothing is downloading or sizes are unknown.
    public var overallProgress: Double? {
        let fractions = downloads.compactMap { $0.state.isActive ? $0.state.fractionCompleted : nil }
        guard !fractions.isEmpty else { return nil }
        return fractions.reduce(0, +) / Double(fractions.count)
    }

    /// Loads persisted downloads of a profile into the list.
    public func loadHistory(for profileID: Profile.ID) async {
        guard let stored = try? await repository(profileID)?.downloads(limit: 200) else { return }
        let known = Set(downloads.map(\.id))
        for download in stored {
            profileIDs[download.id] = profileID
        }
        downloads.append(contentsOf: stored.filter { !known.contains($0.id) }.map { download in
            var download = download
            // A download still marked active was interrupted by quitting.
            if download.state.isActive { download.state = .failed(message: "Interrupted") }
            return download
        })
        downloads.sort { $0.startedAt > $1.startedAt }
    }

    public func begin(_ download: WKDownload, profileID: Profile.ID?) {
        download.delegate = self
        let record = Download(
            sourceURL: download.originalRequest?.url,
            fileName: download.originalRequest?.url?.lastPathComponent ?? "Download",
        )
        var entry = ActiveDownload(id: record.id, profileID: profileID, download: download)
        entry.observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let received = progress.completedUnitCount
            let expected = progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
            Task { @MainActor in self?.updateProgress(record.id, received: received, expected: expected) }
        }
        active[ObjectIdentifier(download)] = entry
        if let profileID { profileIDs[record.id] = profileID }
        downloads.insert(record, at: 0)
    }

    public func cancel(_ id: Download.ID) {
        guard let entry = active.values.first(where: { $0.id == id }) else { return }
        entry.download.cancel { _ in }
        finish(entry.download, state: .cancelled)
    }

    public func reveal(_ id: Download.ID) {
        guard let url = downloads.first(where: { $0.id == id })?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func open(_ id: Download.ID) {
        guard let download = downloads.first(where: { $0.id == id }), download.state == .finished,
              let url = download.fileURL else { return }
        NSWorkspace.shared.open(url)
    }

    public func remove(_ id: Download.ID) {
        guard let index = downloads.firstIndex(where: { $0.id == id }), !downloads[index].state.isActive else { return }
        let download = downloads.remove(at: index)
        removePersisted(download.id)
    }

    public func clearFinished() {
        let finished = downloads.filter { !$0.state.isActive }
        downloads.removeAll { !$0.state.isActive }
        finished.forEach { removePersisted($0.id) }
    }

    /// Renames a finished download on disk (used by "tidy download names").
    public func rename(_ id: Download.ID, to fileName: String) {
        guard let index = downloads.firstIndex(where: { $0.id == id }), let url = downloads[index].fileURL,
              downloads[index].state == .finished else { return }
        let destination = Self.uniqueURL(in: url.deletingLastPathComponent(), fileName: fileName)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            downloads[index].fileURL = destination
            downloads[index].fileName = destination.lastPathComponent
            persist(downloads[index], profileID: profileID(for: id))
        } catch {
            logger.error("Rename failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internals

    private var profileIDs: [Download.ID: Profile.ID] = [:]

    private func profileID(for id: Download.ID) -> Profile.ID? {
        profileIDs[id]
    }

    private func updateProgress(_ id: Download.ID, received: Int64, expected: Int64?) {
        guard let index = downloads.firstIndex(where: { $0.id == id }), downloads[index].state.isActive else { return }
        downloads[index].state = .inProgress(receivedBytes: received, expectedBytes: expected)
    }

    private func finish(_ download: WKDownload, state: Download.State) {
        guard let entry = active.removeValue(forKey: ObjectIdentifier(download)),
              let index = downloads.firstIndex(where: { $0.id == entry.id })
        else { return }
        downloads[index].state = state
        downloads[index].finishedAt = .now
        let record = downloads[index]
        persist(record, profileID: entry.profileID)
        if state == .finished { onFinished?(record, entry.profileID) }
    }

    private func persist(_ download: Download, profileID: Profile.ID?) {
        guard let profileID else { return }
        profileIDs[download.id] = profileID
        let repository = repository(profileID)
        Task { try? await repository?.upsert(download) }
    }

    private func removePersisted(_ id: Download.ID) {
        guard let profileID = profileIDs[id] else { return }
        let repository = repository(profileID)
        Task { try? await repository?.remove([id]) }
    }

    /// A non-existing file URL in `directory`, adding " (n)" before the extension if needed.
    static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let sanitized = sanitize(fileName)
        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var candidate = directory.appending(path: sanitized)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = directory.appending(path: name)
            counter += 1
        }
        return candidate
    }

    /// Strips path components and characters macOS or Finder treat specially.
    static func sanitize(_ fileName: String) -> String {
        let lastComponent = (fileName as NSString).lastPathComponent
        let forbidden = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        let cleaned = lastComponent.unicodeScalars.filter { !forbidden.contains($0) }.map(String.init).joined()
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "Download" : String(cleaned.prefix(200))
    }
}

extension DownloadCoordinator: WKDownloadDelegate {
    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let destination = Self.uniqueURL(in: directory(), fileName: suggestedFilename)
        if let entry = active[ObjectIdentifier(download)], let index = downloads.firstIndex(where: { $0.id == entry.id }) {
            downloads[index].fileName = destination.lastPathComponent
            downloads[index].fileURL = destination
            persist(downloads[index], profileID: entry.profileID)
        }
        return destination
    }

    public func downloadDidFinish(_ download: WKDownload) {
        finish(download, state: .finished)
    }

    public func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        let nsError = error as NSError
        let state: Download.State = nsError.code == NSURLErrorCancelled ? .cancelled : .failed(message: nsError.localizedDescription)
        finish(download, state: state)
    }
}
