import Foundation
import Testing
@testable import MarcCore

struct CommandBarRankerTests {
    let ranker = CommandBarRanker()
    let now = Date(timeIntervalSince1970: 2_000_000_000)

    func page(_ url: String, _ title: String, visits: Int = 1, typed: Int = 0, daysAgo: Double = 1) -> HistoryPage {
        HistoryPage(
            url: URL(string: url)!,
            title: title,
            visitCount: visits,
            typedCount: typed,
            lastVisitedAt: now.addingTimeInterval(-daysAgo * 86400),
        )
    }

    @Test func `search comes first for plain queries`() {
        let results = ranker.results(
            for: "swift ui",
            engine: .google,
            tabs: [],
            history: [],
            suggestions: ["swift ui tutorial"],
            commands: [],
            now: now,
        )
        #expect(results.first == .search("swift ui", .google))
        #expect(results.contains(.suggestion("swift ui tutorial", .google)))
    }

    @Test func `navigation comes first for URLs`() throws {
        let results = ranker.results(for: "example.com", engine: .google, tabs: [], history: [], suggestions: [], commands: [], now: now)
        #expect(try results.first == .navigate(#require(URL(string: "https://example.com"))))
    }

    @Test func `frequently visited host wins inline autocomplete`() {
        let github = page("https://github.com/", "GitHub", visits: 40, typed: 10)
        let results = ranker.results(for: "git", engine: .google, tabs: [], history: [github], suggestions: [], commands: [], now: now)
        #expect(results.first == .history(github))
        #expect(results.dropFirst().first == .search("git", .google))
    }

    @Test func `open tabs are offered and hidden from history`() throws {
        let url = try #require(URL(string: "https://news.ycombinator.com/"))
        let tab = TabCandidate(itemID: SidebarItem.ID(), spaceID: nil, title: "Hacker News", url: url, faviconURL: nil)
        let results = ranker.results(
            for: "hacker",
            engine: .google,
            tabs: [tab],
            history: [page(url.absoluteString, "Hacker News", visits: 5)],
            suggestions: [],
            commands: [],
            now: now,
        )
        #expect(results.contains(.tab(tab)))
        #expect(!results.contains {
            if case .history = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test func `commands match title and keywords`() {
        let toggle = CommandDescriptor(id: "toggle-sidebar", title: "Toggle Sidebar", keywords: ["hide"], symbol: "sidebar.left")
        let results = ranker.results(for: "hide", engine: .google, tabs: [], history: [], suggestions: [], commands: [toggle], now: now)
        #expect(results.contains(.command(toggle)))
    }

    @Test func `site search is offered for keyword prefixes`() {
        let results = ranker.results(for: "youtu", engine: .google, tabs: [], history: [], suggestions: [], commands: [], now: now)
        #expect(results.contains {
            if case let .searchSite(engine) = $0 {
                engine.id == "youtube"
            } else {
                false
            }
        })
    }

    @Test func `empty query shows top history by frecency`() {
        let recent = page("https://a.com", "A", visits: 3, daysAgo: 1)
        let stale = page("https://b.com", "B", visits: 3, daysAgo: 200)
        let results = ranker.results(for: "", engine: .google, tabs: [], history: [stale, recent], suggestions: [], commands: [], now: now)
        #expect(results == [.history(recent), .history(stale)])
    }

    @Test func `results are unique`() {
        let results = ranker.results(
            for: "swift",
            engine: .google,
            tabs: [],
            history: [],
            suggestions: ["swift", "swift", "swiftui"],
            commands: [],
            now: now,
        )
        #expect(Set(results.map(\.id)).count == results.count)
        #expect(!results.contains(.suggestion("swift", .google)))
    }

    @Test func `frecency decays with age`() {
        #expect(Frecency.score(page("https://a.com", "A", visits: 10, daysAgo: 1), now: now)
            > Frecency.score(page("https://a.com", "A", visits: 10, daysAgo: 100), now: now))
        #expect(Frecency.score(page("https://a.com", "A", visits: 1, typed: 1), now: now)
            > Frecency.score(page("https://a.com", "A", visits: 1), now: now))
    }
}
