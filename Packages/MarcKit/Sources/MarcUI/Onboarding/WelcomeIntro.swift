import AppKit
import Observation
import SwiftUI

/// Plays the welcome intro: when it started, whether it is leaving, and its music.
@MainActor
@Observable
final class WelcomeIntroModel {
    /// How long the zoom-away after "Get Started" or Skip takes.
    static let exitDuration = 0.9

    var isMuted = false {
        didSet { updateVolume() }
    }

    private(set) var startDate: Date?
    private(set) var exitDate: Date?
    @ObservationIgnored var onFinish: (() -> Void)?
    @ObservationIgnored private let soundtrack: WelcomeSoundtrack?
    @ObservationIgnored private var isAppActive = true

    init(playsMusic: Bool) {
        soundtrack = playsMusic ? WelcomeSoundtrack() : nil
    }

    func start(at date: Date = .now) {
        guard startDate == nil else { return }
        startDate = date
        updateVolume()
        soundtrack?.start()
    }

    func elapsed(at date: Date) -> Double {
        startDate.map { max(date.timeIntervalSince($0), 0) } ?? 0
    }

    func exitElapsed(at date: Date) -> Double? {
        exitDate.map { date.timeIntervalSince($0) }
    }

    /// Zooms the intro away, fades the music and then calls `onFinish`.
    func finish() {
        guard exitDate == nil else { return }
        exitDate = .now
        soundtrack?.stop(over: Self.exitDuration + 0.3)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.exitDuration))
            self?.onFinish?()
        }
    }

    /// The music goes quiet while Marc is in the background.
    func setAppActive(_ isActive: Bool) {
        isAppActive = isActive
        updateVolume()
    }

    private func updateVolume() {
        guard exitDate == nil else { return }
        soundtrack?.isMuted = isMuted || !isAppActive
    }
}

struct WelcomeIntroView: View {
    let model: WelcomeIntroModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            WelcomeIntroScene(
                timeline: WelcomeIntroTimeline(time: model.elapsed(at: context.date), reduceMotion: reduceMotion),
                exit: welcomeExitProgress(model.exitElapsed(at: context.date)),
                isMuted: model.isMuted,
                onGetStarted: model.finish,
                onToggleMute: { model.isMuted.toggle() },
            )
        }
        .onAppear { model.start() }
    }
}

/// Shows the welcome intro over the whole screen, above the menu bar and the Dock, the way Arc
/// greets new users. It hides while Marc is in the background and closes after "Get Started",
/// Skip, Return or Escape.
@MainActor
public final class WelcomeIntroController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var model: WelcomeIntroModel?

    override public init() {
        super.init()
    }

    public var isShowing: Bool {
        window != nil
    }

    /// Presents the intro, then calls `onFinish` once it has gone. Without music (UI tests) the intro
    /// plays silently.
    public func show(playsMusic: Bool = true, onFinish: @escaping () -> Void) {
        guard window == nil, let screen = NSScreen.main ?? NSScreen.screens.first else {
            onFinish()
            return
        }
        let model = WelcomeIntroModel(playsMusic: playsMusic)
        let window = WelcomeIntroWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.hidesOnDeactivate = true
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "Welcome to Marc"
        window.delegate = self
        let host = NSHostingView(rootView: WelcomeIntroView(model: model))
        host.sizingOptions = []
        window.contentView = host
        window.onKeyDown = { [weak model] event in
            switch event.keyCode {
            case 36, 53, 76: // Return, Escape, Enter
                model?.finish()
                return true
            case 46: // M
                model?.isMuted.toggle()
                return true
            default:
                return false
            }
        }
        model.onFinish = { [weak self] in
            self?.close()
            onFinish()
        }
        self.window = window
        self.model = model
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window?.delegate = nil
        window?.orderOut(nil)
        window = nil
        model = nil
    }

    // The intro's window is only key while Marc is frontmost.

    public func windowDidBecomeKey(_ notification: Notification) {
        model?.setAppActive(true)
    }

    public func windowDidResignKey(_ notification: Notification) {
        model?.setAppActive(false)
    }
}

/// A borderless window that can still take keyboard input. The scene's buttons have shortcuts
/// for Return, Escape and M; keys they don't catch arrive here.
private final class WelcomeIntroWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
