import Foundation

/// Persisted state of one browser window, used for session restore.
public struct WindowState: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<WindowState>

    public enum Kind: String, Hashable, Sendable, Codable {
        case standard
        case little
    }

    public static let defaultSidebarWidth = 250.0
    public static let sidebarWidthRange = 200.0 ... 400.0

    public let id: ID
    public var kind: Kind
    public var spaceID: Space.ID?
    public var selection: [Space.ID: SidebarItem.ID]
    public var isSidebarVisible: Bool
    public var sidebarWidth: Double
    public var frame: Frame?
    public var sortKey: Double

    public init(
        id: ID = ID(),
        kind: Kind = .standard,
        spaceID: Space.ID?,
        selection: [Space.ID: SidebarItem.ID] = [:],
        isSidebarVisible: Bool = true,
        sidebarWidth: Double = WindowState.defaultSidebarWidth,
        frame: Frame? = nil,
        sortKey: Double = 0,
    ) {
        self.id = id
        self.kind = kind
        self.spaceID = spaceID
        self.selection = selection
        self.isSidebarVisible = isSidebarVisible
        self.sidebarWidth = sidebarWidth
        self.frame = frame
        self.sortKey = sortKey
    }

    public var selectedItemID: SidebarItem.ID? {
        spaceID.flatMap { selection[$0] }
    }

    public struct Frame: Hashable, Sendable, Codable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }
}
