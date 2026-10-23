import AppKit
import MarcWebKit
import SwiftUI
import WebKit

/// Hosts a tab's `WKWebView`. A web view can be in one place at a time; `token` identifies this
/// host so that a second window showing the same tab can display a placeholder instead.
struct WebContentView: NSViewRepresentable {
    let tab: WebTab
    let token: UUID

    func makeNSView(context: Context) -> WebContainerView {
        let view = WebContainerView()
        view.attach(tab, token: token)
        return view
    }

    func updateNSView(_ view: WebContainerView, context: Context) {
        view.attach(tab, token: token)
    }

    static func dismantleNSView(_ view: WebContainerView, coordinator: ()) {
        view.detach()
    }
}

/// Shows one tab's web view and keeps the last few tabs it showed inside it, hidden. Taking a
/// `WKWebView` out of its window makes WebKit tear down the page's layers, so coming back to a tab
/// repainted the whole page; a hidden web view is still in the window and reappears at once.
final class WebContainerView: NSView {
    private weak var tab: WebTab?
    private var token: UUID?
    /// Tabs shown here before the current one, most recent first. Their web views stay hidden.
    private var parked: [WeakTab] = []
    private static let parkingLimit = 4

    override var isFlipped: Bool { true }

    func attach(_ newTab: WebTab, token: UUID) {
        var hadKeyboardFocus = false
        if let tab, tab !== newTab {
            hadKeyboardFocus = hasKeyboardFocus(tab.webView)
            park(tab)
        }
        tab = newTab
        self.token = token
        parked.removeAll { $0.tab == nil || $0.tab === newTab }
        newTab.loadIfNeeded()
        guard let webView = newTab.webView else { return }
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
        webView.isHidden = false
        if hadKeyboardFocus { window?.makeFirstResponder(webView) }
        if newTab.host != AnyHashable(token) {
            newTab.host = token
        }
    }

    func detach() {
        if let tab {
            remove(tab)
            self.tab = nil
        }
        parked.compactMap(\.tab).forEach(remove)
        parked.removeAll()
    }

    /// Hides the previous tab's web view and gives up the claim on it, so another window or pane
    /// can show it; that window then simply moves the web view.
    private func park(_ old: WebTab) {
        if let token, old.host == AnyHashable(token) { old.host = nil }
        guard let webView = old.webView, webView.superview === self else { return }
        if hasKeyboardFocus(webView) { window?.makeFirstResponder(nil) }
        webView.isHidden = true
        parked.insert(WeakTab(old), at: 0)
        while parked.count > Self.parkingLimit {
            if let evicted = parked.removeLast().tab { remove(evicted) }
        }
    }

    private func remove(_ tab: WebTab) {
        if let webView = tab.webView, webView.superview === self {
            webView.removeFromSuperview()
            webView.isHidden = false
        }
        if let token, tab.host == AnyHashable(token) {
            tab.host = nil
        }
    }

    private func hasKeyboardFocus(_ webView: NSView?) -> Bool {
        guard let webView, let responder = window?.firstResponder as? NSView else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }
}

private struct WeakTab {
    weak var tab: WebTab?

    init(_ tab: WebTab) {
        self.tab = tab
    }
}
