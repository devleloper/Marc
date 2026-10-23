import Foundation

/// A per-site customization: recolouring, font replacement, hidden ("zapped") elements and
/// user-authored CSS or JavaScript.
public struct Boost: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = Identifier<Boost>

    public let id: ID
    public var name: String
    /// A host such as `news.ycombinator.com`, or `*.example.com` to include subdomains.
    public var hostPattern: String
    public var isEnabled: Bool
    public var style: Style
    public var zappedSelectors: [String]
    public var customCSS: String
    public var customJavaScript: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ID = ID(),
        name: String,
        hostPattern: String,
        isEnabled: Bool = true,
        style: Style = Style(),
        zappedSelectors: [String] = [],
        customCSS: String = "",
        customJavaScript: String = "",
        createdAt: Date = .now,
        updatedAt: Date? = nil,
    ) {
        self.id = id
        self.name = name
        self.hostPattern = hostPattern
        self.isEnabled = isEnabled
        self.style = style
        self.zappedSelectors = zappedSelectors
        self.customCSS = customCSS
        self.customJavaScript = customJavaScript
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public struct Style: Hashable, Sendable, Codable {
        /// Hue rotation in degrees, `nil` leaves colors untouched.
        public var hueRotation: Double?
        /// Saturation multiplier, 1 is unchanged.
        public var saturation: Double
        /// Brightness multiplier, 1 is unchanged.
        public var brightness: Double
        public var invertsColors: Bool
        public var fontFamily: String?
        /// Font size multiplier, 1 is unchanged.
        public var fontScale: Double

        public init(
            hueRotation: Double? = nil,
            saturation: Double = 1,
            brightness: Double = 1,
            invertsColors: Bool = false,
            fontFamily: String? = nil,
            fontScale: Double = 1,
        ) {
            self.hueRotation = hueRotation
            self.saturation = saturation
            self.brightness = brightness
            self.invertsColors = invertsColors
            self.fontFamily = fontFamily
            self.fontScale = fontScale
        }

        public var isIdentity: Bool {
            self == Style()
        }
    }
}
