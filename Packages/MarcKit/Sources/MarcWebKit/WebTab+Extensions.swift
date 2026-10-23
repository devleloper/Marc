import AppKit
import Foundation
import MarcCore
import WebKit

/// Browser state a tab reports to web extensions.
@MainActor
public protocol WebTabExtensionBridge: AnyObject {
    func extensionWindow(for tab: WebTab) -> (any WKWebExtensionWindow)?
    func extensionIndex(of tab: WebTab) -> Int
    func isSelected(_ tab: WebTab) -> Bool
    func isPinned(_ tab: WebTab) -> Bool
    func activate(_ tab: WebTab)
    func close(_ tab: WebTab)
}

extension WebTab: WKWebExtensionTab {
    public func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        extensionBridge?.extensionWindow(for: self)
    }

    public func indexInWindow(for context: WKWebExtensionContext) -> Int {
        extensionBridge?.extensionIndex(of: self) ?? 0
    }

    public func webView(for context: WKWebExtensionContext) -> WKWebView? {
        webView
    }

    public func title(for context: WKWebExtensionContext) -> String? {
        title
    }

    public func url(for context: WKWebExtensionContext) -> URL? {
        url
    }

    public func isPinned(for context: WKWebExtensionContext) -> Bool {
        extensionBridge?.isPinned(self) ?? false
    }

    public func isSelected(for context: WKWebExtensionContext) -> Bool {
        extensionBridge?.isSelected(self) ?? false
    }

    public func isPlayingAudio(for context: WKWebExtensionContext) -> Bool {
        media.isAudible
    }

    public func isMuted(for context: WKWebExtensionContext) -> Bool {
        media.isMuted
    }

    public func setMuted(_ muted: Bool, for context: WKWebExtensionContext) async throws {
        setMuted(muted)
    }

    public func zoomFactor(for context: WKWebExtensionContext) -> Double {
        zoom
    }

    public func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        setZoom(zoomFactor)
    }

    public func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !isLoading
    }

    public func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        load(url, initiator: .webContent, transition: .link)
    }

    public func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        reload(fromOrigin: fromOrigin)
    }

    public func goBack(for context: WKWebExtensionContext) async throws {
        goBack()
    }

    public func goForward(for context: WKWebExtensionContext) async throws {
        goForward()
    }

    public func activate(for context: WKWebExtensionContext) async throws {
        extensionBridge?.activate(self)
    }

    public func close(for context: WKWebExtensionContext) async throws {
        extensionBridge?.close(self)
    }
}
