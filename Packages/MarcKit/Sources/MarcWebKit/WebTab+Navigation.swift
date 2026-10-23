import AppKit
import Foundation
import MarcCore
import WebKit

extension WebTab: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences,
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let url = action.request.url else { return (.cancel, preferences) }
        if action.shouldPerformDownload { return (.download, preferences) }

        let isMainFrame = action.targetFrame?.isMainFrame ?? true
        let initiator: NavigationSafetyPolicy.Initiator = url == userInitiatedURL ? .user : .webContent
        if isMainFrame { userInitiatedURL = nil }

        switch NavigationSafetyPolicy().decide(url, isMainFrame: isMainFrame, initiator: initiator) {
        case .allow:
            break
        case let .openExternally(externalURL):
            Task { await openExternally(externalURL) }
            return (.cancel, preferences)
        case let .block(reason):
            if isMainFrame, initiator == .user {
                failure = .blocked(url: url, reason: reason)
            }
            return (.cancel, preferences)
        }

        if action.navigationType == .linkActivated, isMainFrame {
            let flags = action.modifierFlags
            if action.buttonNumber == 2 || flags.contains(.command) {
                delegate?.webTab(self, open: url, disposition: flags.contains(.shift) ? .foregroundTab : .backgroundTab)
                return (.cancel, preferences)
            }
            if flags.contains(.option) {
                return (.download, preferences)
            }
            if delegate?.webTab(self, shouldPeekAt: url) == true {
                delegate?.webTab(self, peekAt: url)
                return (.cancel, preferences)
            }
        }

        if isMainFrame {
            prepareForNavigation(to: url)
            pendingTransition = action.navigationType == .backForward ? .link : pendingTransition
        }
        return (.allow, preferences)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if !response.canShowMIMEType { return .download }
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition")?.lowercased(),
           disposition.hasPrefix("attachment") {
            return .download
        }
        return .allow
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        delegate?.webTab(self, didStart: download)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        delegate?.webTab(self, didStart: download)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failure = nil
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        let transition = pendingTransition
        pendingTransition = .link
        hoveredLink = nil
        if find.isActive { find = FindState(isActive: true) }
        delegate?.webTab(self, didVisit: url, title: webView.title ?? "", transition: transition)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if favicon == nil, let url = webView.url, url.isWebURL {
            Task { await loadFallbackFavicon(for: url) }
        }
        delegate?.webTabDidChangeMetadata(self)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handle(error, url: webView.url)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        handle(error, url: failingURL ?? pendingURL)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failure = .webContentProcessTerminated
        isLoading = false
    }

    public func webView(
        _ webView: WKWebView,
        respondTo challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            if allowedInsecureHosts.contains(space.host), let trust = space.serverTrust {
                return (.useCredential, URLCredential(trust: trust))
            }
            return (.performDefaultHandling, nil)
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM:
            guard challenge.previousFailureCount < 3 else { return (.cancelAuthenticationChallenge, nil) }
            if let credential = await delegate?.webTab(self, credentialFor: challenge) {
                return (.useCredential, credential)
            }
            return (.cancelAuthenticationChallenge, nil)
        default:
            return (.performDefaultHandling, nil)
        }
    }

    // MARK: - Helpers

    /// Configures per-host content rules and boosts before a main-frame document is created.
    func prepareForNavigation(to url: URL) {
        guard let controller = webView?.configuration.userContentController else { return }
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let preferences = delegate?.webTab(self, preferencesFor: host) ?? SitePreferences()
        if preferences.zoom != zoom {
            setZoom(preferences.zoom)
        }

        let ruleLists = environment.isContentBlockingEnabled() && preferences.blocksContent ? environment.contentRuleLists() : []
        let identities = ruleLists.map(ObjectIdentifier.init)
        if identities != appliedContentRuleLists {
            controller.removeAllContentRuleLists()
            ruleLists.forEach(controller.add)
            appliedContentRuleLists = identities
        }

        guard host != preparedHost else { return }
        preparedHost = host
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: ScriptResource.pageObserver.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .marc,
        ))
        controller.addUserScript(WKUserScript(
            source: ScriptResource.autofill.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .marc,
        ))
        BoostScripts.userScripts(for: environment.boosts(host)).forEach(controller.addUserScript)
    }

    /// Rebuilds boost scripts after boosts changed, then applies style changes live.
    public func boostsDidChange() {
        preparedHost = nil
        if let url { prepareForNavigation(to: url) }
        let host = url?.host(percentEncoded: false) ?? ""
        applyBoostStyles(environment.boosts(host))
    }

    private func handle(_ error: any Error, url: URL?) {
        let nsError = error as NSError
        // Cancelled loads and loads interrupted by a policy decision (downloads, Peek, new tabs)
        // are not failures.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == WKError.errorDomain, nsError.code == 102 || nsError.code == 204 { return }

        let certificateErrors = [
            NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
            NSURLErrorSecureConnectionFailed,
        ]
        if nsError.domain == NSURLErrorDomain, certificateErrors.contains(nsError.code), let url,
           let host = url.host(percentEncoded: false) {
            failure = .certificate(url: url, host: host, description: nsError.localizedDescription)
        } else {
            failure = .network(url: url, code: nsError.code, description: nsError.localizedDescription)
        }
        isLoading = false
    }

    func openExternally(_ url: URL) async {
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { return }
        if await delegate?.webTab(self, confirmOpeningExternally: url) == true {
            NSWorkspace.shared.open(url)
        }
    }

    func loadFallbackFavicon(for pageURL: URL) async {
        guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return }
        components.path = "/favicon.ico"
        components.query = nil
        components.fragment = nil
        guard let iconURL = components.url, let image = await environment.favicons.image(for: iconURL), favicon == nil,
              url?.host(percentEncoded: false) == pageURL.host(percentEncoded: false) else { return }
        favicon = image
        faviconURL = iconURL
        delegate?.webTabDidChangeMetadata(self)
    }
}

extension FindState {
    init(isActive: Bool) {
        self.init()
        self.isActive = isActive
    }
}
