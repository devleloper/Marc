import Foundation
import Testing
@testable import MarcWebKit

@MainActor
struct HostPreresolverTests {
    @Test(arguments: [
        ("https://www.Example.com/path?q=1", "www.example.com"),
        ("http://news.ycombinator.com", "news.ycombinator.com"),
    ])
    func `resolves the host of web URLs`(address: String, host: String) throws {
        #expect(try HostPreresolver.host(worthResolving: #require(URL(string: address))) == host)
    }

    @Test(arguments: [
        "file:///tmp/a.html",
        "about:blank",
        "marc://settings",
        "http://localhost:8080",
        "https://192.168.1.10",
        "https://[::1]/",
    ])
    func `skips addresses that gain nothing from a lookup`(address: String) throws {
        #expect(try HostPreresolver.host(worthResolving: #require(URL(string: address))) == nil)
    }

    @Test func `looks up each host at most once a minute`() throws {
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        let resolver = HostPreresolver(resolve: { _ in }, now: { clock })
        let url = try #require(URL(string: "https://swift.org/blog"))
        #expect(resolver.preresolve(url))
        #expect(!resolver.preresolve(URL(string: "https://swift.org/documentation")))
        clock = clock.addingTimeInterval(61)
        #expect(resolver.preresolve(url))
    }

    @Test func `does nothing when turned off`() throws {
        let resolver = HostPreresolver(resolve: { _ in })
        resolver.isEnabled = { false }
        #expect(try !resolver.preresolve(#require(URL(string: "https://webkit.org"))))
    }
}
