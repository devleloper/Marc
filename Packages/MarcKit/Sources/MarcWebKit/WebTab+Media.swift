import Foundation
import os
import WebKit

/// Media controls for the mini player and automatic Picture in Picture. They call into the page
/// script (PageObserver.js) in Marc's isolated content world.
public extension WebTab {
    func setMuted(_ muted: Bool) {
        media.isMuted = muted
        run("window.__marcSetMuted && window.__marcSetMuted(muted)", arguments: ["muted": muted])
    }

    func togglePlayback() {
        run("return window.__marcTogglePlayback ? window.__marcTogglePlayback() : 'none'")
    }

    func togglePictureInPicture() {
        pictureInPicture("toggle")
    }

    func enterPictureInPicture() {
        pictureInPicture("enter")
    }

    func exitPictureInPicture() {
        pictureInPicture("exit")
    }

    /// Runs the page script with a user gesture (WebKit grants one to app-initiated scripts) and
    /// logs the outcome, so a site that refuses Picture in Picture shows up in Console.
    private func pictureInPicture(_ mode: String) {
        guard let webView else { return }
        let logger = logger
        webView.callAsyncJavaScript(
            "return window.__marcPictureInPicture ? await window.__marcPictureInPicture(mode) : 'unavailable'",
            arguments: ["mode": mode],
            in: nil,
            in: .marc,
        ) { result in
            switch result {
            case let .success(outcome):
                logger.info("Picture in Picture (\(mode, privacy: .public)): \(String(describing: outcome), privacy: .public)")
            case let .failure(error):
                logger.error("Picture in Picture (\(mode, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
