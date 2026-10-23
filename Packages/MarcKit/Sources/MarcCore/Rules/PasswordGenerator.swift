import Foundation

/// Generates strong, readable passwords in the `xxxxxx-xxxxxx-xxxxxx` style: 18 random
/// characters from an unambiguous alphabet with at least one digit and one uppercase letter.
public struct PasswordGenerator: Sendable {
    static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    static let digits = Array("23456789")

    public init() {}

    public func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    public func generate(using generator: inout some RandomNumberGenerator) -> String {
        var characters = (0 ..< 18).map { _ in Self.lowercase.randomElement(using: &generator)! }
        var positions = Array(0 ..< 18).shuffled(using: &generator)
        characters[positions.removeLast()] = Self.digits.randomElement(using: &generator)!
        characters[positions.removeLast()] = Self.uppercase.randomElement(using: &generator)!
        return stride(from: 0, to: 18, by: 6)
            .map { String(characters[$0 ..< $0 + 6]) }
            .joined(separator: "-")
    }
}
