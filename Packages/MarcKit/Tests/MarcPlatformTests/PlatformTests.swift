import Foundation
import MarcCore
import Testing
@testable import MarcPlatform

@Suite(.serialized)
struct KeychainTests {
    @Test func `secret store saves replaces and deletes`() throws {
        let store = KeychainSecretStore(service: "dev.devleloper.Marc.tests.\(UUID().uuidString)")
        #expect(try store.secret(for: "key") == nil)
        try store.setSecret("one", for: "key")
        try store.setSecret("two", for: "key")
        #expect(try store.secret(for: "key") == "two")
        try store.setSecret(nil, for: "key")
        #expect(try store.secret(for: "key") == nil)
    }

    @Test func `credential store keeps metadata separate from passwords`() async throws {
        let store = KeychainCredentialStore(profileID: Profile.ID(), servicePrefix: "dev.devleloper.Marc.tests.credentials")
        defer { try? store.deleteAll() }
        let credential = Credential(origin: "https://example.com", username: "ada")
        try await store.save(credential, password: "s3cret-pass")
        try await store.save(Credential(origin: "https://other.com", username: "bob"), password: "x")

        #expect(try await store.credentials(for: "https://example.com") == [credential])
        #expect(try await store.allCredentials().count == 2)
        #expect(try await store.password(for: credential) == "s3cret-pass")

        let usedAt = Date(timeIntervalSince1970: 1000)
        try await store.markUsed(credential, at: usedAt)
        #expect(try await store.credentials(for: "https://example.com").first?.lastUsedAt == usedAt)

        try await store.delete(credential)
        #expect(try await store.credentials(for: "https://example.com").isEmpty)
    }
}

struct SettingsStoreTests {
    @Test func `round trips settings and falls back to defaults`() throws {
        let suite = "dev.devleloper.Marc.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(store.load() == BrowserSettings())

        var settings = BrowserSettings()
        settings.searchEngineID = "duckduckgo"
        store.save(settings)
        #expect(store.load().searchEngine == .duckDuckGo)

        defaults.set(Data("not json".utf8), forKey: "BrowserSettings")
        #expect(store.load() == BrowserSettings())
    }
}

struct SearchSuggestionTests {
    @Test func `parses open search JSON`() {
        #expect(SearchSuggestionClient.parse(Data(#"["swift",["swift ui","swift concurrency",""]]"#.utf8)) == [
            "swift ui",
            "swift concurrency",
        ])
        #expect(SearchSuggestionClient.parse(Data("garbage".utf8)).isEmpty)
        #expect(SearchSuggestionClient.parse(Data(#"{"a":1}"#.utf8)).isEmpty)
    }
}

