import Foundation

/// Classifies every navigation before it reaches WebKit.
public struct NavigationSafetyPolicy: Sendable {
    public enum Decision: Hashable, Sendable {
        /// Load in the web view.
        case allow
        /// Hand off to another application after the user confirms.
        case openExternally(URL)
        case block(Reason)
    }

    public enum Reason: Hashable, Sendable {
        case scriptURL
        case topLevelDataURL
        case fileURLFromWebContent
        case unsupportedAboutPage
        case internalPageFromWebContent
    }

    public enum Initiator: Hashable, Sendable {
        /// Typed in the address field, chosen in the Command Bar, or opened from Finder.
        case user
        /// Requested by web content (links, redirects, scripts, forms).
        case webContent
    }

    static let webSchemes: Set = ["http", "https"]
    static let scriptSchemes: Set = ["javascript", "vbscript"]
    static let allowedAboutPages: Set = ["blank", "srcdoc"]

    public init() {}

    public func decide(_ url: URL, isMainFrame: Bool, initiator: Initiator) -> Decision {
        guard let scheme = url.scheme?.lowercased() else { return .block(.scriptURL) }
        if Self.webSchemes.contains(scheme) { return .allow }
        if Self.scriptSchemes.contains(scheme) { return .block(.scriptURL) }

        switch scheme {
        case "about":
            let page = url.absoluteString.dropFirst("about:".count).prefix { $0 != "?" && $0 != "#" }
            return Self.allowedAboutPages.contains(String(page).lowercased()) ? .allow : .block(.unsupportedAboutPage)
        case "blob":
            return .allow
        case "marc":
            // Marc's own pages are rendered natively and never handed to WebKit.
            return initiator == .user ? .allow : .block(.internalPageFromWebContent)
        case "data":
            // Top-level data: URLs from web content are a common phishing vector.
            return isMainFrame && initiator == .webContent ? .block(.topLevelDataURL) : .allow
        case "file":
            return initiator == .user ? .allow : .block(.fileURLFromWebContent)
        default:
            return .openExternally(url)
        }
    }
}
