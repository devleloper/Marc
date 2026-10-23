import Foundation
import Testing
@testable import MarcCore

struct BoostTests {
    @Test func `host patterns match exactly or by suffix`() {
        let exact = Boost(name: "HN", hostPattern: "news.ycombinator.com")
        #expect(exact.matches(host: "news.ycombinator.com"))
        #expect(!exact.matches(host: "ycombinator.com"))

        let wildcard = Boost(name: "Example", hostPattern: "*.example.com")
        #expect(wildcard.matches(host: "example.com"))
        #expect(wildcard.matches(host: "docs.example.com"))
        #expect(!wildcard.matches(host: "badexample.com"))

        #expect(Boost(name: "W", hostPattern: "www.apple.com").matches(host: "apple.com"))
    }

    @Test func `style sheet combines filters fonts and zaps`() {
        let boost = Boost(
            name: "Test",
            hostPattern: "example.com",
            style: Boost.Style(hueRotation: 90, saturation: 1.5, fontFamily: "Avenir Next"),
            zappedSelectors: ["#ads", ".banner"],
            customCSS: "body { margin: 0; }",
        )
        let css = boost.styleSheet
        #expect(css.contains("hue-rotate(90deg)"))
        #expect(css.contains("saturate(1.50)"))
        #expect(css.contains("\"Avenir Next\""))
        #expect(css.contains("#ads,\n.banner { display: none !important; }"))
        #expect(css.hasSuffix("body { margin: 0; }"))
    }

    @Test func `unsafe selectors and fonts are dropped`() {
        let boost = Boost(
            name: "Test",
            hostPattern: "example.com",
            style: Boost.Style(fontFamily: "x; } body { display:none"),
            zappedSelectors: ["div } body { display: none", "  "],
        )
        #expect(boost.styleSheet.isEmpty)
    }

    @Test func `identity style produces no filter`() {
        #expect(Boost.Style().isIdentity)
        #expect(Boost.Style().cssFilters.isEmpty)
    }
}

struct PasswordGeneratorTests {
    @Test func `produces three groups with required character classes`() {
        for _ in 0 ..< 50 {
            let password = PasswordGenerator().generate()
            let groups = password.split(separator: "-")
            #expect(groups.count == 3)
            #expect(groups.allSatisfy { $0.count == 6 })
            #expect(password.contains { $0.isNumber })
            #expect(password.contains { $0.isUppercase })
        }
    }

    @Test func `passwords are not repeated`() {
        let passwords = Set((0 ..< 100).map { _ in PasswordGenerator().generate() })
        #expect(passwords.count == 100)
    }
}

struct SelectionPolicyTests {
    let a = SidebarItem.ID(), b = SidebarItem.ID(), c = SidebarItem.ID()

    @Test func `selects the next item then the previous`() {
        #expect(SelectionPolicy.replacement(forRemoved: b, orderBeforeRemoval: [a, b, c], remaining: [a, c]) == c)
        #expect(SelectionPolicy.replacement(forRemoved: c, orderBeforeRemoval: [a, b, c], remaining: [a, b]) == b)
        #expect(SelectionPolicy.replacement(forRemoved: a, orderBeforeRemoval: [a], remaining: []) == nil)
    }

    @Test func `neighbor wraps around`() {
        #expect(SelectionPolicy.neighbor(of: c, offset: 1, in: [a, b, c]) == a)
        #expect(SelectionPolicy.neighbor(of: a, offset: -1, in: [a, b, c]) == c)
        #expect(SelectionPolicy.neighbor(of: nil, offset: 1, in: [a, b, c]) == a)
    }
}

struct SearchEngineTests {
    @Test func `encodes queries safely`() {
        let url = SearchEngine.google.searchURL(for: "a&b=c #1 ü")
        #expect(url?.absoluteString == "https://www.google.com/search?q=a%26b%3Dc%20%231%20%C3%BC")
    }

    @Test func `empty queries produce no URL`() {
        #expect(SearchEngine.google.searchURL(for: "   ") == nil)
    }

    @Test func `unknown identifiers fall back to google`() {
        #expect(SearchEngine.builtIn(id: "nope") == .google)
        #expect(SearchEngine.builtIn(id: "kagi") == .kagi)
    }
}

struct ThemeTests {
    @Test func `parses and formats hex colors`() {
        #expect(RGBColor(hex: "#FF8000")?.hex == "#FF8000")
        #expect(RGBColor(hex: "zzzzzz") == nil)
        #expect(RGBColor(hex: "#FFF") == nil)
    }