struct ClaudeStreamEventTests {
    @Test func `extracts text deltas and ignores other events`() throws {
        #expect(
            try ClaudeStreamEvent(dataLine: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#) ==
                .text("Hi"),
        )
        #expect(
            try ClaudeStreamEvent(
                dataLine: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#,
            ) ==
                .ignored,
        )
        #expect(try ClaudeStreamEvent(dataLine: #"data: {"type":"ping"}"#) == .ignored)
        #expect(try ClaudeStreamEvent(dataLine: #"data: {"type":"content_block_start","index":0,"content_block":{"type":"fallback"}}"#) ==
            .ignored)
    }

    @Test func `surfaces refusals limits and errors`() {
        #expect(throws: LanguageModelError.refused(category: "cyber")) {
            try ClaudeStreamEvent(
                dataLine: #"data: {"type":"message_delta","delta":{"stop_reason":"refusal","#
                    + #""stop_details":{"type":"refusal","category":"cyber"}}}"#,
            )
        }
        #expect(throws: LanguageModelError.outputLimitReached) {
            try ClaudeStreamEvent(dataLine: #"data: {"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#)
        }
        #expect(throws: LanguageModelError.http(status: 529, message: "Overloaded")) {
            try ClaudeStreamEvent(dataLine: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        }
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: Data
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Response)?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            captured.httpBody = data
        }
        Self.lastRequest = captured
        let response = Self.handler?(captured) ?? Response(status: 500, body: Data())
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"],
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ClaudeProviderTests {
    func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    @Test func `builds a streaming request with fallbacks for opus`() throws {
        let provider = ClaudeLanguageModelProvider(apiKey: { "test-key" }, model: { ClaudeModel.opus.rawValue })
        let request = try provider.makeURLRequest(for: LanguageModelRequest(
            system: "sys",
            prompt: "hello",
            maxOutputTokens: 100,
            effort: .low,
        )).get()
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let httpBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5-5")
        #expect(body["stream"] as? Bool == true)
        #expect(body["fallbacks"] as? String == "default")
        #expect((body["output_config"] as? [String: Any])?["effort"] as? String == "low")
        #expect(body["temperature"] == nil)
    }

    @Test func `haiku requests omit server fallbacks`() throws {
        let provider = ClaudeLanguageModelProvider(apiKey: { "k" }, model: { ClaudeModel.haiku.rawValue })
        let request = try provider.makeURLRequest(for: LanguageModelRequest(system: "s", prompt: "p", maxOutputTokens: 10)).get()
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == nil)
        let httpBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(body["fallbacks"] == nil)
    }

    @Test func `requires an API key`() async {
        let provider = ClaudeLanguageModelProvider(session: session(), apiKey: { nil }, model: { ClaudeModel.opus.rawValue })
        #expect(await provider.isAvailable() == false)
        await #expect(throws: LanguageModelError.missingAPIKey) {
            try await provider.complete(LanguageModelRequest(system: "s", prompt: "p", maxOutputTokens: 10))
        }
    }

    @Test func `streams text from server sent events`() async throws {
        StubURLProtocol.handler = { _ in
            let events = """
            event: message_start
            data: {"type":"message_start","message":{"id":"msg_1","type":"message"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

            event: content_block_delta
            data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":", world"}}

            event: message_delta
            data: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}

            event: message_stop
            data: {"type":"message_stop"}

            """
            return .init(status: 200, body: Data(events.utf8))
        }
        let provider = ClaudeLanguageModelProvider(session: session(), apiKey: { "k" }, model: { ClaudeModel.sonnet.rawValue })
        let text = try await provider.complete(LanguageModelRequest(system: "s", prompt: "p", maxOutputTokens: 10))
        #expect(text == "Hello, world")
    }

    @Test func `maps HTTP errors`() async {
        StubURLProtocol.handler = { _ in
            .init(status: 401, body: Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8))
        }
        let provider = ClaudeLanguageModelProvider(session: session(), apiKey: { "bad" }, model: { ClaudeModel.opus.rawValue })
        await #expect(throws: LanguageModelError.http(status: 401, message: "invalid x-api-key")) {
            try await provider.complete(LanguageModelRequest(system: "s", prompt: "p", maxOutputTokens: 10))
        }
    }
}

struct LanguageModelResolverTests {
    struct FakeProvider: LanguageModelProvider {
        let kind: AIProviderKind
        let available: Bool
        let maximumInputCharacters = 100
        func isAvailable() async -> Bool { available }
        func stream(_ request: LanguageModelRequest) -> AsyncThrowingStream<String, any Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    @Test func `automatic prefers on device then claude`() async {
        let claude = FakeProvider(kind: .claude, available: true)
        let resolverWithBoth = LanguageModelResolver(claude: claude, onDevice: FakeProvider(kind: .onDevice, available: true))
        #expect(await resolverWithBoth.provider(for: .automatic)?.kind == .onDevice)

        let resolverWithoutOnDevice = LanguageModelResolver(claude: claude, onDevice: FakeProvider(kind: .onDevice, available: false))
        #expect(await resolverWithoutOnDevice.provider(for: .automatic)?.kind == .claude)
        #expect(await resolverWithoutOnDevice.provider(for: .onDevice) == nil)
        #expect(await resolverWithoutOnDevice.provider(for: .off) == nil)
    }
}
