import AppKit
import Foundation
import MarcCore
import Observation
import os
import WebKit

/// The live runtime of one tab. The `WKWebView` is created lazily, can be unloaded to save
/// memory (keeping its back/forward list), and is re-created on demand.
@Observable
public final class WebTab: NSObject {
    public let id: SidebarItem.ID
    public let context: ProfileWebContext

    public internal(set) var url: URL?
    public internal(set) var title = ""
    public internal(set) var isLoading = false
    public internal(set) var estimatedProgress = 0.0
    public internal(set) var canGoBack = false
    public internal(set) var canGoForward = false
    public internal(set) var hasOnlySecureContent = false
    public internal(set) var favicon: NSImage?
    public internal(set) var faviconURL: URL?
    public internal(set) var themeColor: NSColor?
    public internal(set) var hoveredLink: URL?
    public internal(set) var media = MediaState()
    public internal(set) var cameraState: WKMediaCaptureState = .none
    public internal(set) var microphoneState: WKMediaCaptureState = .none
    public internal(set) var failure: NavigationFailure?
    public internal(set) var zoom = 1.0
    public internal(set) var find = FindState()
    public internal(set) var isPickingElements = false
    public internal(set) var lastActiveAt = Date.now
    public internal(set) var hasWebView = false
    /// The content view currently hosting the web view; a tab can be visible in one place only.
    public var host: AnyHashable?

    @ObservationIgnored public weak var delegate: (any WebTabDelegate)?
    @ObservationIgnored public weak var extensionBridge: (any WebTabExtensionBridge)?
    @ObservationIgnored public internal(set) var webView: MarcWebView?
    @ObservationIgnored let environment: WebTabEnvironment
    @ObservationIgnored var pendingURL: URL?
    @ObservationIgnored var interactionState: Any?
    @ObservationIgnored var observations: [NSKeyValueObservation] = []
    @ObservationIgnored var userInitiatedURL: URL?
    @ObservationIgnored var allowedInsecureHosts: Set<String> = []
    @ObservationIgnored var preparedHost: String?
    /// The content rule lists currently installed, so unchanged lists aren't sent to the page's
    /// process again on every navigation.
    @ObservationIgnored var appliedContentRuleLists: [ObjectIdentifier] = []
    @ObservationIgnored var pendingTransition = VisitTransition.link
    @ObservationIgnored let logger = Logger.marc("WebTab")

    /// A tab that will load `url` when first shown.
    public init(id: SidebarItem.ID, context: ProfileWebContext, environment: WebTabEnvironment, url: URL?, title: String = "") {
        self.id = id
        self.context = context
        self.environment = environment
        self.url = url
        self.title = title
        pendingURL = url
        super.init()
    }

    /// A tab adopting a pop-up created by WebKit with `configuration`.
    public init(
        id: SidebarItem.ID,
        context: ProfileWebContext,
        environment: WebTabEnvironment,
        popupConfiguration: WKWebViewConfiguration,
    ) {
        self.id = id
        self.context = context
        self.environment = environment
        super.init()
        // The configuration comes from the opener; give the pop-up its own scripts and handlers
        // so that its messages are not delivered to the opener's tab.
        popupConfiguration.userContentController = WKUserContentController()
        makeWebView(configuration: popupConfiguration)
    }

    // MARK: - Lifecycle

    /// Creates the web view and starts loading if the tab has not been loaded yet.
    public func loadIfNeeded() {
        guard webView == nil else { return }
        let host = pendingURL?.host(percentEncoded: false) ?? ""
        let preferences = delegate?.webTab(self, preferencesFor: host) ?? SitePreferences()
        zoom = preferences.zoom
        let configuration = context.makeConfiguration(
            applicationName: environment.applicationName,
            autoplayAllowed: preferences.autoplayAllowed,
        )
        makeWebView(configuration: configuration)
        if let interactionState {
            webView?.interactionState = interactionState
            self.interactionState = nil
        } else if let pendingURL {
            pendingTransition = .restored
            startLoading(pendingURL)
        }
    }

    /// Releases the web view, keeping enough state to restore the tab later.
    public func unload() {
        guard let webView else { return }
        interactionState = webView.interactionState
        pendingURL = url
        tearDown(webView)
    }

