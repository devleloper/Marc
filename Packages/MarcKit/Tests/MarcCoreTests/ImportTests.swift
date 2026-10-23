import Foundation
import Testing
@testable import MarcCore

func fixture(_ name: String, _ ext: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

struct ArcSidebarParserTests {
    @Test func `parses spaces folders splits and favorites`() throws {
        let result = try ArcSidebarParser().parse(fixture("arc-sidebar", "json"))
        #expect(result.source == .arc)
        #expect(result.spaces.map(\.name) == ["Work", "Side"])

        let work = result.spaces[0]
        #expect(work.icon == .emoji("💼"))
        #expect(work.profile == .default)
        #expect(work.pinned.count == 3, "Easels are skipped")
        guard case let .folder(name, children) = work.pinned[0] else { Issue.record("expected folder")
            return
        }
        #expect(name == "Docs")
        #expect(
            try children == [.link(ImportedLink(title: "The Spec", url: #require(URL(string: "https://example.com/spec"))))],
            "javascript: bookmarklets are dropped",
        )
        #expect(try work.pinned[2] == .split(
            links: [
                ImportedLink(title: "A", url: #require(URL(string: "https://a.example.com/"))),
                ImportedLink(title: "B", url: #require(URL(string: "https://b.example.com/"))),
            ],
            axis: .horizontal,
        ))
        #expect(work.today.count == 1)

        #expect(result.spaces[1].profile == .named("Profile 1"))
        #expect(result.favorites[.default]?.map(\.url.host) == ["github.com"])
    }

    @Test func `maps the window theme`() throws {
        let theme = try #require(try ArcSidebarParser().parse(fixture("arc-sidebar", "json")).spaces[0].theme)
        #expect(theme.appearance == .dark)
        #expect(theme.colors.count == 2)
        #expect(abs(theme.colors[0].blue - 0.4) < 0.001)
        #expect(abs(theme.grain - 0.3) < 0.001)
    }

    @Test func `rejects unrelated JSON`() {
        #expect(throws: BrowserImportError.unreadableFormat) { try ArcSidebarParser().parse(Data(#"{"a":1}"#.utf8)) }
    }
}

struct BookmarkParserTests {
    @Test func `parses chrome roots and skips non web URLs`() throws {
        let nodes = try ChromeBookmarksParser().parse(fixture("chrome-bookmarks", "json"))
        #expect(nodes.count == 2, "Empty roots are skipped")
        guard case let .folder(name, children) = nodes[0] else { Issue.record("expected folder")
            return
        }
        #expect(name == "Bookmarks bar")
        #expect(children.count == 2)
        guard case let .folder(_, tools) = children[1] else { Issue.record("expected folder")
            return
        }
        #expect(tools.count == 1)
    }

    @Test func `parses safari bookmarks without the reading list`() throws {
        let nodes = try SafariBookmarksParser().parse(fixture("safari-bookmarks", "plist"))
        #expect(nodes.count == 2)
        #expect(try nodes[0] == .folder(
            name: "Favorites Bar",
            children: [.link(ImportedLink(title: "WebKit", url: #require(URL(string: "https://webkit.org/"))))],
        ))
    }

    @Test func `parses netscape HTML with entities and nesting`() throws {
        let nodes = try NetscapeBookmarksParser().parse(fixture("bookmarks", "html"))
        #expect(nodes.count == 2)
        guard case let .folder(name, children) = nodes[0] else { Issue.record("expected folder")
            return
        }
        #expect(name == "Toolbar")
        #expect(try children.first == .link(ImportedLink(title: "Swift & Friends", url: #require(URL(string: "https://swift.org/")))))
        #expect(try children.last == .folder(
            name: "Nested",
            children: [.link(ImportedLink(title: "Example", url: #require(URL(string: "https://example.com/a?b=1&c=2"))))],
        ))
        #expect(try nodes[1] == .link(ImportedLink(title: "Apple", url: #require(URL(string: "https://apple.com/")))))
    }
}

struct WorkspaceImportTests {
    @Test func `applies an arc import`() throws {
        var workspace = Workspace.makeDefault()
        let target = workspace.orderedSpaces[0].id
        let imported = try ArcSidebarParser().parse(fixture("arc-sidebar", "json"))
        let summary = try workspace.apply(imported, targetSpace: target)

        #expect(summary.spaces == 2)
        #expect(summary.favorites == 1)
        #expect(workspace.orderedProfiles.count == 2, "The custom Arc profile becomes a new profile")
        let work = try #require(workspace.orderedSpaces.first { $0.name == "Work" })
        #expect(work.profileID == workspace.orderedSpaces[0].profileID)
        let pinned = workspace.children(of: .pinned(work.id))
        #expect(pinned.map(\.kind) == [.folder, .tab, .split])
        #expect(workspace.children(of: .today(work.id)).count == 1)

        // Importing again does not duplicate favorites.
        let again = try workspace.apply(imported, targetSpace: target)
        #expect(again.favorites == 0)
    }

    @Test func `puts plain bookmarks into one collapsed folder`() throws {
        var workspace = Workspace.makeDefault()
        let target = workspace.orderedSpaces[0].id
        let bookmarks = try ChromeBookmarksParser().parse(fixture("chrome-bookmarks", "json"))
        let summary = try workspace.apply(BrowserImport(source: .chrome, bookmarks: bookmarks), targetSpace: target)

        let root = workspace.children(of: .pinned(target))
        #expect(root.count == 1)
        #expect(root[0].folder?.name == "Google Chrome Bookmarks")
        #expect(root[0].folder?.isExpanded == false)
        #expect(summary.tabs == 3)
    }
}
