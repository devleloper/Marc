import AppKit
import WebKit

/// `WKWebView` with Marc's link context-menu items.
public final class MarcWebView: WKWebView {
    weak var owner: WebTab?

    override public func mouseDown(with event: NSEvent) {
        if let owner { owner.delegate?.webTabDidReceiveClick(owner) }
        super.mouseDown(with: event)
    }

    /// WebKit does not publish constants for its menu item identifiers; these strings are the
    /// identifiers WebKit assigns at runtime. If they ever change, Marc's items are simply
    /// appended instead of replacing WebKit's.
    private enum WebKitItem {
        static let openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
        static let openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
        static let openFrameInNewWindow = "WKMenuItemIdentifierOpenFrameInNewWindow"
        static let openMediaInNewWindow = "WKMenuItemIdentifierOpenMediaInNewWindow"
    }

    override public func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for identifier in [WebKitItem.openImageInNewWindow, WebKitItem.openFrameInNewWindow, WebKitItem.openMediaInNewWindow] {
            if let item = menu.items.first(where: { $0.identifier?.rawValue == identifier }) {
                item.title = item.title.replacingOccurrences(of: "Window", with: "Tab")
            }
        }
        guard let link = owner?.hoveredLink else { return }

        let index: Int
        if let existing = menu.items.firstIndex(where: { $0.identifier?.rawValue == WebKitItem.openLinkInNewWindow }) {
            menu.removeItem(at: existing)
            index = existing
        } else {
            index = 0
        }
        let items = [
            makeItem("Open Link in New Tab", link: link, action: #selector(openLinkInNewTab(_:))),
            makeItem("Open Link in Split View", link: link, action: #selector(openLinkInSplitView(_:))),
            makeItem("Open Link in Little Window", link: link, action: #selector(openLinkInLittleWindow(_:))),
        ]
        for (offset, item) in items.enumerated() {
            menu.insertItem(item, at: index + offset)
        }
        if index == 0 {
            menu.insertItem(.separator(), at: items.count)
        }
    }

    private func makeItem(_ title: String, link: URL, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = link
        return item
    }

    @objc private func openLinkInNewTab(_ sender: NSMenuItem) {
        open(sender, disposition: .foregroundTab)
    }

    @objc private func openLinkInSplitView(_ sender: NSMenuItem) {
        open(sender, disposition: .splitView)
    }

    @objc private func openLinkInLittleWindow(_ sender: NSMenuItem) {
        open(sender, disposition: .littleWindow)
    }

    private func open(_ sender: NSMenuItem, disposition: LinkDisposition) {
        guard let owner, let url = sender.representedObject as? URL else { return }
        owner.delegate?.webTab(owner, open: url, disposition: disposition)
    }
}
