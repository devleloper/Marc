import Foundation
import MarcWebKit

/// Sections of the Settings window.
public enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
    case general
    case profiles
    case search
    case privacy
    case passwords
    case extensions
    case ai
    case shortcuts
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .profiles: "Profiles"
        case .search: "Search"
        case .privacy: "Privacy & Security"
        case .passwords: "Passwords"
        case .extensions: "Extensions"
        case .ai: "AI"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .profiles: "person.2"
        case .search: "magnifyingglass"
        case .privacy: "hand.raised"
        case .passwords: "key"
        case .extensions: "puzzlepiece.extension"
        case .ai: "sparkles"
        case .shortcuts: "keyboard"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}
