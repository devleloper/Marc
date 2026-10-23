import Foundation
import MarcCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Claude through the Messages API with streaming. Swift has no official Anthropic SDK, so the
/// request is sent over HTTP.
public struct ClaudeLanguageModelProvider: LanguageModelProvider {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2026-10-21"
    static let serverFallbackBeta = "server-side-fallback-2026-07-01"

    public let kind = AIProviderKind.claude
    /// Roughly 100k tokens: well inside the context window while keeping requests affordable.
    public let maximumInputCharacters = 400_000

    private let session: URLSession
    private let apiKey: @Sendable () -> String?
    private let model: @Sendable () -> String

    public init(
        session: URLSession = .shared,
        apiKey: @escaping @Sendable () -> String?,
        model: @escaping @Sendable () -> String,
    ) {
        self.session = session
        self.apiKey = apiKey
        self.model = model
    }

    public func isAvailable() async -> Bool {
        apiKey()?.isEmpty == false
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<String, any Error> {
        let session = session
        let urlRequest = makeURLRequest(for: request)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try urlRequest.get()
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse else { throw LanguageModelError.malformedResponse }
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes where body.count < 65536 {
                            body.append(byte)
                        }
                        throw LanguageModelError.http(status: http.statusCode, message: ClaudeStreamEvent.errorMessage(in: body))
                    }
                    // Every event carries its type inside the JSON payload, so `data:` lines are
                    // enough; `AsyncLineSequence` drops the blank separator lines anyway.
                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        switch try ClaudeStreamEvent(dataLine: line) {
                        case let .text(delta): continuation.yield(delta)
                        case .ignored: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeURLRequest(for request: LanguageModelRequest) -> Result<URLRequest, any Error> {
        guard let key = apiKey(), !key.isEmpty else { return .failure(LanguageModelError.missingAPIKey) }
        let modelID = model()
        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": request.maxOutputTokens,
            "stream": true,
            "system": request.system,
            "messages": [["role": "user", "content": request.prompt]],
            "output_config": ["effort": request.effort.rawValue],
        ]
        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if ClaudeModel(rawValue: modelID)?.supportsServerFallback ?? false {
            // A classifier decline is retried server-side on the recommended model.
            body["fallbacks"] = "default"
            urlRequest.setValue(Self.serverFallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        return Result { urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body) }.map { urlRequest }
    }
}

/// One server-sent event of a streamed Messages API response.
enum ClaudeStreamEvent: Equatable {
    case text(String)
    case ignored

    init(dataLine: String) throws {
        let payload = dataLine.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard let object = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let type = object["type"] as? String
        else { throw LanguageModelError.malformedResponse }

        switch type {
        case "content_block_delta":
            let delta = object["delta"] as? [String: Any]
            if delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String {
                self = .text(text)
            } else {
                self = .ignored
            }
        case "message_delta":
            let delta = object["delta"] as? [String: Any]
            switch delta?["stop_reason"] as? String {
            case "refusal":
                let details = (delta?["stop_details"] ?? object["stop_details"]) as? [String: Any]
                throw LanguageModelError.refused(category: details?["category"] as? String)
            case "max_tokens":
                throw LanguageModelError.outputLimitReached
            default:
                self = .ignored
            }
        case "error":
            let error = object["error"] as? [String: Any]
            let status = switch error?["type"] as? String {
            case "overloaded_error": 529
            case "rate_limit_error": 429
            case "api_error": 500
            default: 0
            }
            throw LanguageModelError.http(status: status, message: error?["message"] as? String ?? "Unknown error")
        default:
            self = .ignored
        }
    }

    static func errorMessage(in body: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return (object?["error"] as? [String: Any])?["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: 0)
    }
}

/// Apple's on-device foundation model (macOS 26 with Apple Intelligence enabled).
public struct OnDeviceLanguageModelProvider: LanguageModelProvider {
    public let kind = AIProviderKind.onDevice
    /// The on-device context holds about 4,000 tokens shared by instructions, prompt and answer.
    public let maximumInputCharacters = 7000

    public init() {}

    public func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            return true
        }
        #endif
        return false
    }

    public func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<String, any Error> {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return Self.streamOnDevice(request)
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: LanguageModelError.unavailable) }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func streamOnDevice(_ request: LanguageModelRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: request.system)
                    let options = GenerationOptions(maximumResponseTokens: request.maxOutputTokens)
                    var emitted = ""
                    // Snapshots carry the cumulative text; forward only what is new.
                    for try await snapshot in session.streamResponse(to: request.prompt, options: options) {
                        let content = snapshot.content
                        if content.hasPrefix(emitted) {
                            continuation.yield(String(content.dropFirst(emitted.count)))
                        }
                        emitted = content
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    #endif
}
