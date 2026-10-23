import AppKit
import Sparkle

/// Sparkle-based updates. Development and preview builds have no `SUPublicEDKey`, so the updater stays off
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
        alert.messageText = "This Build Doesn't Update Itself"
        alert.informativeText = """
        Development and preview builds of Marc can't install updates automatically. Download new versions \
        from GitHub Releases.
        """
        alert.addButton(withTitle: "Open Releases")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn, let url = URL(string: "https://github.com/devleloper/Marc/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}
