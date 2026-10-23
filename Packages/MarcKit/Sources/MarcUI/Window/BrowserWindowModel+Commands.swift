import AppKit
import Foundation
import MarcCore
import MarcWebKit
import UniformTypeIdentifiers
import WebKit

public extension BrowserWindowModel {
    /// Whether a command applies in the current state (used to validate menu items).
    func canPerform(_ command: BrowserCommand) -> Bool {
        let tab = selectedTab
        let hasPage = tab?.url?.isWebURL == true
        switch command {
        case .goBack: return tab?.canGoBack == true
        case .goForward: return tab?.canGoForward == true
        case .reload, .forceReload: return tab != nil
        case .stopLoading: return tab?.isLoading == true
        case .copyURL, .copyURLAsMarkdown, .copyURLAsQuote, .share: return tab?.url != nil
        case .find, .findNext, .findPrevious, .zoomIn, .zoomOut, .actualSize, .printPage, .savePage, .viewSource,
             .developerTools, .clearCookiesAndReload, .clearCacheAndReload, .boostSite, .summarizePage, .askPage,
             .siteControls, .toggleMute:
            return hasPage
        case .addSplit: return selectedItem?.kind == .tab && kind != .little
        case .closeSplitPane, .separateSplitPane: return selectedSplit != nil
        case .pinTab, .duplicateTab: return selectedItem?.kind == .tab && isPersistent
        case .resetPinnedTab: return selectedItem?.tab?.hasLeftHome == true
        case .archiveTab: return selectedItem != nil || kind != .standard
        case .restoreClosedTab: return !(session?.recentlyClosed.isEmpty ?? true)
        case .newSpace, .editTheme, .renameSpace, .newFolder, .importData: return isPersistent
        case .nextSpace, .previousSpace: return workspace.spaces.count > 1
        case let .space(number): return workspace.orderedSpaces.count >= number
        case .clearToday: return state.spaceID.map { !workspace.children(of: .today($0)).isEmpty } ?? false
        case .tidyTabTitles: return session?.settings.settings.aiProvider != .off
        default: return true
        }
    }

