import AppKit
import CryptoKit
import Foundation
import MarcCore
import os

/// Downloads and caches favicons in memory and on disk. Requests use an ephemeral session
/// without cookies so that fetching icons does not leak browsing state.
public final class FaviconLoader {
    private let memory = NSCache<NSURL, NSImage>()
    private let directory: URL
    private let session: URLSession
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    private let logger = Logger.marc("Favicons")

    public init(directory: URL) {
        self.directory = directory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
        memory.countLimit = 500
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func cachedImage(for url: URL) -> NSImage? {
        if let image = memory.object(forKey: url as NSURL) { return image }
        guard let data = try? Data(contentsOf: fileURL(for: url)), let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    public func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return await task.value }
        let task = Task { await fetch(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        return image
    }

    private func fetch(_ url: URL) async -> NSImage? {
        let data: Data
        if url.scheme == "data" {
            guard let decoded = try? Data(contentsOf: url) else { return nil }
            data = decoded
        } else {
            guard let (downloaded, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  downloaded.count < 2_000_000
            else { return nil }
            data = downloaded
        }
        guard let image = NSImage(data: data), image.isValid, image.size.width > 0 else { return nil }
        memory.setObject(image, forKey: url as NSURL)
        do {
            try data.write(to: fileURL(for: url), options: .atomic)
        } catch {
            logger.debug("Could not cache favicon: \(error.localizedDescription, privacy: .public)")
        }
        return image
    }

    private func fileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: digest)
    }

    public func removeAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
