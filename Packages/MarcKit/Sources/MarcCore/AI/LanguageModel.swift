import Foundation

/// A single-turn request to a language model.
public struct LanguageModelRequest: Hashable, Sendable {
    /// How much reasoning a provider should spend; providers without the concept ignore it.
    public enum Effort: String, Hashable, Sendable {
        case low
        case medium
    }

    public var system: String
    public var prompt: String
    public var maxOutputTokens: Int
    public var effort: Effort

    public init(system: String, prompt: String, maxOutputTokens: Int, effort: Effort = .medium) {
        self.system = system
        self.prompt = prompt
        self.maxOutputTokens = maxOutputTokens
        self.effort = effort
    }
}

public enum LanguageModelError: Error, Equatable, Sendable, LocalizedError {
    case unavailable
    case missingAPIKey
    case refused(category: String?)
    case http(status: Int, message: String)
    case malformedResponse
    case outputLimitReached

    public var errorDescription: String? {
        switch self {
        case .unavailable: "The selected AI model is not available on this Mac."
        case .missingAPIKey: "Add a Claude API key in Settings → AI to use this feature."
        case .refused: "The model declined to answer this request."
        case let .http(status, message): "The AI service returned an error (\(status)): \(message)"
        case .malformedResponse: "The AI service sent a response Marc could not read."
        case .outputLimitReached: "The answer was cut off because it reached the length limit."
        }
    }
}

public protocol LanguageModelProvider: Sendable {
    var kind: AIProviderKind { get }
    /// Context budget in characters, used to size page excerpts.
    var maximumInputCharacters: Int { get }
    func isAvailable() async -> Bool
    /// Streams text deltas.
    func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<String, any Error>
}

public extension LanguageModelProvider {
    /// Collects a streamed response into one string.
    func complete(_ request: LanguageModelRequest) async throws -> String {
        var text = ""
        for try await delta in stream(request) {
            text += delta
        }
        return text
    }
}

/// Picks the provider for the user's AI preference.
public struct LanguageModelResolver: Sendable {
    private let claude: (any LanguageModelProvider)?
    private let onDevice: (any LanguageModelProvider)?

    public init(claude: (any LanguageModelProvider)?, onDevice: (any LanguageModelProvider)?) {
        self.claude = claude
        self.onDevice = onDevice
    }

    public func provider(for preference: AIProviderKind) async -> (any LanguageModelProvider)? {
        switch preference {
        case .off:
            return nil
        case .claude:
            return await available(claude)
        case .onDevice:
            return await available(onDevice)
        case .automatic:
            if let onDevice = await available(onDevice) { return onDevice }
            return await available(claude)
        }
    }

    private func available(_ provider: (any LanguageModelProvider)?) async -> (any LanguageModelProvider)? {
        guard let provider, await provider.isAvailable() else { return nil }
        return provider
    }
}

/// Claude models offered in Settings.
public enum ClaudeModel: String, CaseIterable, Sendable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    public var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5"
        case .sonnet: "Claude Sonnet 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }

    /// Server-side refusal fallbacks exist for Opus and Sonnet, not for Haiku.
    public var supportsServerFallback: Bool {
        self != .haiku
    }
}
