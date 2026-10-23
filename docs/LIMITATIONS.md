# Platform Limitations

Marc uses the system WebKit through public APIs only. Arc is built on Chromium, so some of its
capabilities have no public WebKit equivalent. Each limitation below lists the closest safe
alternative Marc implements.

| Area | Limitation | Marc's approach |
| --- | --- | --- |
| Rendering engine | Sites see Safari's engine, not Chromium; Chrome-only features (e.g. some WebUSB/WebHID/WebSerial APIs) are unavailable. | None possible; WebKit is the engine. |
| Web extensions | `WKWebExtension` supports most Manifest V2/V3 APIs but not all Chrome APIs. There is no API to install from the Chrome Web Store. | Install unpacked folders, `.zip` archives and `.crx` files (the CRX header is stripped and the archive verified before loading). |
| Developer tools | No public API opens the Web Inspector programmatically. | Web views are `isInspectable`; *Developer Tools* opens Safari's Web Inspector instructions and *Inspect Element* is available from Safari's Develop menu. *View Source* uses a native viewer. |
| Geolocation prompts | WebKit shows its own permission prompt; there is no public per-site decision delegate on macOS. | Marc provides the location usage description and records nothing; the system prompt handles consent. |
| Web notifications | The Notifications API is not exposed to third-party WebKit apps. | Not supported; documented in Settings. |
| Muting a tab | No public page-mute API. | Media elements are muted from an isolated user script; audio produced by Web Audio may not be muted. |
| Playing-audio indicator | No public "is playing audio" property. | Media events observed by an isolated script, cross-checked with `requestMediaPlaybackState()`. |
| Picture in Picture from the sidebar | Entering PiP programmatically may require a user gesture inside the page. | The mini player offers PiP when WebKit accepts the request; otherwise it focuses the tab. |
| Password autofill | iCloud Keychain / Passwords app data is not available to third-party browsers. | Built-in Keychain-backed manager; third-party managers via web extensions. |
| Passkeys / WebAuthn | Requires a restricted browser entitlement granted by Apple. | Not available in community builds; documented. |
| Cookies import | Other browsers' cookies are encrypted per app and must not be read. | Import covers bookmarks, history and Arc's sidebar structure only. |
| Safari data import | `~/Library/Safari` is protected by privacy controls. | The user selects the file in an open panel (or grants Full Disk Access). |
| Apple Foundation Models | Available on macOS 26 with Apple Intelligence enabled. | Feature-gated; Claude API works on all supported macOS versions. |
| Auto-update & notarization | Requires a Developer ID certificate. | Ad-hoc signed development builds; release workflow activates when signing secrets are configured. |