    // swiftlint:disable:next function_body_length
    func perform(_ command: BrowserCommand) {
        guard let session else { return }
        let tab = selectedTab
        switch command {
        case .newTab: showCommandBar(.newTab)
        case .newWindow: session.openWindow()
        case .newBlankWindow: session.openEphemeralWindow(kind: .blank).showCommandBar(.newTab)
        case .newIncognitoWindow: session.openEphemeralWindow(kind: .incognito).showCommandBar(.newTab)
        case .newLittleWindow: session.openEphemeralWindow(kind: .little).showCommandBar(.newTab)
        case .restoreClosedTab: restoreLastClosedTab()
        case .openLocation: showCommandBar(tab == nil ? .newTab : .currentTab)
        case .newNote: createNote()
        case .archiveTab: closeSelected()
        case .share: share()
        case .savePage: savePage()
        case .printPage: printPage()
        case .importData: isShowingImport = true
        case .copyURL: copyCurrentURL(format: .plain)
        case .copyURLAsMarkdown: copyCurrentURL(format: .markdown)
        case .copyURLAsQuote: copyCurrentURL(format: .quote)
        case .find:
            tab?.beginFind()
            findFocusRequest += 1
        case .findNext: if let tab { Task { await tab.find(tab.find.query) } }
        case .findPrevious: if let tab { Task { await tab.find(tab.find.query, backwards: true) } }
        case .toggleSidebar: toggleSidebar()
        case .stopLoading: tab?.stopLoading()
        case .reload: tab?.reload()
        case .forceReload: tab?.reload(fromOrigin: true)
        case .clearCookiesAndReload: clearWebsiteData(WKWebsiteDataStore.cookieTypes, message: "Cleared cookies")
        case .clearCacheAndReload: clearWebsiteData(WKWebsiteDataStore.cacheTypes, message: "Cleared cache")
        case .addSplit: showCommandBar(.split)
        case .closeSplitPane: closeSelected()
        case .separateSplitPane: if let id = selectedItemID { try? store.update { try $0.separateFromSplit(id) } }
        case .zoomIn: adjustZoom(.in)
        case .zoomOut: adjustZoom(.out)
        case .actualSize: adjustZoom(.reset)
        case .viewSource: viewSource()
        case .developerTools: showDeveloperToolsHelp()
        case .newSpace:
            state.isSidebarVisible = true
            isCreatingSpace = true
        case .editTheme: editingThemeSpaceID = state.spaceID
        case .renameSpace: renamingSpaceID = state.spaceID
        case .nextSpace: switchSpace(offset: 1)
        case .previousSpace: switchSpace(offset: -1)
        case let .space(number): switchSpace(number: number)
        case .pinTab: togglePin()
        case .newFolder: createFolder()
        case .nextTab: selectNeighbor(offset: 1)
        case .previousTab: selectNeighbor(offset: -1)
        case let .selectTab(number): selectItem(number: number)
        case .clearToday: clearToday()
        case .duplicateTab: if let id = selectedItemID, let newID = try? store.update({ try $0.duplicateTab(id) }) { select(newID) }
        case .toggleMute: if let tab { tab.setMuted(!tab.media.isMuted) }
        case .resetPinnedTab: resetPinnedTab()
        case .goBack: tab?.goBack()
        case .goForward: tab?.goForward()
        case .showHistory: showInternalPage(.history)
        case .showArchive: showInternalPage(.archive)
        case .showDownloads: showInternalPage(.downloads)
        case .showLibrary: isShowingLibrary.toggle()
        case .boostSite: editBoost()
        case .summarizePage: showAssistant(.summary)
        case .askPage: showAssistant(.ask)
        case .tidyTabTitles: Task { await session.tidyTabTitles(in: self) }
        case .settings: session.showSettings?(.general)
        case .setDefaultBrowser: DefaultBrowser.request()
        case .checkForUpdates: session.checkForUpdates?()
        case .siteControls: siteControlItemID = selectedItemID
        }
    }

    // MARK: - Implementations

    private func createNote() {
        guard let session, let spaceID = state.spaceID else { return }
        let note = session.notes.create()
        guard let itemID = try? store.update({ try $0.addNote(note.id, placement: .todayTop(spaceID)) }) else { return }
        select(itemID)
    }

    private func createFolder() {
        guard let spaceID = state.spaceID,
              let folderID = try? store.update({ try $0.createFolder(
                  named: "New Folder",
                  at: SidebarDestination(container: .pinned(spaceID), index: .max),
              ) })
        else { return }
        state.isSidebarVisible = true
        renamingItemID = folderID
    }

    private func togglePin() {
        guard let item = selectedItem, let spaceID = state.spaceID else { return }
        if item.container.section == .today {
            try? store.update { try $0.pin(item.id) }
            showToast("Pinned", symbol: "pin")
        } else {
            try? store.update { try $0.unpin(item.id, into: spaceID) }
            showToast("Unpinned", symbol: "pin.slash")
        }
    }

    private func resetPinnedTab() {
        guard let item = selectedItem, let home = item.tab?.homeURL else { return }
        try? store.update { try $0.resetToHome(item.id) }
        selectedTab?.load(home, initiator: .user, transition: .link)
    }

    /// Selects an existing internal page tab in the current Space or opens a new one.
    func showInternalPage(_ page: InternalPage) {
        guard let spaceID = state.spaceID else { return }
        if let existing = workspace.allTabs(in: spaceID).first(where: { $0.tab?.url == page.url }) {
            select(existing.id)
            return
        }
        guard let itemID = try? store
            .update({ try $0.openTab(TabContent(url: page.url, title: page.title), placement: .todayTop(spaceID)) }) else { return }
        select(itemID)
    }

