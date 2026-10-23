import AppKit
import MarcCore
import MarcDesignSystem
import MarcWebKit
import SwiftUI

/// First-launch walkthrough: what Marc is, importing, a theme and the default browser.
public struct OnboardingView: View {
    @Bindable var session: BrowserSession
    let onFinish: () -> Void
    @State private var step = Step.welcome
    @State private var theme = Theme.default

    enum Step: Int, CaseIterable {
        case welcome
        case theme
        case importData
        case defaultBrowser
    }

    public init(session: BrowserSession, onFinish: @escaping () -> Void) {
        self.session = session
        self.onFinish = onFinish
    }

    public var body: some View {
        let palette = ThemePalette(
            themeColors: theme.colors.map { PaletteColor(red: $0.red, green: $0.green, blue: $0.blue) },
            isDark: theme.appearance != .light,
        )
        ZStack {
            ThemeBackground(palette: palette, grain: theme.grain)
            VStack(spacing: 22) {
                Spacer(minLength: 20)
                content
                    .foregroundStyle(palette.primaryText)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity),
                    ))
                    .id(step)
                Spacer(minLength: 20)
                HStack {
                    HStack(spacing: 6) {
                        ForEach(Step.allCases, id: \.self) { candidate in
                            Circle()
                                .fill(palette.primaryText.opacity(candidate == step ? 0.9 : 0.25))
                                .frame(width: 6, height: 6)
                        }
                    }
                    Spacer()
                    if step != .welcome {
                        Button("Back") { move(by: -1) }
                            .buttonStyle(.pressable)
                            .foregroundStyle(palette.secondaryText)
                    }
                    Button(step == .defaultBrowser ? "Start Browsing" : "Continue") { advance() }
                        .buttonStyle(PrimaryButtonStyle())
                        .frame(width: 160)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("onboardingContinue")
                }
            }
            .padding(36)
        }
        .frame(width: 620, height: 460)
        .environment(\.themePalette, palette)
        .animation(Motion.surface, value: step)
        .onAppear { theme = session.keyWindow?.space?.theme ?? .default }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 14) {
                Image(systemName: "sparkles").font(.system(size: 44, weight: .light))
                Text("Welcome to Marc").font(.system(size: 30, weight: .bold))
                Text(
                    "A calmer way to browse. Tabs live in the sidebar, Spaces keep projects apart, and unpinned tabs tidy themselves away.",
                )
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .opacity(0.8)
                VStack(alignment: .leading, spacing: 8) {
                    tip("command", "⌘T opens the Command Bar to search, open sites and run commands")
                    tip("square.grid.2x2", "Spaces separate work, life and side projects")
                    tip("pin", "Pinned tabs stay; Today tabs are archived after 12 hours")
                }
                .padding(.top, 6)
            }
        case .theme:
            VStack(spacing: 16) {
                Text("Pick a Look").font(.system(size: 26, weight: .bold))
                Text("Every Space has its own theme. You can change it any time from the Space's menu.").opacity(0.8)
                HStack(spacing: 12) {
                    ForEach(Array(Theme.presets.enumerated()), id: \.offset) { _, preset in
                        Button {
                            theme = preset
                            applyTheme(preset)
                        } label: {
                            ThemeSwatch(theme: preset)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().strokeBorder(.white.opacity(preset == theme ? 1 : 0), lineWidth: 3))
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        case .importData:
            VStack(spacing: 16) {
                Text("Bring Your Stuff").font(.system(size: 26, weight: .bold))
                Text("Import Spaces, pinned tabs and favorites from Arc, or bookmarks and history from Chrome and Safari.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .opacity(0.8)
                Button("Import…") {
                    if let window = session.keyWindow {
                        window.isShowingImport = true
                        window.nsWindow?.makeKeyAndOrderFront(nil)
                    }
                }
                .controlSize(.large)
            }
        case .defaultBrowser:
            VStack(spacing: 16) {
                Text("Make Marc Your Browser").font(.system(size: 26, weight: .bold))
                Text("Links from other apps open in a Little window, so you can read them without losing your place.")
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .opacity(0.8)
                if DefaultBrowser.isDefault {
                    Label("Marc is your default browser", systemImage: "checkmark.circle.fill")
                } else {
                    Button("Set as Default Browser") { DefaultBrowser.request() }
                        .controlSize(.large)
                }
            }
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 13))
    }

    private func applyTheme(_ theme: Theme) {
        guard let spaceID = session.keyWindow?.state.spaceID else { return }
        try? session.store.update { try $0.updateSpace(spaceID) { $0.theme = theme } }
    }

    private func move(by offset: Int) {
        guard let next = Step(rawValue: step.rawValue + offset) else { return }
        step = next
    }

    private func advance() {
        if step == .defaultBrowser {
            session.settings.settings.hasCompletedOnboarding = true
            onFinish()
        } else {
            move(by: 1)
        }
    }
}
