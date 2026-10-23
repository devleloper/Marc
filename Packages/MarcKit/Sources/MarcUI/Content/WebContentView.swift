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

final class WebContainerView: NSView {
    private weak var tab: WebTab?
    private var token: UUID?

    override var isFlipped: Bool { true }

    func attach(_ newTab: WebTab, token: UUID) {
        if let tab, tab !== newTab { detach() }
        tab = newTab
        self.token = token
        newTab.loadIfNeeded()
        guard let webView = newTab.webView else { return }
        if webView.superview !== self {
            webView.removeFromSuperview()
            webView.frame = bounds
            webView.autoresizingMask = [.width, .height]
            addSubview(webView)
        }
        if newTab.host != AnyHashable(token) {
            newTab.host = token
        }
    }

    func detach() {
        guard let tab else { return }
        if let webView = tab.webView, webView.superview === self {
            webView.removeFromSuperview()
        }
        if let token, tab.host == AnyHashable(token) {
            tab.host = nil
        }
        self.tab = nil
    }
}
