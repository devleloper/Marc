import Foundation
import MarcCore
import MarcWebKit
import Observation

/// A link from a pinned tab or favorite shown in a floating card above the page.
@Observable
public final class PeekModel: Identifiable {
    public let id = UUID()
    public let tab: WebTab
    public let sourceItemID: SidebarItem.ID

    @ObservationIgnored private weak var window: BrowserWindowModel?

    init(url: URL, sourceItemID: SidebarItem.ID, context: ProfileWebContext, window: BrowserWindowModel, session: BrowserSession) {
        self.sourceItemID = sourceItemID
        self.window = window
        tab = session.runtime.tab(id: SidebarItem.ID(), url: url, title: "", context: context)
        tab.load(url, initiator: .webContent, transition: .link)
    }

    public func close() {
        window?.session?.runtime.close(tab.id)
        window?.peek = nil
    }

    /// Keeps the page as a Today tab, reusing the loaded web view.
    public func openAsTab(split: Bool = false) {
        guard let window, let spaceID = window.state.spaceID, let url = tab.url else { return }
        let content = TabContent(url: url, title: tab.title)
        let anchor = window.selectedItemID
        guard (try? window.store.update({ try $0.openTab(content, placement: .todayTop(spaceID), id: tab.id) })) != nil else { return }
        if split, let anchor {
            try? window.store.update { try $0.split(anchor, with: tab.id) }
        }
        window.peek = nil
        window.select(tab.id)
    }
}

/// The page assistant: a streamed summary and questions about the page.
@Observable
public final class AssistantModel {
    public enum Mode: Hashable {
        case summary
        case ask
    }

    public struct Exchange: Identifiable {
        public let id = UUID()
        public let question: String
        public var answer: String
    }

    public var mode: Mode
    public var summary = ""
    public var exchanges: [Exchange] = []
    public var draftQuestion = ""
    public private(set) var isRunning = false
    public private(set) var errorMessage: String?
    public private(set) var wasTruncated = false
    public private(set) var providerName: String?
    public let tabID: SidebarItem.ID

    @ObservationIgnored private weak var window: BrowserWindowModel?
    @ObservationIgnored private let session: BrowserSession
    @ObservationIgnored private var task: Task<Void, Never>?

    init(tabID: SidebarItem.ID, window: BrowserWindowModel, session: BrowserSession, mode: Mode) {
        self.tabID = tabID
        self.window = window
        self.session = session
        self.mode = mode
    }

    public func summarize() {
        run { provider, page in
            let (request, truncated) = AIPrompts.summary(of: page, characterLimit: provider.maximumInputCharacters)
            return (request, truncated)
        } onDelta: { [weak self] delta in
            self?.summary += delta
        } onStart: { [weak self] in
            self?.summary = ""
        }
    }

    public func ask() {
        let question = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning else { return }
        draftQuestion = ""
        let previous = exchanges.map { (question: $0.question, answer: $0.answer) }
        exchanges.append(Exchange(question: question, answer: ""))
        let index = exchanges.count - 1
        run { provider, page in
            AIPrompts.answer(question, about: page, previousExchanges: previous, characterLimit: provider.maximumInputCharacters)
        } onDelta: { [weak self] delta in
            guard let self, exchanges.indices.contains(index) else { return }
            exchanges[index].answer += delta
        } onStart: {}
    }

    public func cancel() {
        task?.cancel()
        isRunning = false
    }

    private func run(
        _ makeRequest: @escaping (any LanguageModelProvider, PageContent) -> (LanguageModelRequest, Bool),
        onDelta: @escaping (String) -> Void,
        onStart: @escaping () -> Void,
    ) {
        task?.cancel()
        errorMessage = nil
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            defer { isRunning = false }
            guard let provider = await session.services.languageModels.provider(for: session.settings.settings.aiProvider) else {
                errorMessage = session.settings.settings.aiProvider == .off
                    ? "AI features are turned off in Settings."
                    : "No AI model is available. Add a Claude API key in Settings › AI, or enable Apple Intelligence on macOS 26."
                return
            }
            providerName = provider.kind == .claude ? "Claude" : "Apple Intelligence"
            guard let tab = session.runtime.tab(for: tabID), let page = await tab.pageContent() else {
                errorMessage = "The page content could not be read."
                return
            }
            let (request, truncated) = makeRequest(provider, page)
            wasTruncated = truncated
            onStart()
            do {
                for try await delta in provider.stream(request) {
                    guard !Task.isCancelled else { return }
                    onDelta(delta)
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = (error as? LanguageModelError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

/// Editing state of a Boost for the current site.
@Observable
public final class BoostEditorModel {
    public var boost: Boost {
        didSet { preview() }
    }

    public let tabID: SidebarItem.ID
    public let isNew: Bool

    @ObservationIgnored private weak var window: BrowserWindowModel?

    init(boost: Boost, tabID: SidebarItem.ID, window: BrowserWindowModel) {
        self.boost = boost
        self.tabID = tabID
        self.window = window
        isNew = window.session?.boosts.boosts.contains { $0.id == boost.id } == false
    }

    private var tab: WebTab? {
        window?.session?.runtime.tab(for: tabID)
    }

    public var isPicking: Bool {
        tab?.isPickingElements ?? false
    }

    public func preview() {
        tab?.applyBoostStyles([boost])
    }

    public func startPicking() {
        tab?.startElementPicker()
    }

    public func stopPicking() {
        tab?.stopElementPicker()
    }

    func addZappedSelector(_ selector: String) {
        guard !boost.zappedSelectors.contains(selector) else { return }
        boost.zappedSelectors.append(selector)
    }

    public func removeZappedSelector(_ selector: String) {
        boost.zappedSelectors.removeAll { $0 == selector }
    }

    public func save() {
        stopPicking()
        window?.session?.boosts.save(boost)
        if !boost.customJavaScript.isEmpty { tab?.reload() }
        window?.boostEditor = nil
    }

    public func discard() {
        stopPicking()
        let saved = window?.session?.boosts.boosts.first { $0.id == boost.id }
        tab?.applyBoostStyles([saved ?? Boost(id: boost.id, name: boost.name, hostPattern: boost.hostPattern, isEnabled: false)])
        window?.boostEditor = nil
    }

    public func delete() {
        stopPicking()
        window?.session?.boosts.delete(boost.id)
        window?.boostEditor = nil
    }
}
