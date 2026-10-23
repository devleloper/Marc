import AppKit
import MarcCore
import MarcUI

/// Builds the menu bar from `BrowserCommand`s and routes them to the key browser window.
@MainActor
final class MainMenu: NSObject, NSMenuItemValidation, NSMenuDelegate {
    private let session: BrowserSession
    private let windows: WindowManager
    private var spacesMenu: NSMenu?

    init(session: BrowserSession, windows: WindowManager) {
        self.session = session
        self.windows = windows
    }

    func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        let spaces = menu("Spaces", items: [])
        spaces.delegate = self
        spacesMenu = spaces
        main.addItem(submenu(spaces))
        main.addItem(submenu(tabsMenu()))
        main.addItem(submenu(menu("History", items: [.goBack, .goForward, nil, .showHistory, .showArchive])))
        main.addItem(submenu(menu(
            "Tools",
            items: [.boostSite, .siteControls, nil, .summarizePage, .askPage, .tidyTabTitles, nil, .showLibrary, .showDownloads],
        )))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    // MARK: - Menus

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Marc")
        menu.addItem(withTitle: "About Marc", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item(.settings))
        menu.addItem(item(.setDefaultBrowser))
        menu.addItem(item(.checkForUpdates))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        menu.addItem(submenu(services))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Marc", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Marc", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = menu("File", items: [
            .newTab, .newWindow, .newBlankWindow, .newIncognitoWindow, .newLittleWindow, .restoreClosedTab, .openLocation, .newNote, nil,
        ])
        let close = menu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(item(.archiveTab))
        menu.addItem(.separator())
        for command in [BrowserCommand.share, .savePage, .printPage] {
            menu.addItem(item(command))
        }
        menu.addItem(.separator())
        menu.addItem(item(.importData))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteMatching = menu.addItem(
            withTitle: "Paste and Match Style",
            action: #selector(NSTextView.pasteAsPlainText(_:)),
            keyEquivalent: "v",
        )
        pasteMatching.keyEquivalentModifierMask = [.command, .shift, .option]
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        for command in [BrowserCommand.copyURL, .copyURLAsMarkdown, .copyURLAsQuote] {
            menu.addItem(item(command))
        }
        menu.addItem(.separator())
        menu.addItem(submenu(self.menu("Find", items: [.find, .findNext, .findPrevious])))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = menu("View", items: [
            .toggleSidebar, nil, .stopLoading, .reload, .forceReload, .clearCookiesAndReload, .clearCacheAndReload, nil,
            .addSplit, .closeSplitPane, .separateSplitPane, nil, .zoomIn, .zoomOut, .actualSize, nil,
        ])
        // ⌘= is the unshifted form of ⌘+ on most layouts.
        let zoomAlternate = item(.zoomIn)
        zoomAlternate.keyEquivalent = "="
        zoomAlternate.isHidden = true
        zoomAlternate.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomAlternate)
        menu.addItem(submenu(self.menu("Developer", items: [.viewSource, .developerTools])))
        menu.addItem(.separator())
        let fullScreen = menu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private func tabsMenu() -> NSMenu {
        let menu = menu(
            "Tabs",
            items: [.newTab, .pinTab, .newFolder, .duplicateTab, .toggleMute, .resetPinnedTab, nil, .nextTab, .previousTab, nil],
        )
        menu.addItem(submenu(self.menu("Go to Tab", items: (1 ... 9).map { BrowserCommand.selectTab($0) })))
        menu.addItem(.separator())
        menu.addItem(item(.clearToday))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item(.showLibrary))
        menu.addItem(item(.showDownloads))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        let help = menu.addItem(withTitle: "Marc Help", action: #selector(openHelp), keyEquivalent: "")
        help.target = self
        let shortcuts = menu.addItem(withTitle: "Keyboard Shortcuts", action: #selector(openShortcuts), keyEquivalent: "")
        shortcuts.target = self
        let issue = menu.addItem(withTitle: "Report an Issue…", action: #selector(reportIssue), keyEquivalent: "")
        issue.target = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === spacesMenu else { return }
        menu.removeAllItems()
        for command in [BrowserCommand.newSpace, .editTheme, .renameSpace] {
            menu.addItem(item(command))
        }
        menu.addItem(.separator())
        menu.addItem(item(.nextSpace))
        menu.addItem(item(.previousSpace))
        menu.addItem(.separator())
        let spaces = session.store.workspace.orderedSpaces
        let current = (windows.keyModel ?? session.keyWindow)?.state.spaceID
        for (index, space) in spaces.prefix(9).enumerated() {
            let entry = item(.space(index + 1))
            entry.title = space.name
            entry.state = space.id == current ? .on : .off
            menu.addItem(entry)
        }
    }

    // MARK: - Items

    private func menu(_ title: String, items: [BrowserCommand?]) -> NSMenu {
        let menu = NSMenu(title: title)
        for command in items {
            menu.addItem(command.map(item) ?? .separator())
        }
        return menu
    }

    private func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func item(_ command: BrowserCommand) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title,
            action: #selector(performCommand(_:)),
            keyEquivalent: command.keyboardShortcut?.key ?? "",
        )
        if let shortcut = command.keyboardShortcut {
            item.keyEquivalentModifierMask = shortcut.modifiers
        }
        item.target = self
        item.representedObject = CommandBox(command)
        return item
    }

    // MARK: - Dispatch

    /// Commands that make sense without a browser window.
    private static let windowIndependent: Set<BrowserCommand> = [
        .newWindow, .newBlankWindow, .newIncognitoWindow, .newLittleWindow, .settings, .setDefaultBrowser, .checkForUpdates,
    ]

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = (sender.representedObject as? CommandBox)?.command else { return }
        let model = windows.keyModel
        switch command {
        case .settings:
            windows.showSettings()
        case .checkForUpdates:
            session.checkForUpdates?()
        case .archiveTab where model == nil:
            // ⌘W closes non-browser windows such as Settings.
            NSApp.keyWindow?.performClose(nil)
        default:
            if let target = model ?? (Self.windowIndependent.contains(command) ? session.keyWindow : nil) {
                target.perform(command)
            } else if Self.windowIndependent.contains(command) || command == .newTab {
                session.openWindow().perform(command == .newWindow ? .newTab : command)
            } else if let fallback = session.keyWindow {
                fallback.perform(command)
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = (menuItem.representedObject as? CommandBox)?.command else { return true }
        if Self.windowIndependent.contains(command) || command == .newTab || command == .archiveTab { return true }
        guard let model = windows.keyModel ?? session.keyWindow else { return false }
        if command == .toggleSidebar { menuItem.title = model.isSidebarVisible ? "Hide Sidebar" : "Show Sidebar" }
        return model.canPerform(command)
    }

    // MARK: - Help

    @objc private func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/devleloper/Marc#readme")!)
    }

    @objc private func openShortcuts() {
        windows.showSettings(.shortcuts)
    }

    @objc private func reportIssue() {
        NSWorkspace.shared.open(URL(string: "https://github.com/devleloper/Marc/issues/new/choose")!)
    }
}

/// Boxes a Swift enum so it can travel through `NSMenuItem.representedObject`.
private final class CommandBox: NSObject {
    let command: BrowserCommand

    init(_ command: BrowserCommand) {
        self.command = command
    }
}
