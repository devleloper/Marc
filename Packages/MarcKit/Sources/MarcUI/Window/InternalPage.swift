import Foundation
import MarcWebKit

/// Native pages addressed with `marc://` URLs. They live in the sidebar like web tabs but are
/// rendered with SwiftUI and never reach WebKit.
public enum InternalPage: String, CaseIterable, Sendable {
    case history
    case archive
    case downloads

    public static let scheme = "marc"

    public init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host(percentEncoded: false),
              let page = InternalPage(rawValue: host) else { return nil }
        self = page
    }

    public var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    public var title: String {
        switch self {
        case .history: "History"
        case .archive: "Archive"
        case .downloads: "Downloads"
        }
    }

    public var symbol: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .archive: "archivebox"
        case .downloads: "arrow.down.circle"
        }
    }
}
