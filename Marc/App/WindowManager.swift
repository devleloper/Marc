import AppKit
import MarcCore
import MarcUI
import Observation
import SwiftUI

/// Creates and tracks the app's windows: browser windows, Settings, the welcome intro and onboarding.
@MainActor
final class WindowManager {
    private let session: BrowserSession
    private let updater: Updater
    private var controllers: [WindowState.ID: BrowserWindowController] = [:]
    private var settingsWindow: NSWindow?
    private var settingsPane = SettingsPaneState()
    private var onboardingWindow: NSWindow?
    private let welcome = WelcomeIntroController()

    init(session: BrowserSession, updater: Updater) {
        self.session = session
        self.updater = updater
        session.presentWindow = { [weak self] model in self?.present(model) }
        session.showSettings = { [weak self] pane in self?.showSettings(pane) }
        session.checkForUpdates = { [weak self] in self?.updater.checkForUpdates() }
    }

    private func present(_ model: BrowserWindowModel) {
        let controller = BrowserWindowController(model: model) { [weak self] closed in
            self?.session.windowDidClose(closed)
            self?.controllers[closed.id] = nil
        }
        controllers[model.id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// The model of the key browser window, if a browser window is key.
    var keyModel: BrowserWindowModel? {
        controllers.values.first { $0.window === NSApp.keyWindow }?.model
    }

    func showSettings(_ pane: SettingsPane = .general) {
        settingsPane.pane = pane
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: SettingsRoot(session: session, state: settingsPane))
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.setContentSize(NSSize(width: 760, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("MarcSettings")
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    /// Plays the full-screen welcome intro, then calls `completion`.
    func showWelcome(playsMusic: Bool = true, then completion: @escaping () -> Void = {}) {
        guard !welcome.isShowing else { return }
        welcome.show(playsMusic: playsMusic, onFinish: completion)
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(session: session) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
    }
}

/// Lets the menu and `showSettings(_:)` switch the visible Settings pane.
@MainActor
@Observable
final class SettingsPaneState {
    var pane = SettingsPane.general
}

private struct SettingsRoot: View {
    let session: BrowserSession
    @Bindable var state: SettingsPaneState

    var body: some View {
        SettingsView(session: session, pane: $state.pane)
    }
}
