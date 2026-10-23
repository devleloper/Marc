import AppKit
import Foundation
import MarcCore
import WebKit

extension WebTab: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
    ) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        // Pop-ups that must remain connected to their opener (OAuth, payment flows) get a real
        // web view; plain links with target=_blank simply open a new tab.
        if action.navigationType == .linkActivated, action.targetFrame == nil, windowFeatures.width == nil {
            let flags = action.modifierFlags
            delegate?.webTab(
                self,
                open: url,
                disposition: flags.contains(.command) && !flags.contains(.shift) ? .backgroundTab : .foregroundTab,
            )
            return nil
        }
        return delegate?.webTab(self, createPopupTabWith: configuration, for: action.request)?.webView
    }

    public func webViewDidClose(_ webView: WKWebView) {
        delegate?.webTabRequestsClose(self)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
    ) async {
        await delegate?.webTab(self, runAlert: message)
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> Bool {
        await delegate?.webTab(self, runConfirm: message) ?? false
    }

    public func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> String? {
        await delegate?.webTab(self, runPrompt: prompt, defaultText: defaultText)
    }

    public func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> [URL]? {
        await delegate?.webTab(self, chooseFiles: parameters)
    }

    public func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType,
    ) async -> WKPermissionDecision {
        let originString = origin.port == 0 ? "\(origin.protocol)://\(origin.host)" : "\(origin.protocol)://\(origin.host):\(origin.port)"
        return await delegate?.webTab(self, requestMediaCapture: type, origin: originString) ?? .deny
    }
}

extension WebTab: WKScriptMessageHandler {
    public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        // Only Marc's own isolated world can reach these handlers; still require the main frame,
        // which is the only frame the scripts are injected into.
        guard message.frameInfo.isMainFrame, message.world == .marc, let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            return
        }
        switch ScriptMessageName(rawValue: message.name) {
        case .page: handlePageMessage(type: type, body: body)
        case .autofill: handleAutofillMessage(type: type, body: body, frame: message.frameInfo)
        case .boost: handleBoostMessage(type: type, body: body)
        case nil: break
        }
    }

    private func handlePageMessage(type: String, body: [String: Any]) {
        switch type {
        case "hover":
            hoveredLink = (body["href"] as? String).flatMap(URL.init(string:))
            if let hoveredLink { environment.preresolve(hoveredLink) }
        case "icons":
            let icons = (body["icons"] as? [[String: Any]] ?? []).compactMap(PageIcon.init)
            if let best = PageIcon.best(in: icons), best.url != faviconURL {
                Task { await loadFavicon(best.url) }
            }
        case "media":
            var state = MediaState()
            state.isPlaying = body["isPlaying"] as? Bool ?? false
            state.isAudible = body["isAudible"] as? Bool ?? false
            state.isMuted = body["isMuted"] as? Bool ?? media.isMuted
            state.hasVideo = body["hasVideo"] as? Bool ?? false
            state.hasMedia = body["hasMedia"] as? Bool ?? false
            state.title = body["title"] as? String
            state.artist = body["artist"] as? String
            state.artworkURL = (body["artwork"] as? String).flatMap(URL.init(string:))
            if state != media { media = state }
        default:
            break
        }
    }

    private func handleAutofillMessage(type: String, body: [String: Any], frame: WKFrameInfo) {
        // Credentials are only exchanged with the page's own HTTPS (or loopback) origin.
        guard let pageURL = webView?.url, let pageOrigin = Credential.origin(for: pageURL) else { return }
        let origin = frame.securityOrigin
        let frameOrigin = origin.port == 0 ? "\(origin.protocol)://\(origin.host)" : "\(origin.protocol)://\(origin.host):\(origin.port)"
        guard frameOrigin.lowercased() == pageOrigin else { return }

        switch type {
        case "fieldFocused":
            guard let kind = (body["kind"] as? String).flatMap(AutofillEvent.FieldKind.init(rawValue:)),
                  let rect = body["rect"] as? [String: Double]
            else { return }
            let scale = zoom * (webView?.magnification ?? 1)
            let frameRect = CGRect(
                x: (rect["x"] ?? 0) * scale,
                y: (rect["y"] ?? 0) * scale,
                width: (rect["width"] ?? 0) * scale,
                height: (rect["height"] ?? 0) * scale,
            )
            delegate?.webTab(
                self,
                autofill: .fieldFocused(kind: kind, isNewPassword: body["isNewPassword"] as? Bool ?? false, rect: frameRect),
            )
        case "fieldBlurred":
            delegate?.webTab(self, autofill: .fieldBlurred)
        case "submitted":
            guard let password = body["password"] as? String, !password.isEmpty else { return }
            delegate?.webTab(
                self,
                autofill: .submitted(origin: pageOrigin, username: body["username"] as? String ?? "", password: password),
            )
        case "formsDetected":
            delegate?.webTab(self, autofill: .formsDetected(count: body["count"] as? Int ?? 0))
        default:
            break
        }
    }

    private func handleBoostMessage(type: String, body: [String: Any]) {
        switch type {
        case "picked":
            if let selector = body["selector"] as? String, Boost.isSafeSelector(selector) {
                delegate?.webTab(self, didPickElement: selector)
            }
        case "pickerFinished":
            isPickingElements = false
            delegate?.webTabDidFinishPicking(self)
        default:
            break
        }
    }

    func loadFavicon(_ iconURL: URL) async {
        guard let image = await environment.favicons.image(for: iconURL) else { return }
        favicon = image
        faviconURL = iconURL
        delegate?.webTabDidChangeMetadata(self)
    }
}

/// An icon declared by a page.
struct PageIcon: Equatable {
    let url: URL
    let size: Int
    let isAppleTouchIcon: Bool
    let isSVG: Bool

    init?(_ dictionary: [String: Any]) {
        guard let href = dictionary["href"] as? String, let url = URL(string: href),
              url.isWebURL || url.scheme == "data" else { return nil }
        self.url = url
        let sizes = (dictionary["sizes"] as? String ?? "").lowercased()
        size = sizes.split(separator: " ").compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }.max() ?? 0
        isAppleTouchIcon = (dictionary["rel"] as? String ?? "").contains("apple-touch-icon")
        isSVG = (dictionary["type"] as? String ?? "").contains("svg") || url.pathExtension.lowercased() == "svg"
    }

    /// Prefers crisp icons around 32–64 px, then larger ones, then anything.
    static func best(in icons: [PageIcon]) -> PageIcon? {
        icons.max { lhs, rhs in score(lhs) < score(rhs) }
    }

    private static func score(_ icon: PageIcon) -> Int {
        if icon.isSVG { return 90 }
        switch icon.size {
        case 32 ... 64: return 100 + icon.size
        case 65...: return 80 - icon.size / 64
        case 1 ..< 32: return 40 + icon.size
        default: return icon.isAppleTouchIcon ? 70 : 50
        }
    }
}
