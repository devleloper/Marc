import Foundation

/// A named set of pinned and today tabs with its own theme, bound to one profile.
public struct Space: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<Space>

    public let id: ID
    public var profileID: Profile.ID
    public var name: String
    public var icon: SpaceIcon
    public var theme: Theme
    public var sortKey: Double

    public init(
        id: ID = ID(),
        profileID: Profile.ID,
        name: String,
        icon: SpaceIcon = .symbol("circle.fill"),
        theme: Theme = .default,
        sortKey: Double = 0,
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.icon = icon
        self.theme = theme
        self.sortKey = sortKey
    }
}

public enum SpaceIcon: Hashable, Sendable, Codable {
    case symbol(String)
    case emoji(String)

    /// Symbols offered by the icon picker. All are SF Symbols shipped with macOS 15.
    public static let suggestedSymbols: [String] = [
        "circle.fill", "star.fill", "heart.fill", "bolt.fill", "flame.fill", "leaf.fill",
        "moon.fill", "sun.max.fill", "cloud.fill", "sparkles", "briefcase.fill", "house.fill",
        "book.fill", "graduationcap.fill", "chevron.left.forwardslash.chevron.right", "terminal.fill",
        "paintbrush.pointed.fill", "music.note", "gamecontroller.fill", "cart.fill", "airplane",
        "camera.fill", "film.fill", "globe", "lightbulb.fill", "square.grid.2x2.fill", "person.2.fill",
        "dumbbell.fill", "cup.and.saucer.fill", "pawprint.fill",
    ]
}
