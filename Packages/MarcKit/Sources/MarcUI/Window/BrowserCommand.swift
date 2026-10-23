import AppKit
import Foundation
import MarcCore
import MarcWebKit

/// Every user-facing command. Menus, keyboard shortcuts and the Command Bar all dispatch
/// through `BrowserWindowModel.perform(_:)`, so each command has one implementation.
public enum BrowserCommand: Hashable, Sendable {
    // File
    case newTab
    case newWindow
    case newBlankWindow
    case newIncognitoWindow
    case newLittleWindow
    case restoreClosedTab
    case openLocation
    case newNote
    case archiveTab
    case share
    case savePage
    case printPage
    case importData
    // Edit
    case copyURL
    case copyURLAsMarkdown
    case copyURLAsQuote
    case find
    case findNext
    case findPrevious
    // View
    case toggleSidebar
    case stopLoading
    case reload
    case forceReload
    case clearCookiesAndReload
    case clearCacheAndReload
    case addSplit
    case closeSplitPane
    case separateSplitPane
    case zoomIn
    case zoomOut
    case actualSize
    case viewSource
    case developerTools
    // Spaces
    case newSpace
    case editTheme
    case renameSpace
    case nextSpace
    case previousSpace
    case space(Int)
    // Tabs
    case pinTab
    case newFolder
    case nextTab
    case previousTab
    case selectTab(Int)
    case clearToday
    case duplicateTab
    case toggleMute
    case resetPinnedTab
    // History
    case goBack
    case goForward
    case showHistory
    case showArchive
    // Library
    case showLibrary
    case showDownloads
    case boostSite
    // AI
    case summarizePage
    case askPage
    case tidyTabTitles
    // App
    case settings
    case setDefaultBrowser
    case checkForUpdates
    case siteControls

    /// Commands listed in the Command Bar.
    public static let searchable: [BrowserCommand] = [
        .newWindow, .newIncognitoWindow, .newLittleWindow, .newNote, .newSpace, .newFolder, .restoreClosedTab,
        .copyURL, .copyURLAsMarkdown, .find, .toggleSidebar, .reload, .addSplit, .pinTab, .duplicateTab,
        .clearToday, .showHistory, .showArchive, .showLibrary, .showDownloads, .boostSite, .summarizePage,
        .askPage, .tidyTabTitles, .editTheme, .zoomIn, .zoomOut, .actualSize, .printPage, .savePage, .viewSource,
        .importData, .settings, .setDefaultBrowser, .siteControls, .toggleMute, .clearCookiesAndReload,
    ]

    public var title: String {
        switch self {
        case .newTab: "New Tab"
        case .newWindow: "New Window"
        case .newBlankWindow: "Blank Window"
        case .newIncognitoWindow: "New Incognito Window"
        case .newLittleWindow: "New Little Window"
        case .restoreClosedTab: "Restore Last Closed Tab"
        case .openLocation: "Open Location"
        case .newNote: "New Note"
        case .archiveTab: "Archive Tab"
        case .share: "Share…"
        case .savePage: "Save Page As…"
        case .printPage: "Print…"
        case .importData: "Import Browser Data…"
        case .copyURL: "Copy URL"
        case .copyURLAsMarkdown: "Copy URL as Markdown"
        case .copyURLAsQuote: "Copy URL as Quote"
        case .find: "Find in Page"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .toggleSidebar: "Toggle Sidebar"
        case .stopLoading: "Stop Loading"
        case .reload: "Reload Page"
        case .forceReload: "Force Reload Page"
        case .clearCookiesAndReload: "Clear Cookies and Reload"
        case .clearCacheAndReload: "Clear Cache and Reload"
        case .addSplit: "Add Split View"
        case .closeSplitPane: "Close Split Pane"
        case .separateSplitPane: "Separate Page from Split View"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .actualSize: "Actual Size"
        case .viewSource: "View Source"
        case .developerTools: "Developer Tools"
        case .newSpace: "New Space"
        case .editTheme: "Edit Theme"
        case .renameSpace: "Rename Space"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case let .space(number): "Space \(number)"
        case .pinTab: "Pin or Unpin Tab"
        case .newFolder: "New Folder"
        case .nextTab: "Next Tab"
        case .previousTab: "Previous Tab"
        case let .selectTab(number): "Tab \(number)"
        case .clearToday: "Clear Unpinned Tabs"
        case .duplicateTab: "Duplicate Tab"
        case .toggleMute: "Mute or Unmute Tab"
        case .resetPinnedTab: "Back to Pinned URL"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .showHistory: "Show History"
        case .showArchive: "Show Archive"
        case .showLibrary: "Show Library"
        case .showDownloads: "Show Downloads"
        case .boostSite: "Boost This Site"
        case .summarizePage: "Summarize Page"
        case .askPage: "Ask This Page"
        case .tidyTabTitles: "Tidy Tab Titles"
        case .settings: "Settings…"
        case .setDefaultBrowser: "Set as Default Browser"
        case .checkForUpdates: "Check for Updates…"
        case .siteControls: "Site Controls"
        }
    }

