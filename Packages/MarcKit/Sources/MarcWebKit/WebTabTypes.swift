import AppKit
import Foundation
import MarcCore
import WebKit

/// Per-site preferences a tab needs synchronously when it creates its web view or navigates.
public struct SitePreferences: Equatable, Sendable {
    public var zoom: Double
    public var blocksContent: Bool
    public var autoplayAllowed: Bool

    public init(zoom: Double = 1, blocksContent: Bool = true, autoplayAllowed: Bool = false) {
        self.zoom = zoom
        self.blocksContent = blocksContent
        self.autoplayAllowed = autoplayAllowed
    }
}

public struct MediaState: Equatable, Sendable {
    public var isPlaying = false
    public var isAudible = false
    public var isMuted = false
    public var hasVideo = false
    public var hasMedia = false
    public var title: String?
    public var artist: String?
    public var artworkURL: URL?

    public init() {}
}

public enum NavigationFailure: Equatable, Sendable {
    case network(url: URL?, code: Int, description: String)
    case certificate(url: URL, host: String, description: String)
    case blocked(url: URL, reason: NavigationSafetyPolicy.Reason)
    case webContentProcessTerminated

    public var url: URL? {
        switch self {
        case let .network(url, _, _): url
        case let .certificate(url, _, _), let .blocked(url, _): url
        case .webContentProcessTerminated: nil
        }
    }
}

public struct FindState: Equatable, Sendable {
    public var isActive = false
    public var query = ""
    public var matchCount = 0
    /// One-based index of the highlighted match, 0 when there is none.
    public var currentMatch = 0

    public init() {}
}

/// How a link should open when a tab hands it to the browser.
public enum LinkDisposition: Sendable {
    case foregroundTab
    case backgroundTab
    case splitView
    case littleWindow
}

public enum AutofillEvent: Sendable {
    public enum FieldKind: String, Sendable {
        case username
        case password
    }

    /// `rect` is in the web view's coordinate space with a top-left origin.
    case fieldFocused(kind: FieldKind, isNewPassword: Bool, rect: CGRect)
    case fieldBlurred
    case submitted(origin: String, username: String, password: String)
    case formsDetected(count: Int)
}

/// Decisions and side effects a tab delegates to the browser layer.
@MainActor
public protocol WebTabDelegate: AnyObject {
    func webTab(_ tab: WebTab, open url: URL, disposition: LinkDisposition)
    /// Called for `window.open` and `target=_blank`. Return a new tab adopting the web view built
    /// from `configuration`, or `nil` to block the pop-up.
    func webTab(_ tab: WebTab, createPopupTabWith configuration: WKWebViewConfiguration, for request: URLRequest) -> WebTab?
    func webTab(_ tab: WebTab, shouldPeekAt url: URL) -> Bool
    func webTab(_ tab: WebTab, peekAt url: URL)
    func webTab(_ tab: WebTab, confirmOpeningExternally url: URL) async -> Bool
    func webTab(_ tab: WebTab, preferencesFor host: String) -> SitePreferences
    func webTab(_ tab: WebTab, didVisit url: URL, title: String, transition: VisitTransition)
    func webTabDidChangeMetadata(_ tab: WebTab)
    func webTab(_ tab: WebTab, requestMediaCapture type: WKMediaCaptureType, origin: String) async -> WKPermissionDecision
    func webTab(_ tab: WebTab, didStart download: WKDownload)
    func webTab(_ tab: WebTab, runAlert message: String) async
    func webTab(_ tab: WebTab, runConfirm message: String) async -> Bool
    func webTab(_ tab: WebTab, runPrompt message: String, defaultText: String?) async -> String?
    func webTab(_ tab: WebTab, chooseFiles parameters: WKOpenPanelParameters) async -> [URL]?
    func webTab(_ tab: WebTab, credentialFor challenge: URLAuthenticationChallenge) async -> URLCredential?
    func webTabRequestsClose(_ tab: WebTab)
    func webTab(_ tab: WebTab, autofill event: AutofillEvent)
    func webTab(_ tab: WebTab, didPickElement selector: String)
    func webTabDidFinishPicking(_ tab: WebTab)
}

public extension WebTabDelegate {
    func webTab(_ tab: WebTab, createPopupTabWith configuration: WKWebViewConfiguration, for request: URLRequest) -> WebTab? { nil }
    func webTab(_ tab: WebTab, shouldPeekAt url: URL) -> Bool { false }
    func webTab(_ tab: WebTab, peekAt url: URL) {}
    func webTab(_ tab: WebTab, confirmOpeningExternally url: URL) async -> Bool { false }
    func webTab(_ tab: WebTab, preferencesFor host: String) -> SitePreferences { SitePreferences() }
    func webTab(_ tab: WebTab, didVisit url: URL, title: String, transition: VisitTransition) {}
    func webTabDidChangeMetadata(_ tab: WebTab) {}
    func webTab(_ tab: WebTab, requestMediaCapture type: WKMediaCaptureType, origin: String) async -> WKPermissionDecision { .prompt }
    func webTab(_ tab: WebTab, didStart download: WKDownload) {}
    func webTab(_ tab: WebTab, runAlert message: String) async {}
    func webTab(_ tab: WebTab, runConfirm message: String) async -> Bool { false }
    func webTab(_ tab: WebTab, runPrompt message: String, defaultText: String?) async -> String? { nil }
    func webTab(_ tab: WebTab, chooseFiles parameters: WKOpenPanelParameters) async -> [URL]? { nil }
    func webTab(_ tab: WebTab, credentialFor challenge: URLAuthenticationChallenge) async -> URLCredential? { nil }
    func webTabRequestsClose(_ tab: WebTab) {}
    func webTab(_ tab: WebTab, autofill event: AutofillEvent) {}
    func webTab(_ tab: WebTab, didPickElement selector: String) {}
    func webTabDidFinishPicking(_ tab: WebTab) {}
}

/// Shared services a tab reads from the engine.
@MainActor
public struct WebTabEnvironment {
    public var applicationName: String
    public var contentRuleLists: () -> [WKContentRuleList]
    public var isContentBlockingEnabled: () -> Bool
    public var boosts: (String) -> [Boost]
    public var favicons: FaviconLoader

    public init(
        applicationName: String,
        contentRuleLists: @escaping () -> [WKContentRuleList],
        isContentBlockingEnabled: @escaping () -> Bool,
        boosts: @escaping (String) -> [Boost],
        favicons: FaviconLoader,
    ) {
        self.applicationName = applicationName
        self.contentRuleLists = contentRuleLists
        self.isContentBlockingEnabled = isContentBlockingEnabled
        self.boosts = boosts
        self.favicons = favicons
    }
}
