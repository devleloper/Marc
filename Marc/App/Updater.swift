import AppKit
import Sparkle

/// Sparkle-based updates. Development builds have no `SUPublicEDKey`, so the updater stays off
/// and "Check for Updates" explains where releases come from.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init(isEnabled: Bool) {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = isEnabled && !key.isEmpty
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var isAvailable: Bool {
        controller != nil
    }

    func checkForUpdates() {
        if let controller {
            controller.checkForUpdates(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Updates Are Off in This Build"
        alert.informativeText = """
        This is a development build. Signed releases of Marc update themselves automatically; download them \
        from GitHub Releases.
        """
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "https://github.com/devleloper/Marc/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}
