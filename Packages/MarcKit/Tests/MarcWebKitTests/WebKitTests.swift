import Foundation
import MarcCore
import Testing
import WebKit
@testable import MarcWebKit

struct CRXArchiveTests {
    func crx3(header: Data, zip: Data) -> Data {
        var data = Data("Cr24".utf8)
        withUnsafeBytes(of: UInt32(3).littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { data.append(contentsOf: $0) }
        return data + header + zip
    }

    @Test func `strips the CRX3 header`() throws {
        let zip = Data("PK\u{03}\u{04}rest-of-archive".utf8)
        #expect(try CRXArchive.zipData(from: crx3(header: Data(repeating: 7, count: 40), zip: zip)) == zip)
    }

    @Test func `strips the CRX2 header`() throws {
        var data = Data("Cr24".utf8)
        for value in [UInt32(2), 4, 3] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let zip = Data("PK\u{03}\u{04}archive".utf8)
        data += Data([1, 2, 3, 4]) + Data([5, 6, 7]) + zip
        #expect(try CRXArchive.zipData(from: data) == zip)
    }

    @Test func `rejects other files`() {
        #expect(throws: WebExtensionHost.InstallError.self) { try CRXArchive.zipData(from: Data("not a crx file at all".utf8)) }
        #expect(throws: WebExtensionHost.InstallError.self) { try CRXArchive.zipData(from: crx3(header: Data(), zip: Data("NOTZIP".utf8))) }
    }
}

struct DownloadNameTests {
    @Test func `sanitizes suggested names`() {
        #expect(DownloadCoordinator.sanitize("../../etc/passwd") == "passwd")
        #expect(DownloadCoordinator.sanitize("report:final.pdf") == "reportfinal.pdf")
        #expect(DownloadCoordinator.sanitize("...") == "Download")
        #expect(DownloadCoordinator.sanitize("  .hidden ") == "hidden")
    }

    @Test func `picks unique destinations`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory.appending(path: "file.zip"))
        try Data().write(to: directory.appending(path: "file (1).zip"))
        #expect(DownloadCoordinator.uniqueURL(in: directory, fileName: "file.zip").lastPathComponent == "file (2).zip")
        #expect(DownloadCoordinator.uniqueURL(in: directory, fileName: "new.txt").lastPathComponent == "new.txt")
    }
}

struct PageIconTests {
    func icon(_ href: String, sizes: String = "", rel: String = "icon", type: String = "") -> PageIcon? {
        PageIcon(["href": href, "sizes": sizes, "rel": rel, "type": type])
    }

    @Test func `prefers icons around 32 to 64 pixels`() throws {
        let icons = try [
            #require(icon("https://a.com/16.png", sizes: "16x16")),
            #require(icon("https://a.com/32.png", sizes: "32x32")),
            #require(icon("https://a.com/512.png", sizes: "512x512")),
            #require(icon("https://a.com/touch.png", rel: "apple-touch-icon")),
        ]
        #expect(PageIcon.best(in: icons)?.url.lastPathComponent == "32.png")
    }

    @Test func `ignores non web icon urls`() {
        #expect(icon("javascript:alert(1)") == nil)
        #expect(icon("file:///etc/hosts") == nil)
        #expect(icon("data:image/png;base64,AAAA") != nil)
    }
}

struct BoostScriptTests {
    @Test func `string literals cannot break out of the script`() {
        let literal = BoostScripts.jsonStringLiteral("a\"b\n</script><script>alert(1)</script>")
        #expect(literal.hasPrefix("\""))
        #expect(literal.hasSuffix("\""))
        #expect(!literal.contains("\n"))
        #expect(literal.contains("\\\""))
    }

    @Test func `builds style and script user scripts for a boost`() {
        let boost = Boost(name: "B", hostPattern: "example.com", style: .init(hueRotation: 90), customJavaScript: "console.log(1)")
        let scripts = BoostScripts.userScripts(for: [boost])
        #expect(scripts.count == 2)
        #expect(scripts[0].injectionTime == .atDocumentStart)
        #expect(scripts[1].injectionTime == .atDocumentEnd)
        let mainFrameOnly = scripts.allSatisfy(\.isForMainFrameOnly)
        #expect(mainFrameOnly)
    }
}

@MainActor
struct WebTabIntegrationTests {
    func makeEngine() -> WebEngine {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MarcWebKitTests-\(UUID().uuidString)")
        let blocker = ContentBlocker(directory: directory.appending(path: "Blocker")) { _, _ in .notModified }
        return WebEngine(contentBlocker: blocker, favicons: FaviconLoader(directory: directory.appending(path: "Favicons")))
    }

    func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test func `loads a page and reports its title and text`() async throws {
        let engine = makeEngine()
        let registry = TabRuntimeRegistry(engine: engine)
        let html = "<html><head><title>Marc Test</title></head><body><main>Hello from the page</main></body></html>"
        let encoded = try #require(html.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let url = try #require(URL(string: "data:text/html;charset=utf-8," + encoded))
        let tab = registry.tab(id: SidebarItem.ID(), url: nil, title: "", context: ProfileWebContext())
        tab.load(url, initiator: .user)

        #expect(await waitUntil { tab.title == "Marc Test" && !tab.isLoading })
        let content = await tab.pageContent()
        #expect(content?.text.contains("Hello from the page") == true)

        await tab.find("hello")
        #expect(tab.find.matchCount == 1)

        tab.unload()
        #expect(!tab.hasWebView)
        registry.close(tab.id)
        #expect(registry.tab(for: tab.id) == nil)
    }

    @Test func `blocks script urls before they reach WebKit`() async throws {
        let engine = makeEngine()
        let registry = TabRuntimeRegistry(engine: engine)
        let tab = registry.tab(id: SidebarItem.ID(), url: nil, title: "", context: ProfileWebContext())
        try tab.load(#require(URL(string: "about:blank")), initiator: .user)
        #expect(await waitUntil { !tab.isLoading && tab.hasWebView })
        try tab.load(#require(URL(string: "javascript:alert(1)")), initiator: .user)
        #expect(await waitUntil { tab.failure != nil })
        #expect(try tab.failure == .blocked(url: #require(URL(string: "javascript:alert(1)")), reason: .scriptURL))
    }
}
