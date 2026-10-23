import Foundation

/// How long an unpinned tab may stay inactive before it is moved to the Archive.
public enum ArchiveInterval: String, Hashable, Sendable, Codable, CaseIterable {
    case twelveHours
    case day
    case week
    case month
    case never

    public var duration: TimeInterval? {
        switch self {
        case .twelveHours: 12 * 60 * 60
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .never: nil
        }
    }

    public var displayName: String {
        switch self {
        case .twelveHours: "After 12 hours"
        case .day: "After 24 hours"
        case .week: "After 7 days"
        case .month: "After 30 days"
        case .never: "Never"
        }
    }
}
