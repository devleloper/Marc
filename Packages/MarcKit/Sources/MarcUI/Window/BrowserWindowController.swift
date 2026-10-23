import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import Observation
import SwiftUI

/// A borderless-looking window: transparent title bar, full-size content and traffic lights
/// placed where Arc puts them.
public final class BrowserWindow: NSWindow {
    var trafficLightsHidden = false {
        didSet { positionTrafficLights() }
    }

    /// The vertical center of the traffic lights, matching the window's toolbar row.
    var trafficLightCenterY = Metrics.Window.trafficLightCenterY {
        didSet { positionTrafficLights() }
    }

    override public func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
    }

    func positionTrafficLights() {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        guard let close = standardWindowButton(.closeButton), let container = close.superview else { return }
        let isFullScreen = styleMask.contains(.fullScreen)
        for (index, type) in buttons.enumerated() {
            guard let button = standardWindowButton(type) else { continue }
            button.isHidden = trafficLightsHidden && !isFullScreen
            guard !isFullScreen else { continue }
            let origin = NSPoint(
                x: Metrics.Window.trafficLightLeading + CGFloat(index) * 23,
                y: container.frame.height - trafficLightCenterY - button.frame.height / 2,
            )
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }
}

/// Owns one browser window and keeps its chrome in sync with the model.
public final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    public let model: BrowserWindowModel
    private let onClose: (BrowserWindowModel) -> Void
    private var isObserving = true

    public init(model: BrowserWindowModel, onClose: @escaping (BrowserWindowModel) -> Void) {
        self.model = model
        self.onClose = onClose
        let size = model.kind == .little ? CGSize(width: 520, height: 680) : Metrics.Window.defaultSize
        let window = BrowserWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.minSize = Metrics.Window.minimumSize
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.setAccessibilityIdentifier("browserWindow")
        super.init(window: window)
        window.delegate = self

        let rootView = model.kind == .little ? AnyView(LittleWindowView(window: model)) : AnyView(BrowserRootView(window: model))
        let hostingView = NSHostingView(rootView: rootView)
        // The content extends under the transparent title bar; the toolbar rows reserve room for
        // the traffic lights themselves.
        hostingView.safeAreaRegions = []
        window.contentView = hostingView
        window.trafficLightCenterY = model.kind == .little ? Metrics.Window.littleToolbarHeight / 2 : Metrics.Window.trafficLightCenterY
        restoreFrame(of: window)
        model.nsWindow = window
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func restoreFrame(of window: NSWindow) {
        if let frame = model.state.frame {
            window.setFrame(NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height), display: false)
        } else if model.kind == .little, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.maxX - window.frame.width - 40, y: visible.maxY - window.frame.height - 40))
        } else {
            window.center()
        }
    }

    /// Re-applies appearance and traffic-light visibility whenever the observed model changes.
    private func observeModel() {
        guard isObserving, let window = window as? BrowserWindow else { return }
        withObservationTracking {
            let palette = model.palette
            window.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            window.trafficLightsHidden = model.kind != .little && !model.isSidebarVisible && !model.isSidebarRevealed
            window.title = model.selectedTab?.title ?? model.space?.name ?? "Marc"
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.observeModel() }
        }
    }

    // MARK: - NSWindowDelegate

    public func windowDidBecomeKey(_ notification: Notification) {
        model.session?.windowDidBecomeKey(model)
    }

    public func windowDidResize(_ notification: Notification) {
        (window as? BrowserWindow)?.positionTrafficLights()
        saveFrame()
    }

    public func windowDidMove(_ notification: Notification) {
        saveFrame()
    }

    public func windowDidExitFullScreen(_ notification: Notification) {
        (window as? BrowserWindow)?.positionTrafficLights()
    }

    public func windowWillClose(_ notification: Notification) {
        isObserving = false
        onClose(model)
    }

    private func saveFrame() {
        guard let frame = window?.frame, model.kind == .standard else { return }
        model.state.frame = WindowState.Frame(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height)
    }
}
