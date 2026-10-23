import Foundation

/// Reads Arc's `StorableSidebar.json`: Spaces with their pinned and unpinned trees, folders,
/// split views, favorites per profile, icons and base theme colors. Easels and other Arc-only
/// item types are skipped.
public struct ArcSidebarParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> BrowserImport {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sidebar = root["sidebar"] as? [String: Any],
              let containers = sidebar["containers"] as? [[String: Any]],
              let container = containers.first(where: { $0["spaces"] != nil && $0["items"] != nil })
        else { throw BrowserImportError.unreadableFormat }

        let items = Self.itemsByID(container["items"] as? [Any] ?? [])
        let tree = ArcTree(items: items)

        let spaces = (container["spaces"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map { space in
            let containerIDs = Self.containerIDs(space["containerIDs"] as? [Any] ?? [])
            let customInfo = space["customInfo"] as? [String: Any]
            return ImportedSpace(
                name: (space["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Imported Space",
                icon: Self.icon(customInfo?["iconType"] as? [String: Any]),
                theme: Self.theme(customInfo?["windowTheme"] as? [String: Any]),
                profile: Self.profileKey(space["profile"]),
                pinned: containerIDs["pinned"].map(tree.children) ?? [],
                today: containerIDs["unpinned"].map(tree.children) ?? [],
            )
        }

        var favorites: [ImportedProfileKey: [ImportedLink]] = [:]
        for (key, containerID) in Self.favoritesContainers(container["topAppsContainerIDs"] as? [Any] ?? []) {
            favorites[key, default: []] += tree.children(of: containerID).compactMap { node in
                if case let .link(link) = node { link } else { nil }
            }
        }

        let result = BrowserImport(source: .arc, spaces: spaces, favorites: favorites)
        guard !result.isEmpty else { throw BrowserImportError.nothingToImport }
        return result
    }

    // MARK: - Structure

    /// Arc stores dictionaries as flat arrays alternating keys and values.
    static func itemsByID(_ flat: [Any]) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for case let item as [String: Any] in flat {
            if let id = item["id"] as? String { result[id] = item }
        }
        return result
    }

    /// `["unpinned", id, "pinned", id]` → `["unpinned": id, "pinned": id]`.
    static func containerIDs(_ flat: [Any]) -> [String: String] {
        var result: [String: String] = [:]
        var index = 0
        while index + 1 < flat.count {
            if let label = flat[index] as? String, let id = flat[index + 1] as? String { result[label] = id }
            index += 2
        }
        return result
    }

    /// `[{"default": true}, id, {"custom": {"_0": {"directoryBasename": "Profile 1"}}}, id]`.
    static func favoritesContainers(_ flat: [Any]) -> [(ImportedProfileKey, String)] {
        var result: [(ImportedProfileKey, String)] = []
        var index = 0
        while index + 1 < flat.count {
            if let id = flat[index + 1] as? String { result.append((profileKey(flat[index]), id)) }
            index += 2
        }
        return result
    }

    static func profileKey(_ value: Any?) -> ImportedProfileKey {
        guard let profile = value as? [String: Any], let custom = profile["custom"] as? [String: Any] else { return .default }
        let details = custom["_0"] as? [String: Any]
        return .named(details?["directoryBasename"] as? String ?? "Custom")
    }

    static func icon(_ iconType: [String: Any]?) -> SpaceIcon? {
        if let emoji = iconType?["emoji_v2"] as? String, !emoji.isEmpty { return .emoji(emoji) }
        return nil
    }

    static func theme(_ windowTheme: [String: Any]?) -> Theme? {
        guard let windowTheme else { return nil }
        let single = (windowTheme["background"] as? [String: Any])?["single"] as? [String: Any]
        let background = single?["_0"] as? [String: Any]
        let blended =
            ((((background?["style"] as? [String: Any])?["color"] as? [String: Any])?["_0"] as? [String: Any])?["blendedSingleColor"]
                as? [String: Any])?["_0"] as? [String: Any]
        let palette = windowTheme["primaryColorPalette"] as? [String: Any]

        guard let color = rgb(blended?["color"]) ?? rgb(palette?["midTone"]) else { return nil }
        let modifiers = blended?["modifiers"] as? [String: Any]
        let noise = (modifiers?["noiseFactor"] as? NSNumber)?.doubleValue ?? 0
        let appearance: Theme.Appearance = switch background?["contentOverBackgroundAppearance"] as? String {
        case "light": .light
        case "dark": .dark
        default: color.relativeLuminance < 0.4 ? .dark : .light
        }
        var colors = [color]
        if let shaded = rgb(palette?["shaded"]), shaded != color { colors.append(shaded) }
        return Theme(colors: colors, appearance: appearance, grain: min(noise / 100, 1))
    }

    static func rgb(_ value: Any?) -> RGBColor? {
        guard let dictionary = value as? [String: Any],
              let red = (dictionary["red"] as? NSNumber)?.doubleValue,
              let green = (dictionary["green"] as? NSNumber)?.doubleValue,
              let blue = (dictionary["blue"] as? NSNumber)?.doubleValue
        else { return nil }
        return RGBColor(red: red, green: green, blue: blue)
    }
}

/// Resolves Arc items into importable nodes.
private struct ArcTree {
    let items: [String: [String: Any]]

    func children(of id: String) -> [ImportedNode] {
        children(of: id, depth: 0)
    }

    private func children(of id: String, depth: Int) -> [ImportedNode] {
        // Guards against malformed files with cyclic parent references.
        guard depth < 32, let item = items[id] else { return [] }
        return (item["childrenIds"] as? [String] ?? []).compactMap { node(for: $0, depth: depth + 1) }
    }

    private func node(for id: String, depth: Int) -> ImportedNode? {
        guard let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
        let customTitle = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        if let tab = data["tab"] as? [String: Any] {
            return link(tab: tab, customTitle: customTitle).map(ImportedNode.link)
        }
        if data["list"] != nil {
            return .folder(name: customTitle ?? "Folder", children: children(of: id, depth: depth))
        }
        if let split = data["splitView"] as? [String: Any] {
            let links = (item["childrenIds"] as? [String] ?? []).compactMap { childID -> ImportedLink? in
                guard let child = items[childID], let tab = (child["data"] as? [String: Any])?["tab"] as? [String: Any] else { return nil }
                return link(tab: tab, customTitle: (child["title"] as? String).flatMap { $0.isEmpty ? nil : $0 })
            }
            let axis: SplitLayout.Axis = (split["layoutOrientation"] as? String) == "vertical" ? .vertical : .horizontal
            switch links.count {
            case 0: return nil
            case 1: return .link(links[0])
            default: return .split(links: Array(links.prefix(SplitLayout.maximumPanes)), axis: axis)
            }
        }
        return nil
    }

    private func link(tab: [String: Any], customTitle: String?) -> ImportedLink? {
        guard let url = URL.importable(tab["savedURL"] as? String) else { return nil }
        return ImportedLink(title: customTitle ?? tab["savedTitle"] as? String ?? url.displayString, url: url)
    }
}
