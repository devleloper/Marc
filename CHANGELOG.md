# Changelog

All notable changes to Marc are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Marc
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first public version will be 0.1.0.

### Added

- **Browser core:** WebKit tabs with back/forward, reload, stop, zoom, find in page, printing,
  saving pages, sharing, View Source and Web Inspector support; multiple windows; session
  restore; tab unloading for inactive tabs.
- **Sidebar:** address field, favorites grid, pinned tabs with nested folders, today tabs with
  auto-archive, drag and drop, context menus, hide/reveal with ⌘S and edge hover.
- **Spaces:** themed Spaces with gradient and grain, an icon picker and a theme editor; swiping
  between Spaces; ⌃1–⌃9 shortcuts; profiles with isolated cookies, storage, history and
  passwords.
- **Command Bar:** search, URLs, open tabs, history, commands and site search, ranked by
  frecency; search suggestions.
- **Split View** with up to four panes, **Peek** for links to other sites opened from pinned
  tabs and favorites, a small **Little window** for links opened from other apps, and
  **incognito** windows.
- **Boosts:** per-site colors, fonts, custom CSS and JavaScript, and an element zapper.
- **Notes** and a **Library** with downloads, archived tabs, Boosts and notes.
- **Media mini player** for tabs playing audio or video.
- **Content blocking** with EasyList, EasyPrivacy and Fanboy's Annoyance List, compiled into
  WebKit content rules, plus per-site exceptions.
- **Web extensions** through `WKWebExtension`: install unpacked folders, `.zip` and `.crx`
  files; toolbar actions and permissions.
- **Password manager** backed by the Keychain, with autofill offers, a password generator and
  optional Touch ID before filling.
- **Import** from Arc (sidebar structure, Spaces and pinned tabs), Chrome (bookmarks and
  history), Safari (bookmarks and history) and HTML bookmark files.
- **AI features:** page summaries, questions about the page and tidy tab titles, powered by
  the Claude API (key stored in the Keychain) or on-device Apple Foundation Models.
- **Settings** for search engines, privacy, appearance, shortcuts, passwords, AI, extensions
  and profiles; onboarding; default-browser registration.
- **App icon** in two styles, the white Marc tile and the dark Aurora tile, chosen in Settings ›
  General or matched to light and dark appearance.
- A **disk image** with a designed window: background, arrow and Applications shortcut.
- **Updates** through Sparkle in signed releases.
- Unit, integration and UI tests; CI and release workflows. Releases are ad hoc-signed previews
  until Developer ID signing is configured.

### Changed

- Switching tabs is instant: the last few pages stay in the window, hidden, instead of being
  rebuilt by WebKit each time you come back.
- The sidebar shows and hides faster (0.2 s).
- Buttons sink slightly when pressed and spring back, as in Arc.
- The sidebar slides in and out smoothly, with the page following it and the traffic lights
  fading along.
- Two-finger swipes switch Spaces only over the sidebar; over a page they go back and forward.
- Pages load sooner: Marc looks up the address of a hovered link or the selected Command Bar
  result in advance (Settings › Privacy › Faster loading) and no longer re-sends content-blocking
  rules on every navigation. A thin bar shows loading progress at the top of the page.

### Added

- **Translucency** for Space themes: a slider in the theme editor lets the desktop show through
  the window's background; pages stay opaque.
- **Automatic Picture in Picture**: a video playing in the tab you leave moves into Picture in
  Picture and comes back when you return (Settings › General).
- Clicking into a split pane makes it the active pane.

### Fixed

- Dragging a tab onto a page opens a split again; the page used to take the drop.
- Splitting while a favorite is selected opens the favorite's page in Today and splits it.
- Picture in Picture falls back to WebKit's presentation modes when the standard API refuses.
- Keyboard-focus rings no longer linger on buttons and fields after clicking them.
- Drop indicators in the sidebar no longer stay on screen after a drag.
- In full screen, the sidebar toolbar no longer leaves an empty gap for the hidden traffic lights.