    private func editBoost() {
        guard let session, let tab = selectedTab, let host = tab.url?.host(percentEncoded: false) else { return }
        let boost = session.boosts.boost(for: host) ?? Boost(name: tab.url?.displayHost ?? host, hostPattern: tab.url?.displayHost ?? host)
        boostEditor = BoostEditorModel(boost: boost, tabID: tab.id, window: self)
    }

    private func showAssistant(_ mode: AssistantModel.Mode) {
        guard let session, let tab = selectedTab else { return }
        if let assistant, assistant.tabID == tab.id {
            assistant.mode = mode
            if mode == .summary, assistant.summary.isEmpty { assistant.summarize() }
            return
        }
        let model = AssistantModel(tabID: tab.id, window: self, session: session, mode: mode)
        assistant = model
        if mode == .summary { model.summarize() }
    }

    private func clearWebsiteData(_ types: Set<String>, message: String) {
        guard let tab = selectedTab, let host = tab.url?.host(percentEncoded: false) else { return }
        Task {
            await tab.context.removeData(forHost: host, types: types)
            tab.reload(fromOrigin: true)
            showToast(message, symbol: "trash")
        }
    }

    private func share() {
        guard let url = selectedTab?.url, let contentView = nsWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let anchor = NSRect(
            x: contentView.bounds.minX + (isSidebarVisible ? state.sidebarWidth : 10),
            y: contentView.bounds.maxY - 60,
            width: 1,
            height: 1,
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }

    private func printPage() {
        guard let window = nsWindow, let operation = selectedTab?.printOperation() else { return }
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func savePage() {
        guard let window = nsWindow, let tab = selectedTab else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = DownloadFileName.make(from: tab.title.isEmpty ? (tab.url?.displayHost ?? "Page") : tab.title)
        panel.allowedContentTypes = [.webArchive, .pdf]
        panel.isExtensionHidden = false
        let formats = NSPopUpButton(frame: .zero, pullsDown: false)
        formats.addItems(withTitles: ["Web Archive", "PDF"])
        formats.sizeToFit()
        panel.accessoryView = formats
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let asPDF = formats.indexOfSelectedItem == 1
            Task { @MainActor in
                let data = asPDF ? await tab.pdfData() : await tab.webArchiveData()
                let destination = url.deletingPathExtension().appendingPathExtension(asPDF ? "pdf" : "webarchive")
                try? data?.write(to: destination, options: .atomic)
            }
        }
    }

    private func viewSource() {
        guard let tab = selectedTab else { return }
        Task {
            guard let source = await tab.pageSource() else { return }
            sourceViewer = SourceViewerModel(title: tab.title, url: tab.url, source: source)
        }
    }

    private func showDeveloperToolsHelp() {
        guard let window = nsWindow else { return }
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector from Safari"
        alert.informativeText = """
        Marc's pages can be inspected with Safari's Web Inspector. In Safari, enable Settings › \
        Advanced › Show features for web developers, then choose Develop › \(Host.current().localizedName ?? "This Mac") › \
        Marc › the page you want to inspect.
        """
        alert.addButton(withTitle: "Open Safari")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn,
                  let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
            else { return }
            NSWorkspace.shared.openApplication(at: safari, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// Registers Marc as the default web browser. macOS asks the user to confirm.
enum DefaultBrowser {
    static func request() {
        let application = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: application, toOpenURLsWithScheme: scheme) { _ in }
        }
    }

    static var isDefault: Bool {
        guard let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

enum DownloadFileName {
    /// A file name derived from a page title.
    static func make(from title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>").union(.controlCharacters)
        let cleaned = title.unicodeScalars.filter { !forbidden.contains($0) }.map(String.init).joined().trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Page" : String(cleaned.prefix(120))
    }
}

/// HTML of a page shown in the source viewer.
public struct SourceViewerModel: Identifiable {
    public let id = UUID()
    public let title: String
    public let url: URL?
    public let source: String
}
