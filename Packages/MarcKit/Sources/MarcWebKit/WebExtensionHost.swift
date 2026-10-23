import AppKit
import Foundation
import MarcCore
import Observation
import os
import WebKit

/// Browser-side decisions extensions depend on.
@MainActor
public protocol WebExtensionHostDelegate: AnyObject {
    func openWindows(for host: WebExtensionHost) -> [any WKWebExtensionWindow]
    func focusedWindow(for host: WebExtensionHost) -> (any WKWebExtensionWindow)?
    func host(_ host: WebExtensionHost, openTabWith configuration: WKWebExtension.TabConfiguration) -> (any WKWebExtensionTab)?
    func host(_ host: WebExtensionHost, openWindowWith configuration: WKWebExtension.WindowConfiguration) -> (any WKWebExtensionWindow)?
    func host(_ host: WebExtensionHost, openOptionsPage url: URL)
    func host(_ host: WebExtensionHost, confirm title: String, details: String) async -> Bool
    func host(_ host: WebExtensionHost, presentPopover popover: NSPopover)
}

/// Installs and runs web extensions for one profile.
@Observable
public final class WebExtensionHost: NSObject {
    public struct Installed: Identifiable, Codable, Hashable {
        public let id: String
        public var displayName: String
        public var version: String
        public var isEnabled: Bool
        /// Resource folder or archive inside Marc's storage.
        var resourcePath: String
        var grantedPermissions: [String]
        var grantedMatchPatterns: [String]
    }

    public enum InstallError: LocalizedError {
        case unreadableArchive
        case declined
        case invalid(String)

        public var errorDescription: String? {
            switch self {
            case .unreadableArchive: "The file is not a valid extension archive."
            case .declined: "Installation was cancelled."
            case let .invalid(message): message
            }
        }
    }

    public private(set) var installed: [Installed] = []
    public private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Bumped when actions change so views refresh icons and badges.
    public private(set) var actionsRevision = 0

    @ObservationIgnored public weak var delegate: (any WebExtensionHostDelegate)?
    @ObservationIgnored public let controller: WKWebExtensionController
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let logger = Logger.marc("Extensions")

    public init(controller: WKWebExtensionController, directory: URL) {
        self.controller = controller
        self.directory = directory
        super.init()
        controller.delegate = self
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Installation

    public func loadInstalled() async {
        installed = readManifest()
        for entry in installed where entry.isEnabled {
            do {
                try await load(entry)
            } catch {
                logger.error("Failed to load \(entry.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Installs an unpacked folder, a `.zip` or a `.crx` file after the user approves its permissions.
    @discardableResult
    public func install(from source: URL) async throws -> Installed {
        let id = UUID().uuidString
        let destination = try copyResources(from: source, id: id)
        let webExtension: WKWebExtension
        do {
            webExtension = try await WKWebExtension(resourceBaseURL: destination)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw InstallError.invalid(error.localizedDescription)
        }

        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        let patterns = webExtension.allRequestedMatchPatterns.map(\.string).sorted()
        let name = webExtension.displayName ?? source.deletingPathExtension().lastPathComponent
        var details = "Version \(webExtension.displayVersion ?? "?")"
        if !permissions.isEmpty { details += "\n\nPermissions: \(permissions.joined(separator: ", "))" }
        if !patterns.isEmpty { details += "\n\nSite access: \(patterns.joined(separator: ", "))" }
        if !webExtension.errors
            .isEmpty { details += "\n\nWarnings: \(webExtension.errors.map(\.localizedDescription).joined(separator: "; "))" }
        guard await delegate?.host(self, confirm: "Add “\(name)”?", details: details) == true else {
            try? FileManager.default.removeItem(at: destination)
            throw InstallError.declined
        }

        let entry = Installed(
            id: id,
            displayName: name,
            version: webExtension.displayVersion ?? "",
            isEnabled: true,
            resourcePath: destination.lastPathComponent,
            grantedPermissions: permissions,
            grantedMatchPatterns: patterns,
        )
        try await load(entry, preloaded: webExtension)
        installed.append(entry)
        writeManifest()
        return entry
    }

    public func setEnabled(_ id: String, _ isEnabled: Bool) async {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index].isEnabled = isEnabled
        writeManifest()
        if isEnabled {
            try? await load(installed[index])
        } else if let context = contexts.removeValue(forKey: id) {
            try? controller.unload(context)
        }
        actionsRevision += 1
    }

    public func uninstall(_ id: String) {
        if let context = contexts.removeValue(forKey: id) {
            try? controller.unload(context)
        }
        if let entry = installed.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: directory.appending(path: entry.resourcePath))
        }
        installed.removeAll { $0.id == id }
        writeManifest()
        actionsRevision += 1
    }

    /// Toolbar actions of enabled extensions for a tab.
    public func actions(for tab: (any WKWebExtensionTab)?) -> [(id: String, action: WKWebExtension.Action)] {
        installed.compactMap { entry in
            guard let context = contexts[entry.id], let action = context.action(for: tab) else { return nil }
            return (entry.id, action)
        }
    }

    public func performAction(_ id: String, for tab: (any WKWebExtensionTab)?) {
        contexts[id]?.performAction(for: tab)
    }

    public func optionsPageURL(for id: String) -> URL? {
        contexts[id]?.optionsPageURL
    }

    private func load(_ entry: Installed, preloaded: WKWebExtension? = nil) async throws {
        let url = directory.appending(path: entry.resourcePath)
        let webExtension: WKWebExtension = if let preloaded {
            preloaded
        } else {
            try await WKWebExtension(resourceBaseURL: url)
        }
        let context = WKWebExtensionContext(for: webExtension)
        // A stable identifier keeps the extension's storage across launches.
        context.uniqueIdentifier = entry.id
        context.isInspectable = true
        for permission in entry.grantedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: permission))
        }
        for patternString in entry.grantedMatchPatterns {
            if let pattern = try? WKWebExtension.MatchPattern(string: patternString) {
                context.setPermissionStatus(.grantedExplicitly, for: pattern)
            }
        }
        try controller.load(context)
        contexts[entry.id] = context
        actionsRevision += 1
    }

    // MARK: - Storage

    private func copyResources(from source: URL, id: String) throws -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false), isDirectory: &isDirectory)
        else { throw InstallError.unreadableArchive }
        if isDirectory.boolValue {
            let destination = directory.appending(path: id, directoryHint: .isDirectory)
            try fileManager.copyItem(at: source, to: destination)
            return destination
        }
        let data = try Data(contentsOf: source)
        let archive = source.pathExtension.lowercased() == "crx" ? try CRXArchive.zipData(from: data) : data
        let destination = directory.appending(path: "\(id).zip")
        try archive.write(to: destination, options: .atomic)
        return destination
    }

    private var manifestURL: URL {
        directory.appending(path: "extensions.json")
    }

    private func readManifest() -> [Installed] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([Installed].self, from: data)) ?? []
    }

    private func writeManifest() {
        try? JSONEncoder().encode(installed).write(to: manifestURL, options: .atomic)
    }
}

