# Contributing to Marc

Thanks for helping build Marc. This guide covers how to set up the project, how the code is
organized and what a pull request needs before it can be merged.

By participating you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security
issues privately as described in [SECURITY.md](SECURITY.md), never in a public issue.

## Ground rules

- **Original work only.** Marc reproduces Arc's *interaction model*, not its implementation.
  Do not contribute code, images, icons, sounds, fonts or text taken from Arc or any other
  proprietary product. Measure and describe behavior; then write your own implementation.
- **No dead UI.** Every button, menu item and shortcut must do what it says. If a feature can't
  be finished, leave it out instead of adding a placeholder.
- **Public APIs only.** No private WebKit or AppKit SPI; Marc has to stay buildable and
  notarizable by anyone.
- **Privacy first.** No telemetry, no third-party analytics, no new network endpoints without
  a setting that explains them.

## Setting up

Requirements: macOS 15.4 or later, Xcode 26 and [Homebrew](https://brew.sh).

```bash
git clone https://github.com/devleloper/Marc.git
cd Marc
make bootstrap   # installs XcodeGen, SwiftLint, SwiftFormat and xcbeautify, then generates Marc.xcodeproj
make run         # builds the Debug app and opens it
```

`Marc.xcodeproj`, `Info.plist` and the entitlements file are generated from `project.yml` by
XcodeGen and are not checked in. Run `make project` after pulling changes that touch
`project.yml` or add files to the app target.

Development builds are ad-hoc signed and need no Apple Developer account. Sparkle updates are
off in these builds.

### Useful commands

| Command | What it does |
| --- | --- |
| `make build` | Builds the Debug app. |
| `make run` | Builds and opens the app. |
| `make test-package` | Runs the `MarcKit` unit and integration tests (`swift test`). |
| `make test-ui` | Runs the XCUITest suite against the app. |
| `make test` | Runs both. |
| `make lint` | Checks formatting (SwiftFormat) and style (SwiftLint, strict). |
| `make format` | Formats the code and applies SwiftLint autocorrections. |

The UI tests launch Marc with `-ui-testing`, which uses temporary, in-memory storage and turns
off network-dependent features, so they never touch your real browsing data. They need
permission to control the computer the first time you run them (*System Settings → Privacy &
Security → Accessibility*).

## Where things live

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) before making larger changes. In short:

| Location | Contents |
| --- | --- |
| `Marc/` | The app target: composition root, menus, window management, Sparkle. |
| `Packages/MarcKit/Sources/MarcCore` | Domain model, workspace store, pure rules and importers' parsers. Foundation only. |
| `Packages/MarcKit/Sources/MarcPersistence` | GRDB databases and repositories. |
| `Packages/MarcKit/Sources/MarcWebKit` | Tab runtime, user scripts, content blocking, downloads, extensions. |
| `Packages/MarcKit/Sources/MarcPlatform` | Keychain, authentication, networking and AI providers. |
| `Packages/MarcKit/Sources/MarcDesignSystem` | Design tokens, theme palette, motion and shared components. |
| `Packages/MarcKit/Sources/MarcUI` | Feature views and view models. |
| `MarcUITests/` | End-to-end tests. |
| `design/` | Swift scripts that render the app icons, the disk image background and the social preview. |
| `packaging/dmg/` | Disk image layout (dmgbuild settings and pinned requirements). |
| `docs/` | Architecture, feature inventory, limitations, roadmap and release process. |

Dependency rules are enforced by the package graph: `MarcCore` imports nothing but Foundation
and Observation, and the UI reaches persistence and platform services only through protocols
declared in `MarcCore`.

## Coding guidelines

- **Swift 6 language mode** with strict concurrency. UI and WebKit targets default to the main
  actor; mark work that leaves it explicitly.
- **Business rules go in `MarcCore`** as pure functions or value types, with unit tests.
  Views stay thin.
- **Design tokens, not magic numbers.** Sizes, colors, typography and animation curves come
  from `MarcDesignSystem` (`Metrics`, `Typography`, `Motion`, `ThemePalette`). If you need a
  new value, add a token and note where it was measured.
- **Accessibility.** Give interactive elements labels and identifiers, support keyboard
  navigation, and respect *Reduce Motion* and *Increase Contrast*.
- **Strings** are user-facing English in String Catalog-ready form (`Text("…")`,
  `String(localized:)`); avoid building sentences by concatenation.
- **Errors** are surfaced to the user in plain language or logged with `Logger.marc`; never
  swallowed silently when they affect what the user sees.
- **Formatting** is owned by SwiftFormat and SwiftLint. Run `make format` before committing.

## Tests

- Every bug fix comes with a test that fails without the fix.
- Use Swift Testing (`@Test`, `#expect`, `#require`) in `MarcKit`; XCTest only for UI tests.
- Persistence tests use in-memory databases; WebKit tests may load `data:` URLs but never the
  network.
- UI tests must not depend on the keyboard layout: XCUITest can synthesize some characters with
  modifiers under non-U.S. layouts, so avoid typing the letter "c" in test strings.

## Branches, commits and pull requests

- Branch from `main` using a prefix: `feature/…`, `fix/…`, `refactor/…`, `chore/…`, `docs/…`.
- Write commits in the [Conventional Commits](https://www.conventionalcommits.org) format:
  `feat(sidebar): add folder drag and drop`, `fix(webkit): …`, `docs: …`. Use the module name
  as the scope where it helps (`core`, `persistence`, `webkit`, `platform`, `design-system`,
  `ui`, `app`).
- Keep pull requests focused. Fill in the template, link the issue, and attach before/after
  screenshots or a short recording for visual changes.
- CI must be green: lint, package tests, the app build and UI tests.
- A maintainer reviews every pull request; changes that touch security-sensitive areas
  (autofill, Keychain, navigation policy, extensions, updates) need a second look.

## Versioning and changelog

Marc follows [Semantic Versioning](https://semver.org). User-visible changes get an entry in
the *Unreleased* section of [CHANGELOG.md](CHANGELOG.md), in the
[Keep a Changelog](https://keepachangelog.com) format. Maintainers cut releases as described in
[docs/RELEASING.md](docs/RELEASING.md).

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