    public var symbol: String {
        switch self {
        case .newTab, .addSplit: "plus.square.on.square"
        case .newWindow, .newBlankWindow: "macwindow.badge.plus"
        case .newIncognitoWindow: "eyeglasses"
        case .newLittleWindow: "rectangle.inset.topright.filled"
        case .restoreClosedTab: "arrow.uturn.backward"
        case .openLocation: "magnifyingglass"
        case .newNote: "note.text.badge.plus"
        case .archiveTab: "archivebox"
        case .share: "square.and.arrow.up"
        case .savePage: "square.and.arrow.down"
        case .printPage: "printer"
        case .importData: "square.and.arrow.down.on.square"
        case .copyURL, .copyURLAsMarkdown, .copyURLAsQuote: "link"
        case .find, .findNext, .findPrevious: "text.magnifyingglass"
        case .toggleSidebar: "sidebar.left"
        case .stopLoading: "xmark"
        case .reload, .forceReload: "arrow.clockwise"
        case .clearCookiesAndReload, .clearCacheAndReload: "trash"
        case .closeSplitPane, .separateSplitPane: "rectangle.split.2x1"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .actualSize: "1.magnifyingglass"
        case .viewSource, .developerTools: "chevron.left.forwardslash.chevron.right"
        case .newSpace, .space: "square.grid.2x2"
        case .editTheme: "paintpalette"
        case .renameSpace: "pencil"
        case .nextSpace: "arrow.right"
        case .previousSpace: "arrow.left"
        case .pinTab, .resetPinnedTab: "pin"
        case .newFolder: "folder.badge.plus"
        case .nextTab: "arrow.down"
        case .previousTab: "arrow.up"
        case .selectTab: "number"
        case .clearToday: "archivebox"
        case .duplicateTab: "plus.square.on.square"
        case .toggleMute: "speaker.slash"
        case .goBack: "chevron.left"
        case .goForward: "chevron.right"
        case .showHistory: "clock.arrow.circlepath"
        case .showArchive: "archivebox"
        case .showLibrary: "books.vertical"
        case .showDownloads: "arrow.down.circle"
        case .boostSite: "paintbrush.pointed"
        case .summarizePage: "text.append"
        case .askPage: "bubble.left.and.text.bubble.right"
        case .tidyTabTitles: "wand.and.stars"
        case .settings: "gearshape"
        case .setDefaultBrowser: "globe"
        case .checkForUpdates: "arrow.triangle.2.circlepath"
        case .siteControls: "slider.horizontal.3"
        }
    }

    public var keywords: [String] {
        switch self {
        case .toggleSidebar: ["hide", "show"]
        case .clearToday: ["close", "unpinned", "today"]
        case .summarizePage, .askPage, .tidyTabTitles: ["ai", "max", "assistant"]
        case .boostSite: ["customize", "css", "style"]
        case .importData: ["arc", "chrome", "safari", "bookmarks"]
        case .settings: ["preferences"]
        case .newIncognitoWindow: ["private"]
        default: []
        }
    }

    public var keyboardShortcut: KeyboardShortcutSpec? {
        switch self {
        case .newTab: .init("t", [.command])
        case .newWindow: .init("n", [.command])
        case .newBlankWindow: .init("n", [.command, .control])
        case .newIncognitoWindow: .init("n", [.command, .shift])
        case .newLittleWindow: .init("n", [.command, .option])
        case .restoreClosedTab: .init("t", [.command, .shift])
        case .openLocation: .init("l", [.command])
        case .newNote: .init("n", [.control, .shift])
        case .archiveTab: .init("w", [.command])
        case .savePage: .init("s", [.command, .shift])
        case .printPage: .init("p", [.command])
        case .copyURL: .init("c", [.command, .shift])
        case .copyURLAsMarkdown: .init("c", [.command, .shift, .option])
        case .copyURLAsQuote: .init("c", [.command, .shift, .control])
        case .find: .init("f", [.command])
        case .findNext: .init("g", [.command])
        case .findPrevious: .init("g", [.command, .shift])
        case .toggleSidebar: .init("s", [.command])
        case .stopLoading: .init(".", [.command])
        case .reload: .init("r", [.command])
        case .forceReload: .init("r", [.command, .shift])
        case .addSplit: .init("=", [.control, .shift])
        case .closeSplitPane: .init("-", [.control, .shift])
        case .zoomIn: .init("+", [.command])
        case .zoomOut: .init("-", [.command])
        case .actualSize: .init("0", [.command])
        case .viewSource: .init("u", [.command, .option])
        case .developerTools: .init("i", [.command, .option])
        case .nextSpace: .init(String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option])
        case .previousSpace: .init(String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option])
        case let .space(number): .init("\(number)", [.control])
        case .pinTab: .init("d", [.command])
        case .nextTab: .init(String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option])
        case .previousTab: .init(String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option])
        case let .selectTab(number): .init("\(number)", [.command])
        case .clearToday: .init("k", [.command, .shift])
        case .goBack: .init("[", [.command])
        case .goForward: .init("]", [.command])
        case .showHistory: .init("y", [.command])
        case .showLibrary: .init("l", [.command, .shift])
        case .showDownloads: .init("j", [.command, .shift])
        case .settings: .init(",", [.command])
        default: nil
        }
    }

    var descriptor: CommandDescriptor {
        CommandDescriptor(id: identifier, title: title, keywords: keywords, symbol: symbol, shortcut: keyboardShortcut?.displayString)
    }

    var identifier: String {
        switch self {
        case let .space(number): "space-\(number)"
        case let .selectTab(number): "tab-\(number)"
        default: String(describing: self)
        }
    }

    static func command(withIdentifier identifier: String) -> BrowserCommand? {
        searchable.first { $0.identifier == identifier }
    }
}

/// A key equivalent independent of SwiftUI and AppKit menu types.
public struct KeyboardShortcutSpec: Hashable, Sendable {
    public let key: String
    public let modifiers: NSEvent.ModifierFlags

    init(_ key: String, _ modifiers: NSEvent.ModifierFlags) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.key == rhs.key && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(modifiers.rawValue)
    }

    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        let keyName: String = switch key {
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): "→"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑"
        default: key.uppercased()
        }
        return result + keyName
    }
}
