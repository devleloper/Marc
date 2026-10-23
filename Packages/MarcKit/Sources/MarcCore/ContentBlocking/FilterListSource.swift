import Foundation

/// A filter list the content blocker can subscribe to. Lists are downloaded at runtime by the
/// user's browser; their content is not distributed with Marc.
public struct FilterListSource: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let url: URL
    public let isEnabledByDefault: Bool

    public init(id: String, name: String, url: URL, isEnabledByDefault: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.isEnabledByDefault = isEnabledByDefault
    }

    public static let easyList = FilterListSource(
        id: "easylist",
        name: "EasyList (ads)",
        url: URL(string: "https://easylist.to/easylist/easylist.txt")!,
        isEnabledByDefault: true,
    )

    public static let easyPrivacy = FilterListSource(
        id: "easyprivacy",
        name: "EasyPrivacy (trackers)",
        url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
        isEnabledByDefault: true,
    )

    public static let fanboyAnnoyance = FilterListSource(
        id: "fanboy-annoyance",
        name: "Fanboy's Annoyance (cookie banners, pop-ups)",
        url: URL(string: "https://secure.fanboy.co.nz/fanboy-annoyance.txt")!,
        isEnabledByDefault: false,
    )

    public static let all: [FilterListSource] = [.easyList, .easyPrivacy, .fanboyAnnoyance]

    /// Minimal tracker rules used until the subscribed lists have been downloaded.
    public static let builtInRules = """
    ||doubleclick.net^$third-party
    ||googlesyndication.com^$third-party
    ||googleadservices.com^$third-party
    ||google-analytics.com^$third-party
    ||googletagmanager.com^$third-party
    ||adnxs.com^$third-party
    ||adsrvr.org^$third-party
    ||criteo.com^$third-party
    ||criteo.net^$third-party
    ||taboola.com^$third-party
    ||outbrain.com^$third-party
    ||scorecardresearch.com^$third-party
    ||quantserve.com^$third-party
    ||amazon-adsystem.com^$third-party
    ||hotjar.com^$third-party
    ||mixpanel.com^$third-party
    ||segment.io^$third-party
    ||moatads.com^$third-party
    ||pubmatic.com^$third-party
    ||rubiconproject.com^$third-party
    ||openx.net^$third-party
    ||casalemedia.com^$third-party
    ||bluekai.com^$third-party
    ||demdex.net^$third-party
    """
}

/// Outcome of a conditional filter-list download.
public enum FilterListFetchResult: Sendable, Equatable {
    case updated(contents: String, etag: String?)
    case notModified
}
