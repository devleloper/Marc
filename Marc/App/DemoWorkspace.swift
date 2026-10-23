import Foundation
import MarcCore
import MarcUI

/// Sample favorites, pinned tabs and Spaces for screenshots and manual testing. Enabled with
/// `-ui-testing -demo-workspace`, so it only ever fills the UI-testing session's in-memory database.
@MainActor
enum DemoWorkspace {
    static var isRequested: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-ui-testing") && arguments.contains("-demo-workspace")
    }

    /// Fills the workspace and returns the tab to show first.
    @discardableResult
    static func populate(_ store: WorkspaceStore) -> SidebarItem.ID? {
        try? store.update { workspace in
            guard let profile = workspace.orderedProfiles.first, let space = workspace.orderedSpaces.first else { return nil }
            try workspace.updateSpace(space.id) { $0.name = "Personal" }

            for (title, address) in [
                ("Wikipedia", "https://www.wikipedia.org"),
                ("GitHub", "https://github.com"),
                ("Swift", "https://www.swift.org"),
                ("WebKit", "https://webkit.org"),
            ] {
                try workspace.openTab(tab(title, address), placement: .favoritesEnd(profile.id))
            }

            let folder = try workspace.createFolder(
                named: "Reading",
                at: SidebarDestination(container: .pinned(space.id), index: 0),
            )
            try workspace.openTab(tab("Hacker News", "https://news.ycombinator.com"), placement: .inFolder(folder))
            try workspace.openTab(tab("Lobsters", "https://lobste.rs"), placement: .inFolder(folder))
            try workspace.openTab(
                tab("Swift Evolution", "https://www.swift.org/swift-evolution/"),
                placement: .pinnedEnd(space.id),
            )

            try workspace.openTab(tab("WebKit", "https://webkit.org/blog/"), placement: .todayTop(space.id))
            let first = try workspace.openTab(
                tab("Web browser — Wikipedia", "https://en.wikipedia.org/wiki/Web_browser"),
                placement: .todayTop(space.id),
            )

            let work = try workspace.addSpace(
                name: "Work",
                profileID: profile.id,
                icon: .symbol("briefcase.fill"),
                theme: Theme.presets[2],
            )
            try workspace.openTab(tab("Swift Package Index", "https://swiftpackageindex.com"), placement: .pinnedEnd(work))
            try workspace.openTab(tab("Swift.org", "https://www.swift.org"), placement: .todayTop(work))
            try workspace.addSpace(name: "Ideas", profileID: profile.id, icon: .symbol("lightbulb.fill"), theme: Theme.presets[6])
            return first
        }
    }

    private static func tab(_ title: String, _ address: String) -> TabContent {
        TabContent(url: URL(string: address), title: title, homeURL: URL(string: address))
    }
}
