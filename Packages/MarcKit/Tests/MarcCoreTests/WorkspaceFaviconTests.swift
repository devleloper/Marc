import Foundation
import Testing
@testable import MarcCore

struct WorkspaceFaviconTests {
    var workspace = Workspace.makeDefault()
    var spaceID: Space.ID { workspace.orderedSpaces[0].id }

    @Test func `conventional favicon URL keeps scheme, host and port`() throws {
        let page = try #require(URL(string: "http://example.com:8080/a/b?q=1#top"))
        #expect(Workspace.conventionalFaviconURL(for: page) == URL(string: "http://example.com:8080/favicon.ico"))
    }

    @Test(arguments: ["about:blank", "file:///Users/me/page.html", "marc://settings", "data:text/plain,hi"])
    func `non-web URLs have no conventional favicon`(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(Workspace.conventionalFaviconURL(for: url) == nil)
    }

    @Test mutating func `groups tabs without icons by site`() throws {
        let first = try workspace.openTab(TabContent(url: URL(string: "https://swift.org/blog")), placement: .todayTop(spaceID))
        let second = try workspace.openTab(TabContent(url: URL(string: "https://swift.org/documentation")), placement: .pinnedEnd(spaceID))
        let other = try workspace.openTab(TabContent(url: URL(string: "https://webkit.org")), placement: .todayTop(spaceID))
        try workspace.openTab(
            TabContent(url: URL(string: "https://github.com"), faviconURL: URL(string: "https://github.com/icon.png")),
            placement: .todayTop(spaceID),
        )
        try workspace.openTab(TabContent(url: URL(string: "about:blank")), placement: .todayTop(spaceID))

        let missing = workspace.tabsMissingFavicons()
        let swiftIcon = try #require(URL(string: "https://swift.org/favicon.ico"))
        let webKitIcon = try #require(URL(string: "https://webkit.org/favicon.ico"))
        #expect(missing.count == 2)
        #expect(Set(missing[swiftIcon] ?? []) == [first, second])
        #expect(missing[webKitIcon] == [other])
    }
}
