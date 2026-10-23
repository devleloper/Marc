import Foundation
import MarcCore
import MarcWebKit
import Observation

/// State of an open Command Bar: query, results and selection.
@Observable
public final class CommandBarModel {
    public var query: String {
        didSet {
            guard query != oldValue else { return }
            selectedIndex = 0
            refresh()
        }
    }

    public private(set) var results: [CommandBarResult] = [] {
        didSet { preresolveSelection() }
    }

    public var selectedIndex = 0 {
        didSet { preresolveSelection() }
    }

    /// A site chosen with Tab ("Search YouTube"); results then search that site.
    public private(set) var siteSearch: SearchEngine?
    public let placement: BrowserWindowModel.CommandBarPlacement

    @ObservationIgnored private weak var window: BrowserWindowModel?
    @ObservationIgnored private let session: BrowserSession
    @ObservationIgnored private var history: [HistoryPage] = []
    @ObservationIgnored private var suggestions: [String] = []
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private let ranker = CommandBarRanker()

    init(window: BrowserWindowModel, session: BrowserSession, placement: BrowserWindowModel.CommandBarPlacement, initialText: String) {
        self.window = window
        self.session = session
        self.placement = placement
        query = initialText
        refresh()
    }

    var engine: SearchEngine {
        siteSearch ?? session.settings.settings.searchEngine
    }

    // MARK: - Results

    private func refresh() {
        recompute()
        fetchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = window?.profile
        let isIncognito = window?.kind == .incognito
        fetchTask = Task { [weak self] in
            // A short pause coalesces keystrokes before hitting the database and network.
            try? await Task.sleep(for: .milliseconds(text.isEmpty ? 0 : 60))
            guard let self, !Task.isCancelled else { return }
            if let profile, !isIncognito {
                let services = session.profileServices(for: profile)
                history = await (try? services.history.searchPages(matching: text, limit: text.isEmpty ? 20 : 40)) ?? []
                guard !Task.isCancelled else { return }
                recompute()
            }
            guard shouldFetchSuggestions(for: text) else {
                suggestions = []
                return
            }
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let fetched = await (try? session.services.suggestions.suggestions(for: text, engine: engine)) ?? []
            guard !Task.isCancelled, text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            suggestions = fetched
            recompute()
        }
    }

    private func shouldFetchSuggestions(for text: String) -> Bool {
        guard session.settings.settings.showsSearchSuggestions, window?.kind != .incognito, text.count >= 2 else { return false }
        if case .url = URLInputClassifier().classify(text) { return false }
        return true
    }

    private func recompute() {
        let previousID = results.indices.contains(selectedIndex) ? results[selectedIndex].id : nil
        if siteSearch != nil {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            results = text.isEmpty ? [] : [.search(text, engine)] + suggestions.prefix(5).map { .suggestion($0, engine) }
        } else {
            results = ranker.results(
                for: query,
                engine: engine,
                tabs: tabCandidates(),
                history: history,
                suggestions: suggestions,
                commands: commandCandidates(),
                now: .now,
            )
        }
        if let previousID, let index = results.firstIndex(where: { $0.id == previousID }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, max(results.count - 1, 0))
        }
    }

    private func tabCandidates() -> [TabCandidate] {
        guard let window else { return [] }
        let selected = window.selectedItemID
        return window.workspace.items.values.compactMap { item in
            guard let tab = item.tab, item.id != selected,
                  tab.url?.scheme != InternalPage.scheme || placement == .newTab else { return nil }
            return TabCandidate(
                itemID: item.id,
                spaceID: item.container.spaceID,
                title: tab.displayTitle,
                url: tab.url,
                faviconURL: tab.faviconURL,
            )
        }
    }

    private func commandCandidates() -> [CommandDescriptor] {
        guard let window, placement == .newTab else { return [] }
        return BrowserCommand.searchable.filter(window.canPerform).map(\.descriptor)
    }

    /// Looks up the selected site's address ahead of time, so opening it doesn't wait for DNS.
    private func preresolveSelection() {
        guard results.indices.contains(selectedIndex) else { return }
        switch results[selectedIndex] {
        case let .navigate(url): session.engine.preresolver.preresolve(url)
        case let .history(page): session.engine.preresolver.preresolve(page.url)
        default: break
        }
    }

    // MARK: - Interaction

    public func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + results.count) % results.count
    }

    /// Tab key: enter site search for the selected or matching site.
    public func handleTab() -> Bool {
        guard siteSearch == nil else { return false }
        let candidate = results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
        let engine: SearchEngine? = if case let .searchSite(site) = candidate {
            site
        } else {
            results.lazy.compactMap { result -> SearchEngine? in
                if case let .searchSite(site) = result { site } else { nil }
            }.first
        }
        guard let engine else { return false }
        siteSearch = engine
        suggestions = []
        query = ""
        return true
    }

    /// Backspace in an empty field leaves site search.
    public func handleDeleteBackward() -> Bool {
        guard siteSearch != nil, query.isEmpty else { return false }
        siteSearch = nil
        refresh()
        return true
    }

    public func activateSelection() {
        if results.indices.contains(selectedIndex) {
            activate(results[selectedIndex])
        } else if let classified = URLInputClassifier().classify(query) {
            switch classified {
            case let .url(url): open(url)
            case let .search(text): engine.searchURL(for: text).map(open)
            }
        }
    }

    public func activate(_ result: CommandBarResult) {
        guard let window else { return }
        switch result {
        case let .navigate(url):
            open(url)
        case let .search(text, engine), let .suggestion(text, engine):
            if let url = engine.searchURL(for: text) { open(url) }
        case let .history(page):
            open(page.url)
        case let .tab(candidate):
            window.dismissCommandBar()
            if let spaceID = candidate.spaceID { window.switchSpace(to: spaceID) }
            window.select(candidate.itemID)
        case let .command(descriptor):
            window.dismissCommandBar()
            if let command = BrowserCommand.command(withIdentifier: descriptor.id) {
                window.perform(command)
            }
        case let .searchSite(engine):
            siteSearch = engine
            query = ""
        }
    }

    private func open(_ url: URL) {
        guard let window else { return }
        window.dismissCommandBar()
        if url.scheme == InternalPage.scheme, let page = InternalPage(url: url) {
            window.showInternalPage(page)
            return
        }
        switch placement {
        case .newTab: window.open(url, placement: .newTab)
        case .currentTab: window.open(url, placement: .currentTab)
        case .split: window.open(url, placement: .splitWithSelection)
        }
    }
}
