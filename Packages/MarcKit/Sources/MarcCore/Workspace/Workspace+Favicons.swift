import Foundation

public extension Workspace {
    /// Saved tabs that have never shown a site icon (imported, restored before they loaded, or
    /// opened in the background), grouped by their site's conventional `/favicon.ico` address.
    func tabsMissingFavicons() -> [URL: [SidebarItem.ID]] {
        var result: [URL: [SidebarItem.ID]] = [:]
        for item in items.values {
            guard let tab = item.tab, tab.faviconURL == nil,
                  let iconURL = (tab.url ?? tab.homeURL).flatMap(Self.conventionalFaviconURL(for:))
            else { continue }
            result[iconURL, default: []].append(item.id)
        }
        return result
    }

    /// `scheme://host[:port]/favicon.ico` for web pages; `nil` for every other URL.
    static func conventionalFaviconURL(for pageURL: URL) -> URL? {
        guard let scheme = pageURL.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = pageURL.host(), !host.isEmpty
        else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = pageURL.port
        components.path = "/favicon.ico"
        return components.url
    }
}
