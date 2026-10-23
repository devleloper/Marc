import AppKit
import MarcCore
import MarcUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var windows: WindowManager?
    private var menu: MainMenu?
    private var appIcon: AppIconController?
    /// Links that arrived before the session was ready.
    private var pendingURLs: [URL] = []
    private let logger = Logger(subsystem: "dev.devleloper.Marc", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await launch() }
    }

    private func launch() async {
        do {
            let environment = try await AppEnvironment.make()
            self.environment = environment
            appIcon = AppIconController(settings: environment.session.settings)
            let windows = WindowManager(session: environment.session, updater: environment.updater)
            self.windows = windows
            let menu = MainMenu(session: environment.session, windows: windows)
            self.menu = menu
            NSApp.mainMenu = menu.build()
            let demoTab = DemoWorkspace.isRequested ? DemoWorkspace.populate(environment.session.store) : nil
            await environment.session.start()
            if let demoTab { (environment.session.keyWindow ?? environment.session.openWindow()).select(demoTab) }
            open(pendingURLs)
            pendingURLs = []
            if !environment.session.settings.settings.hasCompletedOnboarding {
                windows.showOnboarding()
            }
        } catch {
            logger.fault("Launch failed: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert(error: error)
            alert.messageText = "Marc Couldn't Open Its Data"
            alert.informativeText = "\(error.localizedDescription)\n\nMarc will quit. Your data has not been changed."
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Links and files from other apps

    func application(_ application: NSApplication, open urls: [URL]) {
        guard environment != nil else {
            pendingURLs += urls
            return
        }
        open(urls)
    }

    private func open(_ urls: [URL]) {
        guard let session = environment?.session, !urls.isEmpty else { return }
        for url in urls where url.isWebURL || url.isFileURL {
            if session.settings.settings.opensExternalLinksInLittleWindow, url.isWebURL {
                session.openEphemeralWindow(kind: .little, url: url)
            } else {
                let window = session.keyWindow ?? session.openWindow()
                window.open(url, placement: .newTab)
                window.nsWindow?.makeKeyAndOrderFront(nil)
            }
        }
        NSApp.activate()
    }

    // MARK: - Lifecycle

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, let session = environment?.session {
            session.openWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session = environment?.session else { return .terminateNow }
        Task {
            await session.prepareForTermination()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(newWindowFromDock), keyEquivalent: "").target = self
        menu.addItem(withTitle: "New Incognito Window", action: #selector(newIncognitoWindowFromDock), keyEquivalent: "").target = self
        return menu
    }

    @objc private func newWindowFromDock() {
        environment?.session.openWindow()
    }

    @objc private func newIncognitoWindowFromDock() {
        environment?.session.openEphemeralWindow(kind: .incognito).showCommandBar(.newTab)
    }
}
