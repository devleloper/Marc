import Foundation

/// Reads Chrome's (and other Chromium browsers') `Bookmarks` JSON file.
public struct ChromeBookmarksParser: Sendable {
    public init() {}

    private struct File: Decodable {
        let roots: [String: Node]
    }

    private struct Node: Decodable {
        let type: String?
        let name: String?
        let url: String?
        let children: [Node]?
    }

    public func parse(_ data: Data) throws -> [ImportedNode] {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw BrowserImportError.unreadableFormat }
        let order = ["bookmark_bar", "other", "synced"]
        let roots = order.compactMap { file.roots[$0] } + file.roots.filter { !order.contains($0.key) }.map(\.value)
        let nodes = roots.compactMap { root -> ImportedNode? in
            let children = (root.children ?? []).compactMap(convert)
            guard !children.isEmpty else { return nil }
            return .folder(name: root.name ?? "Bookmarks", children: children)
        }
        guard !nodes.isEmpty else { throw BrowserImportError.nothingToImport }
        return nodes
    }

    private func convert(_ node: Node) -> ImportedNode? {
        if node.type == "url" {
            guard let url = URL.importable(node.url) else { return nil }
            return .link(ImportedLink(title: node.name ?? url.displayString, url: url))
        }
        let children = (node.children ?? []).compactMap(convert)
        return children.isEmpty ? nil : .folder(name: node.name ?? "Folder", children: children)
    }
}

/// Reads Safari's `Bookmarks.plist`, skipping the Reading List.
public struct SafariBookmarksParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> [ImportedNode] {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BrowserImportError.unreadableFormat
        }
        let nodes = (root["Children"] as? [[String: Any]] ?? []).compactMap(convert)
        guard !nodes.isEmpty else { throw BrowserImportError.nothingToImport }
        return nodes
    }

    private func convert(_ entry: [String: Any]) -> ImportedNode? {
        switch entry["WebBookmarkType"] as? String {
        case "WebBookmarkTypeLeaf":
            guard let url = URL.importable(entry["URLString"] as? String) else { return nil }
            let title = (entry["URIDictionary"] as? [String: Any])?["title"] as? String
            return .link(ImportedLink(title: title ?? url.displayString, url: url))
        case "WebBookmarkTypeList":
            let title = entry["Title"] as? String ?? "Folder"
            guard title != "com.apple.ReadingList" else { return nil }
            let children = (entry["Children"] as? [[String: Any]] ?? []).compactMap(convert)
            let displayName = title == "BookmarksBar" ? "Favorites Bar" : title == "BookmarksMenu" ? "Bookmarks Menu" : title
            return children.isEmpty ? nil : .folder(name: displayName, children: children)
        default:
            return nil
        }
    }
}

/// Reads the Netscape bookmark file format exported by every major browser.
public struct NetscapeBookmarksParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> [ImportedNode] {
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              html.range(of: "<DL", options: .caseInsensitive) != nil
        else { throw BrowserImportError.unreadableFormat }

        var stack: [(name: String, children: [ImportedNode])] = [("Bookmarks", [])]
        var pendingFolderName: String?

        for token in try Self.tokens(in: html) {
            switch token {
            case let .folderTitle(name):
                pendingFolderName = name
            case .listStart:
                stack.append((pendingFolderName ?? "Folder", []))
                pendingFolderName = nil
            case .listEnd:
                guard stack.count > 1 else { continue }
                let folder = stack.removeLast()
                if !folder.children.isEmpty {
                    stack[stack.count - 1].children.append(.folder(name: folder.name, children: folder.children))
                }
            case let .link(href, title):
                guard let url = URL.importable(href) else { continue }
                stack[stack.count - 1].children.append(.link(ImportedLink(title: title.isEmpty ? url.displayString : title, url: url)))
            }
        }
        while stack.count > 1 {
            let folder = stack.removeLast()
            if !folder.children.isEmpty {
                stack[stack.count - 1].children.append(.folder(name: folder.name, children: folder.children))
            }
        }
        // Exports wrap everything in one top-level list; unwrap it.
        var nodes = stack[0].children
        if nodes.count == 1, case let .folder(_, children) = nodes[0] { nodes = children }
        guard !nodes.isEmpty else { throw BrowserImportError.nothingToImport }
        return nodes
    }

    private enum Token {
        case folderTitle(String)
        case listStart
        case listEnd
        case link(href: String, title: String)
    }

    private static let markupPattern = #"<H3[^>]*>(.*?)</H3>|<DL[^>]*>|</DL>|<A\s[^>]*?HREF\s*=\s*"([^"]*)"[^>]*>(.*?)</A>"#

    private static func tokens(in html: String) throws -> [Token] {
        let expression = try NSRegularExpression(pattern: markupPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..., in: html)
        return expression.matches(in: html, range: range).compactMap { match in
            func group(_ index: Int) -> String? {
                guard let range = Range(match.range(at: index), in: html) else { return nil }
                return String(html[range])
            }
            let whole = group(0)?.uppercased() ?? ""
            if let title = group(1) { return .folderTitle(decodeEntities(title)) }
            if let href = group(2) { return .link(href: decodeEntities(href), title: decodeEntities(group(3) ?? "")) }
            if whole.hasPrefix("</DL") { return .listEnd }
            if whole.hasPrefix("<DL") { return .listStart }
            return nil
        }
    }

    static func decodeEntities(_ text: String) -> String {
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        return entities.reduce(stripped) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