    @Test func `luminance orders black and white`() {
        #expect(RGBColor.black.relativeLuminance == 0)
        #expect(abs(RGBColor.white.relativeLuminance - 1) < 0.0001)
    }

    @Test func `themes without translucency decode as opaque and clamp the value`() throws {
        let decoded = try JSONDecoder().decode(Theme.self, from: Data(#"{"colors":[{"red":0.5,"green":0.4,"blue":0.9}],"grain":0.2}"#.utf8))
        #expect(decoded.translucency == 0)
        #expect(Theme(colors: [.white], translucency: 1.7).translucency == 1)
        var theme = Theme.default
        theme.translucency = 0.6
        #expect(try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(theme)) == theme)
    }

    @Test func `themes keep at most three colors and decode empty colors safely`() throws {
        let theme = Theme(colors: Array(repeating: .white, count: 5))
        #expect(theme.colors.count == 3)
        let json = Data(#"{"colors":[],"appearance":"dark","grain":2}"#.utf8)
        let decoded = try JSONDecoder().decode(Theme.self, from: json)
        #expect(!decoded.colors.isEmpty)
        #expect(decoded.grain == 1)
    }
}

struct CredentialTests {
    @Test(arguments: [
        ("https://example.com/login", "https://example.com"),
        ("https://Example.com:8443/", "https://example.com:8443"),
        ("https://example.com:443/", "https://example.com"),
        ("http://localhost:3000/", "http://localhost:3000"),
    ])
    func `normalizes origins`(url: String, origin: String) throws {
        #expect(try Credential.origin(for: #require(URL(string: url))) == origin)
    }

    @Test func `refuses insecure origins`() throws {
        #expect(try Credential.origin(for: #require(URL(string: "http://example.com"))) == nil)
        #expect(try Credential.origin(for: #require(URL(string: "ftp://example.com"))) == nil)
    }
}

struct BrowserSettingsTests {
    @Test func `decodes missing keys with defaults`() throws {
        let settings = try JSONDecoder().decode(BrowserSettings.self, from: Data(#"{"searchEngineID":"kagi"}"#.utf8))
        #expect(settings.searchEngine == .kagi)
        #expect(settings.archiveInterval == .twelveHours)
        #expect(settings.showsSearchSuggestions)
        #expect(settings.appIcon == .marc)
        #expect(settings.preloadsLinkAddresses)
    }

    @Test func `unknown app icon falls back to Marc`() throws {
        let settings = try JSONDecoder().decode(BrowserSettings.self, from: Data(#"{"appIcon":"neon"}"#.utf8))
        #expect(settings.appIcon == .marc)
    }

    @Test(arguments: [
        (AppIconStyle.marc, false, String?.none), (.marc, true, nil),
        (.aurora, false, "AppIconAurora"), (.aurora, true, "AppIconAurora"),
        (.matchAppearance, false, nil), (.matchAppearance, true, "AppIconAurora"),
    ])
    func `app icon follows the style and appearance`(style: AppIconStyle, isDark: Bool, expected: String?) {
        #expect(style.imageName(isDarkAppearance: isDark) == expected)
    }

    @Test func `round trips`() throws {
        var settings = BrowserSettings()
        settings.archiveInterval = .week
        settings.aiProvider = .claude
        settings.appIcon = .matchAppearance
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(BrowserSettings.self, from: data) == settings)
    }

    @Test func `zoom steps through levels`() {
        #expect(SiteSettings.nextZoom(after: 1, zoomingIn: true) == 1.1)
        #expect(SiteSettings.nextZoom(after: 1, zoomingIn: false) == 0.9)
        #expect(SiteSettings.nextZoom(after: 3, zoomingIn: true) == 3)
    }
}

struct URLDisplayTests {
    @Test func `display string drops scheme and WWW`() throws {
        #expect(try #require(URL(string: "https://www.apple.com/")).displayString == "apple.com")
        #expect(try #require(URL(string: "https://example.com:8080/a?b=1")).displayString == "example.com:8080/a?b=1")
    }

    @Test func `markdown link escapes brackets`() throws {
        let url = try #require(URL(string: "https://example.com"))
        #expect(url.markdownLink(title: "A [b]") == "[A \\[b\\]](https://example.com)")
    }
}
