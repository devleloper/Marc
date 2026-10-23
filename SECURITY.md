# Security Policy

A browser handles passwords, cookies and everything people read and type, so security reports
take priority over all other work.

## Reporting a vulnerability

**Do not open a public issue for a vulnerability.** Report it privately through GitHub:

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability** (GitHub private vulnerability reporting).
3. Describe the issue, the affected version (*Marc → About Marc*), the macOS version and the
   steps to reproduce it. A proof of concept page helps a lot.

You can expect:

- an acknowledgement within **3 business days**;
- an assessment and a planned fix timeline within **10 business days**;
- credit in the release notes and the advisory, unless you prefer to stay anonymous.

Please give us a reasonable time to ship a fix before you disclose the issue publicly. We
coordinate disclosure dates with reporters.

## Supported versions

Marc has no stable release yet. Until 1.0, only the latest release gets security fixes.

| Version | Supported |
| --- | --- |
| latest 0.x release | ✅ |
| older releases | ❌ |

## Scope

In scope:

- The Marc app and the `MarcKit` package in this repository.
- Escaping the per-profile data isolation (cookies, storage, history, passwords or the Keychain
  of one profile readable from another profile or from an incognito window).
- Web content reaching Marc's privileged features: the `marc://` pages, isolated user-script
  worlds, autofill, Boosts, the AI assistant or the extension host.
- Navigation-safety bypasses (for example `javascript:` or `file:` URLs from web content, or
  opening external apps without asking).
- Insecure storage of secrets (passwords or API keys outside the Keychain, secrets in logs).
- Update-channel issues (Sparkle feed, signature verification).

Out of scope (report these upstream instead):

- Bugs in WebKit itself: <https://bugs.webkit.org> or Apple's Security Bounty program.
- Bugs in third-party web extensions that users install.
- Issues that need a compromised macOS account or physical access to an unlocked Mac.

## Security model in brief

- **App Sandbox and hardened runtime.** Marc requests only the entitlements a browser needs:
  outgoing network connections, user-selected files and Downloads, camera and microphone
  (granted per site), location, printing, and the mach-lookup exceptions Sparkle needs.
- **Profile isolation.** Each profile has its own `WKWebsiteDataStore`, its own SQLite
  database and its own Keychain service name. Incognito windows use a non-persistent data store
  and write no history.
- **Secrets.** Saved passwords and the Anthropic API key live in the Keychain only. Filling a
  password always needs a user action and, optionally, Touch ID or the account password.
- **Isolated scripts.** Marc's user scripts run in separate `WKContentWorld`s, so pages cannot
  see or call them. Messages from pages are validated before Marc acts on them.
- **Navigation safety.** Web content cannot open `javascript:`, `file:` or `marc://` URLs.
  Other schemes open external apps only after the user confirms.
- **No telemetry.** Marc sends no analytics. Network requests go to the sites you open, the
  search-suggestion endpoint you choose, filter-list publishers when content blocking is on,
  the Claude API when you enable it, and GitHub for updates.
- **Importers** read bookmarks, history and Arc's sidebar structure only. They never read
  other browsers' cookies or saved passwords.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.
