import AppKit
import MarcCore
import MarcUI
import Observation

/// Shows the icon chosen in Settings in the Dock and the app switcher while Marc runs, and
/// follows light and dark appearance for "Match Appearance". The bundle's own icon, which the Dock
/// and Finder show while Marc is closed, can't change: the App Sandbox keeps the bundle read-only.
@MainActor
final class AppIconController {
    private let settings: SettingsModel
    private var appearanceObservation: NSKeyValueObservation?
    private var hasApplied = false
    private var appliedImageName: String?

    init(settings: SettingsModel) {
        self.settings = settings
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.apply() }
        }
        observeSettings()
    }

    private func observeSettings() {
        withObservationTracking {
            apply()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettings() }
        }
    }

    private func apply() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let imageName = settings.settings.appIcon.imageName(isDarkAppearance: isDark)
        guard !hasApplied || imageName != appliedImageName else { return }
        hasApplied = true
        appliedImageName = imageName
        // `nil` restores the bundle's icon.
        NSApp.applicationIconImage = imageName.flatMap { NSImage(named: $0) }
    }
}
