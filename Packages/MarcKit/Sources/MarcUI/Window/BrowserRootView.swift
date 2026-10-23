import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// The root view of a browser window.
public struct BrowserRootView: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(window: BrowserWindowModel) {
        self.window = window
    }

    public var body: some View {
        let palette = window.palette
        let sidebarWidth = window.state.sidebarWidth
        ZStack(alignment: .topLeading) {
            ThemeBackground(palette: palette, grain: window.space?.theme.grain ?? 0)

            HStack(spacing: 0) {
                if window.isSidebarVisible {
                    SidebarView(window: window)
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading))
                }
                ContentArea(window: window)
                    .padding(.top, Metrics.Content.inset)
                    .padding(.trailing, Metrics.Content.inset)
                    .padding(.bottom, Metrics.Content.inset)
                    .padding(.leading, window.isSidebarVisible ? 0 : Metrics.Content.inset)
            }

            if window.isSidebarVisible {
                SidebarResizeHandle(window: window)
                    .offset(x: sidebarWidth - 4)
            } else {
                HiddenSidebarReveal(window: window)
            }

            if let peek = window.peek {
                PeekOverlay(window: window, peek: peek)
                    .transition(.opacity)
            }

            if let commandBar = window.commandBar {
                CommandBarOverlay(window: window, model: commandBar)
            }

            ToastStack(window: window)
        }
        .animation(Motion.accessible(Motion.sidebarToggle, reduceMotion: reduceMotion), value: window.isSidebarVisible)
        .animation(Motion.surface, value: window.peek?.id)
        .environment(\.themePalette, palette)
        .sheet(item: $window.sourceViewer) { SourceViewerSheet(model: $0) }
        .sheet(isPresented: $window.isShowingImport) { ImportSheet(window: window) }
        .frame(minWidth: Metrics.Window.minimumSize.width, minHeight: Metrics.Window.minimumSize.height)
        .background(WindowAccessor(window: window))
    }
}

/// Positions the Command Bar at about a third of the window height; clicking outside closes it.
private struct CommandBarOverlay: View {
    let window: BrowserWindowModel
    let model: CommandBarModel

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { window.dismissCommandBar() }
                CommandBarView(model: model, window: window)
                    .frame(maxWidth: min(Metrics.CommandBar.width, proxy.size.width - 40))
                    .padding(.top, max(proxy.size.height * Metrics.CommandBar.verticalPosition - 40, 40))
            }
        }
    }
}

/// While the sidebar is hidden, the leading edge reveals it as an overlay.
private struct HiddenSidebarReveal: View {
    @Bindable var window: BrowserWindowModel
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: Metrics.Sidebar.revealZoneWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering { withAnimation(Motion.sidebarToggle) { window.isSidebarRevealed = true } }
                }
            if window.isSidebarRevealed {
                SidebarView(window: window)
                    .frame(width: window.state.sidebarWidth)
                    .background {
                        ThemeBackground(palette: palette, grain: window.space?.theme.grain ?? 0)
                            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 18, x: 4)
                    }
                    .padding(.vertical, 4)
                    .onHover { hovering in
                        if !hovering { withAnimation(Motion.sidebarToggle) { window.isSidebarRevealed = false } }
                    }
                    .transition(.move(edge: .leading))
            }
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

/// Drag the sidebar's trailing edge to resize it.
private struct SidebarResizeHandle: View {
    @Bindable var window: BrowserWindowModel
    @State private var startWidth: Double?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? window.state.sidebarWidth
                        startWidth = start
                        let width = start + value.translation.width
                        window.state.sidebarWidth = min(
                            max(width, WindowState.sidebarWidthRange.lowerBound),
                            WindowState.sidebarWidthRange.upperBound,
                        )
                    }
                    .onEnded { _ in startWidth = nil },
            )
            .accessibilityLabel("Resize sidebar")
    }
}

private struct ToastStack: View {
    @Bindable var window: BrowserWindowModel

    var body: some View {
        VStack {
            Spacer()
            ForEach(window.toasts) { toast in
                ToastView(message: toast.message, symbol: toast.symbol, actionTitle: toast.actionTitle, action: toast.action)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(!window.toasts.isEmpty)
        .animation(Motion.toast, value: window.toasts)
    }
}

/// Floating card for a link opened from a pinned tab or favorite.
private struct PeekOverlay: View {
    @Bindable var window: BrowserWindowModel
    @Bindable var peek: PeekModel
    @State private var appeared = false
    @State private var token = UUID()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.25)
                    .onTapGesture { peek.close() }
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        FaviconView(image: peek.tab.favicon, fallbackTitle: peek.tab.title)
                        Text(peek.tab.url?.displayHost ?? "").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Button { peek.openAsTab(split: true) } label: { Image(systemName: "rectangle.split.2x1") }
                            .help("Open in Split View")
                        Button { peek.openAsTab() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .help("Open as Tab")
                        Button { peek.close() } label: { Image(systemName: "xmark") }
                            .help("Close")
                            .keyboardShortcut(.cancelAction)
                    }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.regularMaterial)
                    WebContentView(tab: peek.tab, token: token)
                }
                .frame(width: proxy.size.width * 0.72, height: proxy.size.height * 0.86)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 40, y: 20)
                .scaleEffect(appeared ? 1 : 0.96)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear { withAnimation(Motion.surface) { appeared = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peek")
    }
}

/// Gives the model access to its `NSWindow`.
private struct WindowAccessor: NSViewRepresentable {
    let window: BrowserWindowModel

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in window.nsWindow = view?.window }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if window.nsWindow == nil { window.nsWindow = view.window }
    }
}
