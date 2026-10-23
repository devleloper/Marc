import Foundation
import MarcCore

/// File-system layout of Marc's data inside Application Support (the app container when
/// sandboxed).
public struct StorageLocations: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func applicationSupport(fileManager: FileManager = .default) throws -> StorageLocations {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return StorageLocations(root: base.appending(path: "Marc", directoryHint: .isDirectory))
    }

    public var appDatabase: URL {
        root.appending(path: "Marc.sqlite")
    }

    public func profileDirectory(_ profileID: Profile.ID) -> URL {
        root.appending(path: "Profiles/\(profileID.rawValue.uuidString)", directoryHint: .isDirectory)
    }

    public func profileDatabase(_ profileID: Profile.ID) -> URL {
        profileDirectory(profileID).appending(path: "Profile.sqlite")
    }

    public var extensionsDirectory: URL {
        root.appending(path: "Extensions", directoryHint: .isDirectory)
    }

    public var contentBlockingDirectory: URL {
        root.appending(path: "ContentBlocking", directoryHint: .isDirectory)
    }

    public func createDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, extensionsDirectory, contentBlockingDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func removeProfileData(_ profileID: Profile.ID, fileManager: FileManager = .default) throws {
        let directory = profileDirectory(profileID)
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
    }
}
