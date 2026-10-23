import Foundation

public enum SitePermissionKind: String, Hashable, Sendable, Codable, CaseIterable {
    case camera
    case microphone
    case autoplay
    case popups
    case externalApps
    case downloads

    public var displayName: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .autoplay: "Autoplay"
        case .popups: "Pop-ups"
        case .externalApps: "Open External Apps"
        case .downloads: "Automatic Downloads"
        }
    }
}

public enum PermissionDecision: String, Hashable, Sendable, Codable {
    case allow
    case deny
}

/// A remembered permission decision for one origin host.
public struct SitePermission: Hashable, Sendable, Codable {
    public let host: String
    public let kind: SitePermissionKind
    public var decision: PermissionDecision

    public init(host: String, kind: SitePermissionKind, decision: PermissionDecision) {
        self.host = host
        self.kind = kind
        self.decision = decision
    }
}

/// Per-host presentation preferences.
public struct SiteSettings: Hashable, Sendable, Codable {
    public let host: String
    public var zoom: Double?
    public var isContentBlockingEnabled: Bool?

    public init(host: String, zoom: Double? = nil, isContentBlockingEnabled: Bool? = nil) {
        self.host = host
        self.zoom = zoom
        self.isContentBlockingEnabled = isContentBlockingEnabled
    }

    public static let zoomLevels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    public static func nextZoom(after current: Double, zoomingIn: Bool) -> Double {
        if zoomingIn {
            zoomLevels.first { $0 > current + 0.001 } ?? zoomLevels[zoomLevels.count - 1]
        } else {
            zoomLevels.last { $0 < current - 0.001 } ?? zoomLevels[0]
        }
    }
}
