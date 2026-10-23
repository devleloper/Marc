import Foundation
import Testing
@testable import MarcCore

struct URLInputClassifierTests {
    let classifier = URLInputClassifier()

    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("www.apple.com/mac", "https://www.apple.com/mac"),
        ("https://github.com/apple/swift", "https://github.com/apple/swift"),
        ("http://example.org", "http://example.org"),
        ("localhost:3000", "http://localhost:3000"),
        ("localhost", "http://localhost"),
        ("127.0.0.1:8080/api", "http://127.0.0.1:8080/api"),
        ("192.168.1.1", "http://192.168.1.1"),
        ("myapp.test", "http://myapp.test"),
        ("printer.local", "http://printer.local"),
        ("devbox:8080", "http://devbox:8080"),
        ("en.wikipedia.org/wiki/Web_browser", "https://en.wikipedia.org/wiki/Web_browser"),
        ("example.com:8443/path?q=1#top", "https://example.com:8443/path?q=1#top"),
        ("about:blank", "about:blank"),
        ("mailto:someone@example.com", "mailto:someone@example.com"),
        ("example.com.", "https://example.com."),
        ("[::1]:8000", "http://[::1]:8000"),
    ])
    func `classifies URLs`(input: String, expected: String) throws {
        #expect(try classifier.classify(input) == .url(#require(URL(string: expected))))
    }

    @Test(arguments: [
        "swift concurrency",
        "how to bake bread",
        "3.14",
        "node.notatld",
        "e.g",
        "someone@example.com",
        "intranet",
        "note: buy milk",
        "999.999.999.999",
    ])
    func `classifies searches`(input: String) {
        #expect(classifier.classify(input) == .search(input))
    }

    @Test func `trims whitespace and joins lines`() throws {
        #expect(try classifier.classify("  example.com  ") == .url(#require(URL(string: "https://example.com"))))
        #expect(classifier.classify("swift\nui") == .search("swift ui"))
    }

    @Test func `empty input has no result`() {
        #expect(classifier.classify("   ") == nil)
        #expect(classifier.classify("") == nil)
    }

    @Test func `encodes spaces in explicit URLs`() throws {
        let result = classifier.classify("https://example.com/a b")
        #expect(try result == .url(#require(URL(string: "https://example.com/a%20b"))))
    }

    @Test func `top level domain list is bundled`() {
        #expect(TopLevelDomains.all.count > 1000)
        #expect(TopLevelDomains.all.contains("com"))
        #expect(TopLevelDomains.all.contains("dev"))
    }
}

struct NavigationSafetyPolicyTests {
    let policy = NavigationSafetyPolicy()

    @Test func `allows web schemes`() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(policy.decide(url, isMainFrame: true, initiator: .webContent) == .allow)
    }

    @Test func `blocks script UR ls even when typed`() throws {
        let url = try #require(URL(string: "javascript:alert(1)"))
        #expect(policy.decide(url, isMainFrame: true, initiator: .user) == .block(.scriptURL))
    }

    @Test func `blocks top level data UR ls from web content only`() throws {
        let url = try #require(URL(string: "data:text/html,<h1>hi</h1>"))
        #expect(policy.decide(url, isMainFrame: true, initiator: .webContent) == .block(.topLevelDataURL))
        #expect(policy.decide(url, isMainFrame: false, initiator: .webContent) == .allow)
        #expect(policy.decide(url, isMainFrame: true, initiator: .user) == .allow)
    }

    @Test func `file UR ls require user initiation`() {
        let url = URL(fileURLWithPath: "/tmp/page.html")
        #expect(policy.decide(url, isMainFrame: true, initiator: .user) == .allow)
        #expect(policy.decide(url, isMainFrame: true, initiator: .webContent) == .block(.fileURLFromWebContent))
    }

    @Test func `external schemes need confirmation`() throws {
        let url = try #require(URL(string: "mailto:a@example.com"))
        #expect(policy.decide(url, isMainFrame: true, initiator: .webContent) == .openExternally(url))
    }

    @Test func `only blank and srcdoc about pages load`() throws {
        #expect(try policy.decide(#require(URL(string: "about:blank")), isMainFrame: true, initiator: .user) == .allow)
        #expect(try policy
            .decide(#require(URL(string: "about:config")), isMainFrame: true, initiator: .user) == .block(.unsupportedAboutPage))
    }

    @Test func `internal pages only open from the browser`() throws {
        let url = try #require(URL(string: "marc://history"))
        #expect(policy.decide(url, isMainFrame: true, initiator: .user) == .allow)
        #expect(policy.decide(url, isMainFrame: true, initiator: .webContent) == .block(.internalPageFromWebContent))
    }
}
