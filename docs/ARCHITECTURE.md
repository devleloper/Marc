# Architecture

Marc is a native macOS browser built with Swift 6, SwiftUI, AppKit and WebKit. The codebase is
split into a thin application target (the composition root) and a local Swift package,
`MarcKit`, whose targets enforce the dependency rules below at compile time.

## Layers

```
                ┌──────────────────────────────────────────┐
                │ Marc (app target)                        │
                │ AppDelegate · menus · windows · DI       │
                └──────────────┬───────────────────────────┘
                               │
     ┌─────────────────────────┼──────────────────────────────┐
     ▼                         ▼                              ▼
┌──────────┐   ┌───────────────────────────┐   ┌─────────────────────────┐
│ MarcUI   │──▶│ MarcDesignSystem          │   │ Infrastructure          │
│ features │   │ tokens · components ·     │   │ MarcPersistence (GRDB)  │
│ (SwiftUI │   │ motion · theming          │   │ MarcWebKit (WebKit)     │
│ + AppKit)│   └───────────────────────────┘   │ MarcPlatform (Keychain, │
└────┬─────┘                                   │ network, AI, system)    │
     │                                         └───────────┬─────────────┘
     │            ┌──────────────────────────┐             │
     └───────────▶│ MarcCore                 │◀────────────┘
                  │ domain model · ports ·   │
                  │ use cases · pure rules   │
                  └──────────────────────────┘
```

| Target | Responsibility | May import |
| --- | --- | --- |
| `MarcCore` | Entities, value types, repository/service protocols (ports), stores and use cases, pure rules (URL classification, navigation safety, ranking, archive policy, split layout, filter-list conversion, importers' parsers). | Foundation, Observation |
| `MarcPersistence` | GRDB implementations of the persistence ports; schema and migrations; readers for other browsers' SQLite files. | MarcCore, GRDB |
| `MarcWebKit` | Everything that touches WebKit: tab runtime, per-profile web contexts, user scripts, content blocking, downloads, permissions, web extensions. | MarcCore, WebKit, AppKit |
| `MarcPlatform` | Keychain, LocalAuthentication, networking (search suggestions, filter lists, Claude API), Apple Foundation Models, default-browser registration, settings storage. | MarcCore, Security, LocalAuthentication, FoundationModels |
| `MarcDesignSystem` | Design tokens, theme palette derivation, motion primitives, reusable views. No domain knowledge. | SwiftUI, AppKit |
| `MarcUI` | Feature views and view models: window, sidebar, Command Bar, content area, split, Peek, Library, history, notes, boosts, settings, onboarding. | MarcCore, MarcDesignSystem, MarcWebKit |
| `Marc` (app) | Composition root: builds concrete dependencies, owns window controllers, main menu, URL/Apple Event handling, Sparkle. | everything |

`MarcUI` depends on `MarcWebKit` directly because a `WKWebView` *is* a view: hiding it behind
a protocol would add indirection without decoupling anything. All persistence, networking and
security services reach the UI only through `MarcCore` protocols, so features are testable with
in-memory fakes.

## State management

- **Single source of truth.** `WorkspaceStore` (`@MainActor @Observable`, in `MarcCore`) owns
  the `Workspace` value: profiles, Spaces, and the sidebar tree (favorites, pinned items,
  folders, split groups, today tabs). Views read it; they never mutate it directly.
- **Pure mutations.** Every intent (`pin`, `move`, `archive`, `createSplit`, …) is implemented as
  a pure function on `Workspace` in `WorkspaceMutations`. The store applies the function, diffs
  the old and new values by item identity and hands the change set to `WorkspaceRepository`,
  which persists it off the main actor. Mutations are unit-tested without any I/O.
- **Runtime state stays in the runtime.** Loading progress, titles, favicons, media state and
  navigation history live in `WebTab` (`MarcWebKit`). The store only receives debounced
  snapshots (URL, title, favicon URL) worth persisting.
- **Per-window state.** `WindowState` (current Space, selection per Space, sidebar visibility and
  width, frame) is a value owned by each window's model and persisted for session restore.

## Profiles and data isolation

Each profile gets:

- its own `WKWebsiteDataStore(forIdentifier:)` (cookies, local storage, caches, service
  workers are isolated by WebKit);
- its own SQLite file (`Profiles/<id>/Profile.sqlite`) for history, downloads, site
  permissions and per-site settings;
- its own Keychain service namespace for saved passwords;
- its own `WKWebExtensionController` configuration.

Deleting a profile removes its data store, database folder and Keychain items. Incognito windows
use `WKWebsiteDataStore.nonPersistent()` and never write history.

The global database (`Marc.sqlite`) stores only structure that spans profiles: profiles, Spaces,
the sidebar tree, archive, boosts, notes and window sessions.

## Tab lifecycle

1. A sidebar tab is a persisted `SidebarItem`; it has no web view until it is first shown.
2. `TabRuntimeRegistry` creates a `WebTab` on demand with a configuration built by the tab's
   profile context (data store, content rules, user scripts, extension controller).
3. Inactive tabs are unloaded by the memory saver after a configurable interval. Before the
   `WKWebView` is released its `interactionState` (back/forward list) is kept, so reloading the
   tab restores history.
4. Closing a today tab archives it; closing a pinned tab only unloads it.

## Security model

- **URL safety.** `NavigationSafetyPolicy` classifies every navigation: web schemes load in the
  tab, known external schemes (mailto, tel, app links) require confirmation before handing off to
  `NSWorkspace`, and `javascript:`/top-level `data:` navigations not typed by the user are
  blocked.
- **Isolated scripts.** Marc's own user scripts (password autofill, boosts, media observation,
  favicon discovery) run in a dedicated `WKContentWorld`, so page scripts cannot call Marc's
  message handlers. Handlers validate the sending frame's security origin.
- **Secrets.** API keys and passwords are stored only in the Keychain (generic password items,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). Password autofill always requires an explicit
  user action and, optionally, Touch ID.
- **Downloads.** Files are written to the user's Downloads folder with unique names and quarantine
  attributes; nothing downloaded is ever opened automatically.
- **Sandbox.** The app is sandboxed with the minimum entitlements: network client, user-selected
  and Downloads file access, camera, microphone, location and printing.

WebKit, not Marc, is responsible for process isolation, site isolation and the JavaScript
sandbox. Marc does not claim protections beyond what WebKit provides (see
[LIMITATIONS.md](LIMITATIONS.md)).

## Concurrency

The package uses Swift 6 language mode with complete concurrency checking. UI-facing types are
`@MainActor`; `MarcUI` sets main-actor default isolation. Database access goes through GRDB's
`DatabasePool` (concurrent reads, serialized writes) from `async` repository methods. Network
clients are `Sendable` structs over `URLSession`.

## Testing strategy

| Level | Tooling | Scope |
| --- | --- | --- |
| Unit | Swift Testing | `MarcCore` rules and stores with in-memory fakes; design-system color math |
| Integration | Swift Testing | GRDB repositories on temporary databases; WebKit tabs loading local HTML; Keychain store; importers against synthetic fixtures; HTTP clients over a stub `URLProtocol` |
| UI | XCUITest | Launch, Command Bar navigation, tab and Space management, split view, settings |

## Directory layout

```
Marc/                     App target (composition root)
Packages/MarcKit/         Local package with all modules and their tests
MarcUITests/              XCUITest target
docs/                     Architecture, inventory, roadmap, limitations
Scripts/                  Bootstrap, lint, format and release helpers
.github/                  CI workflows, issue and PR templates
project.yml               XcodeGen specification (the .xcodeproj is generated)
```
