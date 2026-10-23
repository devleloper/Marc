import AppKit
import Foundation
import MarcCore
import MarcWebKit
import WebKit

extension BrowserSession: WebTabDelegate {
    public func webTab(_ tab: WebTab, open url: URL, disposition: LinkDisposition) {
        let window = window(containing: tab.id) ?? keyWindow
        switch disposition {
        case .foregroundTab: window?.open(url, placement: .newTab, initiator: .webContent)
        case .backgroundTab: window?.open(url, placement: .backgroundTab, select: false, initiator: .webContent)
        case .splitView: window?.open(url, placement: .splitWithSelection, initiator: .webContent)
        case .littleWindow: openEphemeralWindow(kind: .little, url: url)
        }
    }

    public func webTab(_ tab: WebTab, createPopupTabWith configuration: WKWebViewConfiguration, for request: URLRequest) -> WebTab? {
        guard let window = window(containing: tab.id) ?? keyWindow, let spaceID = window.state.spaceID else { return nil }
        let id = SidebarItem.ID()
        let content = TabContent(url: request.url, title: "")
        guard (try? window.store.update({ try $0.openTab(content, placement: .todayTop(spaceID), id: id) })) != nil else { return nil }
        let popup = runtime.makePopupTab(id: id, context: tab.context, configuration: configuration)
        window.select(id)
        return popup
    }

    public func webTab(_ tab: WebTab, shouldPeekAt url: URL) -> Bool {
        guard let window = window(containing: tab.id), let item = window.workspace.items[tab.id], window.kind != .little,
              item.container.section != .today, let home = item.tab?.homeURL ?? item.tab?.url else { return false }
        return !url.isSameSite(as: home)
    }

    public func webTab(_ tab: WebTab, peekAt url: URL) {
        guard let window = window(containing: tab.id) else { return }
        window.peek?.close()
        window.peek = PeekModel(url: url, sourceItemID: tab.id, context: tab.context, window: window, session: self)
    }

    public func webTab(_ tab: WebTab, confirmOpeningExternally url: URL) async -> Bool {
        if let host = tab.url?.host(percentEncoded: false) {
            switch sitePreferences.decision(for: host, kind: .externalApps, profileID: tab.context.profileID) {
            case .allow: return true
            case .deny: return false
            case nil: break
            }
        }
        guard let nsWindow = window(containing: tab.id)?.nsWindow ?? keyWindow?.nsWindow,
              let application = NSWorkspace.shared.urlForApplication(toOpen: url)
        else { return false }
        let appName = FileManager.default.displayName(atPath: application.path(percentEncoded: false)).replacingOccurrences(
            of: ".app",
            with: "",
        )
        let alert = NSAlert()
        alert.messageText = "Open “\(appName)”?"
        alert.informativeText = "\(tab.url?.displayHost ?? "This page") wants to open \(appName)."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return await alert.beginSheetModal(for: nsWindow) == .alertFirstButtonReturn
    }

    public func webTab(_ tab: WebTab, preferencesFor host: String) -> SitePreferences {
        let profileID = tab.context.profileID
        let settings = sitePreferences.settings(for: host, profileID: profileID)
        return SitePreferences(
            zoom: settings.zoom ?? 1,
            blocksContent: settings.isContentBlockingEnabled ?? true,
            autoplayAllowed: sitePreferences.decision(for: host, kind: .autoplay, profileID: profileID) == .allow,
        )
    }

    public func webTab(_ tab: WebTab, didVisit url: URL, title: String, transition: VisitTransition) {
        guard let profileID = tab.context.profileID, let services = profileServices(for: profileID) else { return }
        Task { try? await services.history.recordVisit(url: url, title: title, transition: transition, at: .now) }
    }

    public func webTabDidChangeMetadata(_ tab: WebTab) {
        guard let window = window(containing: tab.id), window.workspace.items[tab.id] != nil else { return }
        let url = tab.url
        let title = tab.title
        let faviconURL = tab.faviconURL
        try? window.store.update { workspace in
            try workspace.updateTab(tab.id) { content in
                if let url, url != content.url { content.url = url }
                if !title.isEmpty, title != content.title { content.title = title }
                if let faviconURL, faviconURL != content.faviconURL { content.faviconURL = faviconURL }
            }
        }
        if !title.isEmpty, let url, let profileID = tab.context.profileID, let services = profileServices(for: profileID) {
            Task { try? await services.history.updateTitle(title, for: url) }
        }
        notifyExtensionsOfChange(tab)
    }

    public func webTab(_ tab: WebTab, requestMediaCapture type: WKMediaCaptureType, origin: String) async -> WKPermissionDecision {
        let kinds: [SitePermissionKind] = switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        default: [.camera, .microphone]
        }
        let host = URL(string: origin)?.host(percentEncoded: false) ?? origin
        let profileID = tab.context.profileID
        let decisions = kinds.map { sitePreferences.decision(for: host, kind: $0, profileID: profileID) }
        if decisions.allSatisfy({ $0 == .allow }) { return .grant }
        if decisions.contains(.deny) { return .deny }

