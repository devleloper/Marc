import Foundation

/// A node of the sidebar tree. Items are stored flat; `container` and `parentID` place them in
/// the tree and `sortKey` orders siblings.
public struct SidebarItem: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<SidebarItem>

    public let id: ID
    public var container: SidebarContainer
    public var parentID: ID?
    public var sortKey: Double
    public var content: Content
    public let createdAt: Date
    public var lastActiveAt: Date

    public init(
        id: ID = ID(),
        container: SidebarContainer,
        parentID: ID? = nil,
        sortKey: Double,
        content: Content,
        createdAt: Date = .now,
        lastActiveAt: Date? = nil,
    ) {
        self.id = id
        self.container = container
        self.parentID = parentID
        self.sortKey = sortKey
        self.content = content
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt ?? createdAt
    }

    public enum Content: Hashable, Sendable, Codable {
        case tab(TabContent)
        case folder(FolderContent)
        case split(SplitContent)
        case note(Note.ID)
    }

    public enum Kind: String, Hashable, Sendable, Codable {
        case tab
        case folder
        case split
        case note
    }

    public var kind: Kind {
        switch content {
        case .tab: .tab
        case .folder: .folder
        case .split: .split
        case .note: .note
        }
    }

    public var tab: TabContent? {
        get {
            if case let .tab(tab) = content {
                tab
            } else {
                nil
            }
        }
        set {
            if let newValue { content = .tab(newValue) }
        }
    }

    public var folder: FolderContent? {
        if case let .folder(folder) = content {
            folder
        } else {
            nil
        }
    }

    public var split: SplitContent? {
        if case let .split(split) = content {
            split
        } else {
            nil
        }
    }

    /// Tabs and notes can be shown in the content area; folders and splits are containers.
    public var isLeaf: Bool {
        kind == .tab || kind == .note
    }
}

public enum SidebarContainer: Hashable, Sendable, Codable {
    case favorites(Profile.ID)
    case pinned(Space.ID)
    case today(Space.ID)

    public var spaceID: Space.ID? {
        switch self {
        case .favorites: nil
        case let .pinned(id), let .today(id): id
        }
    }

    public var profileID: Profile.ID? {
        if case let .favorites(id) = self {
            id
        } else {
            nil
        }
    }

    public var section: Section {
        switch self {
        case .favorites: .favorites
        case .pinned: .pinned
        case .today: .today
        }
    }

    public enum Section: String, Hashable, Sendable, Codable {
        case favorites
        case pinned
        case today
    }

    /// Item kinds allowed at the root of the container.
    public var allowedRootKinds: Set<SidebarItem.Kind> {
        switch self {
        case .favorites: [.tab]
        case .pinned: [.tab, .folder, .split, .note]
        case .today: [.tab, .split, .note]
        }
    }
}

public struct TabContent: Hashable, Sendable, Codable {
    public var url: URL?
    public var title: String
    /// A user-assigned name that replaces the page title in the sidebar.
    public var customTitle: String?
    public var faviconURL: URL?
    /// The URL a pinned or favorite tab returns to when reset.
    public var homeURL: URL?

    public init(
        url: URL?,
        title: String = "",
        customTitle: String? = nil,
        faviconURL: URL? = nil,
        homeURL: URL? = nil,
    ) {
        self.url = url
        self.title = title
        self.customTitle = customTitle
        self.faviconURL = faviconURL
        self.homeURL = homeURL
    }

    public var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if !title.isEmpty { return title }
        return url?.displayHost ?? ""
    }

    /// True when a pinned tab has navigated away from its home host.
    public var hasLeftHome: Bool {
        guard let homeURL, let url else { return false }
        return homeURL.host(percentEncoded: false) != url.host(percentEncoded: false) || homeURL.path() != url.path()
    }
}

public struct FolderContent: Hashable, Sendable, Codable {
    public var name: String
    public var isExpanded: Bool

    public init(name: String, isExpanded: Bool = true) {
        self.name = name
        self.isExpanded = isExpanded
    }
}

public struct SplitContent: Hashable, Sendable, Codable {
    public var layout: SplitLayout

    public init(layout: SplitLayout) {
        self.layout = layout
    }
}

/// Pasteboard types Marc uses for its own drags.
public enum MarcPasteboardType {
    /// A sidebar item being dragged; the data is the item's UUID string. Declared in the app's
    /// Info.plist. Web views don't accept it, so it never ends up in a page.
    public static let sidebarItem = "dev.devleloper.marc.sidebar-item"
}