    /// Closes the tab permanently.
    public func close() {
        guard let webView else { return }
        interactionState = nil
        tearDown(webView)
    }

    public func markActive(at date: Date = .now) {
        lastActiveAt = date
    }

    private func tearDown(_ webView: MarcWebView) {
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        let controller = webView.configuration.userContentController
        controller.removeAllScriptMessageHandlers()
        controller.removeAllUserScripts()
        webView.removeFromSuperview()
        self.webView = nil
        hasWebView = false
        isLoading = false
        estimatedProgress = 0
        hoveredLink = nil
        media = MediaState()
        find = FindState()
        isPickingElements = false
    }

    func makeWebView(configuration: WKWebViewConfiguration) {
        preparedHost = nil
        appliedContentRuleLists = []
        let controller = configuration.userContentController
        installBaseScripts(on: controller)
        let webView = MarcWebView(frame: .zero, configuration: configuration)
        webView.owner = self
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.pageZoom = zoom
        self.webView = webView
        hasWebView = true
        observe(webView)
    }

    func installBaseScripts(on controller: WKUserContentController) {
        let proxy = WeakScriptMessageHandler(self)
        for name in ScriptMessageName.allCases {
            controller.add(proxy, contentWorld: .marc, name: name.rawValue)
        }
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
    }

