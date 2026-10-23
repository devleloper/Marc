import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// Horizontally paged Spaces. Clicking a Space icon or a shortcut slides pages with Arc's
/// ease-out-expo curve; a two-finger horizontal swipe drags them interactively.
struct SpacePager: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragOffset: CGFloat = 0
    @State private var transition: PageTransition?
    @State private var progress: CGFloat = 1
    /// Set when a swipe commits, so the resulting Space change continues from the dragged position.
    @State private var swipeStartProgress: CGFloat?

    private struct PageTransition: Equatable {
        let from: Space.ID
        let to: Space.ID
        let forward: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let spaces = window.workspace.orderedSpaces
            let currentIndex = spaces.firstIndex { $0.id == window.state.spaceID } ?? 0
            ZStack(alignment: .topLeading) {
                ForEach(pages(spaces: spaces, currentIndex: currentIndex), id: \.space.id) { page in
                    SpacePageView(window: window, space: page.space)
                        .frame(width: width)
                        .offset(x: page.offset * width + dragOffset)
                        .allowsHitTesting(page.offset == 0 && transition == nil)
                }
            }
            .frame(width: width, alignment: .topLeading)
            .clipped()
            .background(
                HorizontalSwipeMonitor { phase in
                    handleSwipe(phase, width: width, spaces: spaces, currentIndex: currentIndex)
                },
            )
        }
        .onChange(of: window.state.spaceID) { oldValue, newValue in
            guard let oldValue, let newValue else { return }
            let start = swipeStartProgress ?? 0
            swipeStartProgress = nil
            animate(from: oldValue, to: newValue, forward: window.spaceChangeIsForward, startProgress: start)
        }
    }

    private struct Page {
        let space: Space
        let offset: CGFloat
    }

    private func pages(spaces: [Space], currentIndex: Int) -> [Page] {
        if let transition,
           let from = spaces.first(where: { $0.id == transition.from }),
           let to = spaces.first(where: { $0.id == transition.to }) {
            let direction: CGFloat = transition.forward ? 1 : -1
            return [Page(space: from, offset: -direction * progress), Page(space: to, offset: direction * (1 - progress))]
        }
        guard spaces.indices.contains(currentIndex) else { return [] }
        var result = [Page(space: spaces[currentIndex], offset: 0)]
        if dragOffset < 0, spaces.indices.contains(currentIndex + 1) {
            result.append(Page(space: spaces[currentIndex + 1], offset: 1))
        } else if dragOffset > 0, spaces.indices.contains(currentIndex - 1) {
            result.append(Page(space: spaces[currentIndex - 1], offset: -1))
        }
        return result
    }

    private func animate(from: Space.ID, to: Space.ID, forward: Bool, startProgress: CGFloat) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            transition = PageTransition(from: from, to: to, forward: forward)
            progress = startProgress
            dragOffset = 0
        }
        withAnimation(Motion.accessible(Motion.spacePage, reduceMotion: reduceMotion)) {
            progress = 1
        } completion: {
            if transition?.to == to { transition = nil }
        }
    }

    private func handleSwipe(_ phase: HorizontalSwipeMonitor.Phase, width: CGFloat, spaces: [Space], currentIndex: Int) {
        switch phase {
        case let .changed(translation):
            guard transition == nil else { return }
            let hasNeighbor = translation < 0 ? currentIndex + 1 < spaces.count : currentIndex > 0
            // Rubber-band at the ends.
            dragOffset = hasNeighbor ? max(min(translation, width), -width) : translation / 4
        case let .ended(velocity):
            let threshold = width * 0.3
            let target = dragOffset < -threshold || velocity < -600 ? currentIndex + 1
                : dragOffset > threshold || velocity > 600 ? currentIndex - 1 : currentIndex
            if target != currentIndex, spaces.indices.contains(target) {
                swipeStartProgress = min(abs(dragOffset) / width, 1)
                window.switchSpace(to: spaces[target].id)
            } else {
                withAnimation(Motion.spacePage) { dragOffset = 0 }
            }
        }
    }
}

/// Reports horizontal trackpad scrolls over its area. Uses a local event monitor so vertical
/// scrolling of the sidebar lists keeps working.
struct HorizontalSwipeMonitor: NSViewRepresentable {
    enum Phase {
        case changed(CGFloat)
        case ended(velocity: CGFloat)
    }

    let onSwipe: (Phase) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onSwipe = onSwipe
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onSwipe = onSwipe
    }

    final class SwipeView: NSView {
        var onSwipe: ((Phase) -> Void)?
        private var monitor: Any?
        private var translation: CGFloat = 0
        private var isTracking = false
        private var lastDelta: CGFloat = 0
        private var lastTimestamp: TimeInterval = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return handle(event) ? nil : event
            }
        }

        override func removeFromSuperview() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            super.removeFromSuperview()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        /// Returns true when the event was consumed as a Space swipe.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, event.hasPreciseScrollingDeltas else { return false }
            let location = convert(event.locationInWindow, from: nil)
            if event.phase == .began {
                guard bounds.contains(location) else { return false }
                isTracking = false
                translation = 0
            }
            if !event.momentumPhase.isEmpty { return isTracking }

            switch event.phase {
            case .began, .changed:
                if !isTracking {
                    guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5,
                          abs(event.scrollingDeltaX) > 1 else { return false }
                    isTracking = true
                }
                translation += event.scrollingDeltaX
                lastDelta = event.scrollingDeltaX
                lastTimestamp = event.timestamp
                onSwipe?(.changed(translation))
                return true
            case .ended, .cancelled:
                guard isTracking else { return false }
                isTracking = false
                let elapsed = max(event.timestamp - lastTimestamp, 1.0 / 120)
                onSwipe?(.ended(velocity: lastDelta / elapsed))
                return true
            default:
                return isTracking
            }
        }
    }
}