extension WebExtensionHost: WKWebExtensionControllerDelegate {
    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext,
    ) -> [any WKWebExtensionWindow] {
        delegate?.openWindows(for: self) ?? []
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext,
    ) -> (any WKWebExtensionWindow)? {
        delegate?.focusedWindow(for: self)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
    ) async throws -> (any WKWebExtensionTab)? {
        delegate?.host(self, openTabWith: configuration)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
    ) async throws -> (any WKWebExtensionWindow)? {
        delegate?.host(self, openWindowWith: configuration)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
    ) async throws {
        if let url = extensionContext.optionsPageURL {
            delegate?.host(self, openOptionsPage: url)
        }
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
    ) async -> (Set<WKWebExtension.Permission>, Date?) {
        let name = extensionContext.webExtension.displayName ?? "An extension"
        let allowed = await delegate?.host(
            self,
            confirm: "\(name) requests more permissions",
            details: permissions.map(\.rawValue).sorted().joined(separator: ", "),
        ) ?? false
        if allowed { remember(permissions: permissions.map(\.rawValue), patterns: [], for: extensionContext) }
        return (allowed ? permissions : [], nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
    ) async -> (Set<URL>, Date?) {
        let name = extensionContext.webExtension.displayName ?? "An extension"
        let hosts = urls.compactMap { $0.host(percentEncoded: false) }.sorted().joined(separator: ", ")
        let allowed = await delegate?.host(self, confirm: "Allow \(name) to access these sites?", details: hosts) ?? false
        return (allowed ? urls : [], nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
    ) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let name = extensionContext.webExtension.displayName ?? "An extension"
        let allowed = await delegate?.host(
            self,
            confirm: "Allow \(name) to access these sites?",
            details: matchPatterns.map(\.string).sorted().joined(separator: ", "),
        ) ?? false
        if allowed { remember(permissions: [], patterns: matchPatterns.map(\.string), for: extensionContext) }
        return (allowed ? matchPatterns : [], nil)
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext context: WKWebExtensionContext,
    ) {
        actionsRevision += 1
    }

    public func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for context: WKWebExtensionContext,
    ) async throws {
        guard let popover = action.popupPopover else { return }
        delegate?.host(self, presentPopover: popover)
    }

    private func remember(permissions: [String], patterns: [String], for context: WKWebExtensionContext) {
        guard let index = installed.firstIndex(where: { $0.id == context.uniqueIdentifier }) else { return }
        installed[index].grantedPermissions = Array(Set(installed[index].grantedPermissions + permissions)).sorted()
        installed[index].grantedMatchPatterns = Array(Set(installed[index].grantedMatchPatterns + patterns)).sorted()
        writeManifest()
    }
}

/// Chrome extension packages are ZIP archives with a signed header.
enum CRXArchive {
    static func zipData(from data: Data) throws -> Data {
        guard data.count > 16, data.prefix(4) == Data("Cr24".utf8) else { throw WebExtensionHost.InstallError.unreadableArchive }
        func uint32(at offset: Int) -> Int {
            data.subdata(in: offset ..< offset + 4).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        }
        let start: Int = switch uint32(at: 4) {
        case 2: 16 + uint32(at: 8) + uint32(at: 12)
        case 3: 12 + uint32(at: 8)
        default: throw WebExtensionHost.InstallError.unreadableArchive
        }
        guard start < data.count else { throw WebExtensionHost.InstallError.unreadableArchive }
        let zip = data.subdata(in: start ..< data.count)
        guard zip.prefix(2) == Data("PK".utf8) else { throw WebExtensionHost.InstallError.unreadableArchive }
        return zip
    }
}