    private func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.title) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.titleDidChange(webView.title ?? "") }
            },
            webView.observe(\.url) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.urlDidChange(webView.url) }
            },
            webView.observe(\.isLoading) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.estimatedProgress = webView.estimatedProgress }
            },
            webView.observe(\.canGoBack) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.hasOnlySecureContent) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.hasOnlySecureContent = webView.hasOnlySecureContent }
            },
            webView.observe(\.themeColor) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.themeColor = webView.themeColor }
            },
            webView.observe(\.cameraCaptureState) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.cameraState = webView.cameraCaptureState }
            },
            webView.observe(\.microphoneCaptureState) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.microphoneState = webView.microphoneCaptureState }
            },
        ]
    }

    private func titleDidChange(_ newTitle: String) {
        guard newTitle != title else { return }
        title = newTitle
        delegate?.webTabDidChangeMetadata(self)
    }

    private func urlDidChange(_ newURL: URL?) {
        guard let newURL, newURL != url else { return }
        if newURL.host(percentEncoded: false) != url?.host(percentEncoded: false) {
            favicon = nil
            faviconURL = nil
        }
        url = newURL
        delegate?.webTabDidChangeMetadata(self)
    }

    // MARK: - Navigation commands

    /// Loads `url`. User-initiated loads may open local files; loads from web content may not.
    public func load(_ url: URL, initiator: NavigationSafetyPolicy.Initiator = .user, transition: VisitTransition = .typed) {
        // WebKit runs `javascript:` URLs passed to `load` without consulting the navigation
        // delegate, so every load is checked here first.
        switch NavigationSafetyPolicy().decide(url, isMainFrame: true, initiator: initiator) {
        case .allow:
            break
        case let .block(reason):
            failure = .blocked(url: url, reason: reason)
            return
        case let .openExternally(externalURL):
            Task { await openExternally(externalURL) }
            return
        }
        failure = nil
        self.url = url
        pendingURL = url
        interactionState = nil
        if initiator == .user { userInitiatedURL = url }
        pendingTransition = transition
        if webView == nil {
            loadIfNeeded()
        } else {
            startLoading(url)
        }
    }

    func startLoading(_ url: URL) {
        guard let webView else { return }
        prepareForNavigation(to: url)
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    public func goBack() {
        failure = nil
        pendingTransition = .link
        webView?.goBack()
    }

    public func goForward() {
        failure = nil
        pendingTransition = .link
        webView?.goForward()
    }

    public func reload(fromOrigin: Bool = false) {
        if let failedURL = failure?.url {
            load(failedURL, initiator: .user, transition: .reload)
            return
        }
        guard let webView else {
            loadIfNeeded()
            return
        }
        pendingTransition = .reload
        if fromOrigin { webView.reloadFromOrigin() } else { webView.reload() }
    }

    public func stopLoading() {
        webView?.stopLoading()
    }

    /// Allows an invalid certificate for this host for the lifetime of the tab, after the user
    /// explicitly chose to continue.
    public func proceedDespiteCertificateError() {
        guard case let .certificate(url, host, _) = failure else { return }
        allowedInsecureHosts.insert(host)
        load(url, initiator: .user, transition: .link)
    }

    // MARK: - Page commands

    public func setZoom(_ value: Double) {
        zoom = min(max(value, 0.3), 3)
        webView?.pageZoom = zoom
    }

    /// Readable text of the page for AI features.
    public func pageContent(characterLimit: Int = 600_000) async -> PageContent? {
        guard let webView else { return nil }
        let value = try? await webView.callAsyncJavaScript(
            "return window.__marcPageText ? window.__marcPageText(limit) : null",
            arguments: ["limit": characterLimit],
            in: nil,
            contentWorld: .marc,
        )
        guard let dictionary = value as? [String: Any], let text = dictionary["text"] as? String else { return nil }
        return PageContent(
            title: dictionary["title"] as? String ?? title,
            url: (dictionary["url"] as? String).flatMap(URL.init(string:)) ?? url,
            text: text,
        )
    }

    public func fillCredential(username: String, password: String, generated: Bool = false) {
        run("return window.__marcFill ? window.__marcFill(username, password, generated) : false", arguments: [
            "username": username,
            "password": password,
            "generated": generated,
        ])
    }

    public func snapshot() async -> NSImage? {
        try? await webView?.takeSnapshot(configuration: nil)
    }

    public func pdfData() async -> Data? {
        try? await webView?.pdf(configuration: WKPDFConfiguration())
    }

    public func webArchiveData() async -> Data? {
        guard let webView else { return nil }
        return await withCheckedContinuation { continuation in
            webView.createWebArchiveData { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    public func printOperation() -> NSPrintOperation? {
        guard let webView else { return nil }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        let operation = webView.printOperation(with: info)
        operation.view?.frame = webView.bounds
        return operation
    }

    /// The page's HTML, for the source viewer.
    public func pageSource() async -> String? {
        guard let webView else { return nil }
        return try? await webView.callAsyncJavaScript(
            "return document.documentElement ? document.documentElement.outerHTML : ''",
            arguments: [:],
            in: nil,
            contentWorld: .marc,
        ) as? String
    }

    // MARK: - Find

    public func beginFind() {
        find.isActive = true
    }

    public func find(_ query: String, backwards: Bool = false) async {
        if query != find.query { find.currentMatch = 0 }
        find.query = query
        guard let webView, !query.isEmpty else {
            find.matchCount = 0
            find.currentMatch = 0
            return
        }
        let count = await (try? webView.callAsyncJavaScript(
            "return window.__marcCountMatches ? window.__marcCountMatches(query) : 0",
            arguments: ["query": query],
            in: nil,
            contentWorld: .marc,
        ) as? Int) ?? 0
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        let result = try? await webView.find(query, configuration: configuration)
        guard query == find.query else { return }
        find.matchCount = count
        if result?.matchFound == true, count > 0 {
            if find.currentMatch == 0 {
                find.currentMatch = backwards ? count : 1
            } else {
                find.currentMatch = backwards ? (find.currentMatch - 2 + count) % count + 1 : find.currentMatch % count + 1
            }
        } else {
            find.currentMatch = 0
        }
    }

    public func endFind() {
        find = FindState()
        run("window.getSelection && window.getSelection().removeAllRanges()")
    }

    // MARK: - Boosts

    /// Applies style changes to the current page immediately, without reloading.
    public func applyBoostStyles(_ boosts: [Boost]) {
        guard let webView else { return }
        for boost in boosts {
            let css = boost.isEnabled ? boost.styleSheet : ""
            webView.evaluateJavaScript(BoostScripts.styleInjection(css: css, id: boost.id), in: nil, in: .marcBoosts) { _ in }
        }
    }

    public func startElementPicker() {
        guard let webView, !isPickingElements else { return }
        isPickingElements = true
        webView.evaluateJavaScript(ScriptResource.elementPicker.source, in: nil, in: .marc) { _ in }
        webView.window?.makeFirstResponder(webView)
    }

    public func stopElementPicker() {
        guard isPickingElements else { return }
        run("window.__marcStopPicker && window.__marcStopPicker()")
    }

    // MARK: - Helpers

    func run(_ script: String, arguments: [String: Any] = [:]) {
        guard let webView else { return }
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .marc) { _ in }
    }
}