        guard let window = window(containing: tab.id) else { return .deny }
        let (allow, remember) = await withCheckedContinuation { continuation in
            window.permissionPrompt = PermissionPrompt(origin: origin, kinds: kinds) { allow, remember in
                continuation.resume(returning: (allow, remember))
            }
        }
        window.permissionPrompt = nil
        if remember, let profileID, let services = profileServices(for: profileID) {
            for kind in kinds {
                sitePreferences.setDecision(
                    allow ? .allow : .deny,
                    for: host,
                    kind: kind,
                    profileID: profileID,
                    repository: services.siteData,
                )
            }
        }
        return allow ? .grant : .deny
    }

    public func webTab(_ tab: WebTab, didStart download: WKDownload) {
        downloads.begin(download, profileID: tab.context.profileID)
        window(containing: tab.id)?.showToast("Downloading…", symbol: "arrow.down.circle")
    }

    public func webTab(_ tab: WebTab, runAlert message: String) async {
        guard let nsWindow = window(containing: tab.id)?.nsWindow else { return }
        let alert = NSAlert()
        alert.messageText = tab.url?.displayHost ?? "This page"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        _ = await alert.beginSheetModal(for: nsWindow)
    }

    public func webTab(_ tab: WebTab, runConfirm message: String) async -> Bool {
        guard let nsWindow = window(containing: tab.id)?.nsWindow else { return false }
        let alert = NSAlert()
        alert.messageText = tab.url?.displayHost ?? "This page"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await alert.beginSheetModal(for: nsWindow) == .alertFirstButtonReturn
    }

    public func webTab(_ tab: WebTab, runPrompt message: String, defaultText: String?) async -> String? {
        guard let nsWindow = window(containing: tab.id)?.nsWindow else { return nil }
        let alert = NSAlert()
        alert.messageText = tab.url?.displayHost ?? "This page"
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await alert.beginSheetModal(for: nsWindow) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    public func webTab(_ tab: WebTab, chooseFiles parameters: WKOpenPanelParameters) async -> [URL]? {
        guard let nsWindow = window(containing: tab.id)?.nsWindow else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        return await panel.beginSheetModal(for: nsWindow) == .OK ? panel.urls : nil
    }

    public func webTab(_ tab: WebTab, credentialFor challenge: URLAuthenticationChallenge) async -> URLCredential? {
        guard let nsWindow = window(containing: tab.id)?.nsWindow else { return nil }
        let alert = NSAlert()
        alert.messageText = "Log in to \(challenge.protectionSpace.host)"
        alert.informativeText = challenge.protectionSpace.receivesCredentialSecurely
            ? "The site requires a username and password."
            : "Your login information will be sent without encryption."
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        stack.orientation = .vertical
        let user = NSTextField(frame: .zero)
        user.placeholderString = "Username"
        let password = NSSecureTextField(frame: .zero)
        password.placeholderString = "Password"
        stack.addArrangedSubview(user)
        stack.addArrangedSubview(password)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Log In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user
        guard await alert.beginSheetModal(for: nsWindow) == .alertFirstButtonReturn else { return nil }
        return URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession)
    }

    public func webTabRequestsClose(_ tab: WebTab) {
        guard let window = window(containing: tab.id), let item = window.workspace.items[tab.id],
              item.container.section == .today else { return }
        if window.selectedItemID == tab.id {
            window.closeSelected()
        } else {
            archive([tab.id], from: window)
        }
    }

    public func webTab(_ tab: WebTab, autofill event: AutofillEvent) {
        guard let window = window(containing: tab.id) else { return }
        passwords.handle(event, from: tab, in: window)
    }

    public func webTab(_ tab: WebTab, didPickElement selector: String) {
        guard let editor = window(containing: tab.id)?.boostEditor, editor.tabID == tab.id else { return }
        editor.addZappedSelector(selector)
    }

    public func webTabDidFinishPicking(_ tab: WebTab) {}

    // MARK: - AI

    /// Rewrites the titles of the Space's Today tabs into short names.
    func tidyTabTitles(in window: BrowserWindowModel) async {
        guard let spaceID = window.state.spaceID,
              let provider = await services.languageModels.provider(for: settings.settings.aiProvider)
        else {
            window.showToast("No AI model is available", symbol: "exclamationmark.triangle")
            return
        }
        let tabs = window.workspace.children(of: .today(spaceID)).filter { $0.tab?.customTitle == nil && $0.tab?.url?.isWebURL == true }
        guard !tabs.isEmpty else { return }
        let request = AIPrompts.tidyTitles(tabs.map { ($0.tab?.title ?? "", $0.tab?.url?.displayHost ?? "") })
        do {
            let response = try await provider.complete(request)
            let titles = AIResponseParser.tidyTitles(response, count: tabs.count)
            try window.store.update { workspace in
                for (index, title) in titles {
                    try workspace.updateTab(tabs[index].id) { $0.customTitle = title }
                }
            }
            window.showToast("Tidied \(titles.count) titles", symbol: "wand.and.stars")
        } catch {
            window.showToast(
                (error as? LanguageModelError)?.errorDescription ?? "Could not tidy titles",
                symbol: "exclamationmark.triangle",
            )
        }
    }
}
