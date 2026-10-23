import Foundation
import MarcCore
import MarcWebKit
import Testing
@testable import MarcUI

@MainActor
struct BrowserWindowModelTests {
    let blank = URL(string: "about:blank")!

    /// Keeps the session alive for the whole test; windows only hold it weakly.
    final class Fixture {
        let session: BrowserSession
        let window: BrowserWindowModel

        init(session: BrowserSession) {
            self.session = session
            window = session.openWindow()
        }
    }

    func makeWindow() async throws -> Fixture {
        let (session, _, _) = try await TestSession.make()
        return Fixture(session: session)
    }

    @Test func `drop highlights reset once drag updates stop`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let before = window.dropHighlightResets
        window.noteDropActivity(quietPeriod: .milliseconds(20))
        window.noteDropActivity(quietPeriod: .milliseconds(20))
        #expect(window.dropHighlightResets == before, "Updates keep the highlight")
        // Poll rather than sleep a fixed time: busy CI machines can take a while to run the reset.
        for _ in 0 ..< 250 where window.dropHighlightResets == before {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(window.dropHighlightResets == before + 1, "One reset after updates stop")
    }

    @Test func `opening a url adds a selected today tab`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let id = try #require(window.open(blank, placement: .newTab))
        #expect(window.selectedItemID == id)
        #expect(try window.workspace.items[id]?.container == .today(#require(window.state.spaceID)))
        #expect(window.selectedTab?.id == id)
        withExtendedLifetime(fixture) {}
    }

    @Test func `background tabs do not take the selection`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let first = window.open(blank, placement: .newTab)
        _ = window.open(blank, placement: .backgroundTab, select: false)
        #expect(window.selectedItemID == first)
        withExtendedLifetime(fixture) {}
    }

    @Test func `closing a today tab archives it and selects the neighbor`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let session = fixture.session
        let first = try #require(URL(string: "https://example.com/a"))
        let second = try #require(URL(string: "https://example.com/b"))
        let older = try #require(window.open(first, placement: .newTab))
        let newer = try #require(window.open(second, placement: .newTab))
        #expect(window.selectedItemID == newer)

        window.closeSelected()
        #expect(window.workspace.items[newer] == nil)
        #expect(window.selectedItemID == older)
        #expect(session.archive.tabs.first?.url == URL(string: "https://example.com/b"))
        #expect(session.runtime.tab(for: newer) == nil)

        window.restoreLastClosedTab()
        #expect(window.selectedTab?.url == URL(string: "https://example.com/b"))
        withExtendedLifetime(fixture) {}
    }

    @Test func `closing a pinned tab only unloads it`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let session = fixture.session
        let id = try #require(window.open(blank, placement: .newTab))
        window.perform(.pinTab)
        #expect(try window.workspace.items[id]?.container == .pinned(#require(window.state.spaceID)))
        window.closeSelected()
        #expect(window.workspace.items[id] != nil)
        #expect(session.runtime.tab(for: id)?.hasWebView == false)
        withExtendedLifetime(fixture) {}
    }

    @Test func `clear today removes only unpinned tabs`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        _ = window.open(blank, placement: .newTab)
        window.perform(.pinTab)
        _ = window.open(blank, placement: .newTab)
        _ = window.open(blank, placement: .newTab)
        window.clearToday()
        let spaceID = try #require(window.state.spaceID)
        #expect(window.workspace.children(of: .today(spaceID)).isEmpty)
        #expect(window.workspace.children(of: .pinned(spaceID)).count == 1)
        withExtendedLifetime(fixture) {}
    }

    @Test func `split command opens the result next to the selection`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let first = try #require(window.open(blank, placement: .newTab))
        let second = try #require(window.open(blank, placement: .splitWithSelection))
        #expect(window.selectedSplit?.split?.layout.panes == [first, second])
        #expect(window.displayedLeafIDs == [first, second])
        #expect(window.canPerform(.separateSplitPane))
        withExtendedLifetime(fixture) {}
    }

    @Test func `spaces switch by offset and number`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        let first = try #require(window.state.spaceID)
        let profileID = try #require(window.profile?.id)
        let second = try window.store.update { try $0.addSpace(name: "Work", profileID: profileID) }
        window.switchSpace(offset: 1)
        #expect(window.state.spaceID == second)
        #expect(window.spaceChangeIsForward)
        window.switchSpace(number: 1)
        #expect(window.state.spaceID == first)
        #expect(!window.spaceChangeIsForward)
        withExtendedLifetime(fixture) {}
    }

    @Test func `internal pages reuse their tab`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        window.perform(.showHistory)
        let first = window.selectedItemID
        _ = window.open(blank, placement: .newTab)
        window.perform(.showHistory)
        #expect(window.selectedItemID == first)
        #expect(window.selectedItem?.tab?.url == InternalPage.history.url)
        withExtendedLifetime(fixture) {}
    }

    @Test func `page commands need a page`() async throws {
        let fixture = try await makeWindow()
        let window = fixture.window
        #expect(!window.canPerform(.reload))
        #expect(!window.canPerform(.boostSite))
        #expect(window.canPerform(.newTab))
        _ = try window.open(#require(URL(string: "https://example.com")), placement: .newTab)
        #expect(window.canPerform(.reload))
        #expect(window.canPerform(.copyURL))
        withExtendedLifetime(fixture) {}
    }

    @Test func `incognito windows keep tabs to themselves`() async throws {
        let fixture = try await makeWindow()
        let session = fixture.session
        let incognito = session.openEphemeralWindow(kind: .incognito)
        let id = try #require(incognito.open(blank, placement: .newTab))
        #expect(session.store.workspace.items[id] == nil)
        #expect(session.runtime.tab(for: id)?.context.isIncognito == true)
        #expect(!incognito.canPerform(.pinTab))
        withExtendedLifetime(fixture) {}
    }
}

@MainActor
struct CommandBarModelTests {
    @Test func `typing a url and pressing return opens it`() async throws {
        let (session, _, _) = try await TestSession.make()
        let window = session.openWindow()
        defer { withExtendedLifetime(session) {} }
        window.showCommandBar(.newTab)
        let bar = try #require(window.commandBar)
        bar.query = "about:blank"
        #expect(try bar.results.first == .navigate(#require(URL(string: "about:blank"))))
        bar.activateSelection()
        #expect(window.commandBar == nil)
        #expect(window.selectedTab?.url == URL(string: "about:blank"))
    }

    @Test func `commands are offered and run`() async throws {
        let (session, _, _) = try await TestSession.make()
        let window = session.openWindow()
        defer { withExtendedLifetime(session) {} }
        window.showCommandBar(.newTab)
        let bar = try #require(window.commandBar)
        bar.query = "toggle side"
        let command = try #require(bar.results.first {
            if case .command = $0 {
                true
            } else {
                false
            }
        })
        let wasVisible = window.isSidebarVisible
        bar.activate(command)
        #expect(window.isSidebarVisible != wasVisible)
    }

    @Test func `tab enters site search`() async throws {
        let (session, _, _) = try await TestSession.make()
        let window = session.openWindow()
        defer { withExtendedLifetime(session) {} }
        window.showCommandBar(.newTab)
        let bar = try #require(window.commandBar)
        bar.query = "wikip"
        #expect(bar.handleTab())
        #expect(bar.siteSearch?.id == "wikipedia")
        bar.query = "browsers"
        #expect(try bar.results.first == .search("browsers", #require(bar.siteSearch)))
        #expect(bar.handleDeleteBackward() == false)
        bar.query = ""
        #expect(bar.handleDeleteBackward())
        #expect(bar.siteSearch == nil)
    }
}
