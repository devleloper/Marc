# Roadmap

Milestones are delivered in order; every milestone ends with a building app, green tests and
clean lint.

## Definition of done (every feature)

- The feature works end to end in the running app — no placeholder buttons or stub handlers.
- Business rules live in `MarcCore` and are covered by unit tests.
- Persistence and platform adapters have integration tests.
- Keyboard shortcut, menu item and context menu entries exist where Arc has them.
- Light and dark appearance, VoiceOver labels and reduced-motion behavior are handled.
- `swiftformat --lint`, `swiftlint --strict` and the full test suite pass.

## M0 — Foundation

XcodeGen project, `MarcKit` package with module boundaries, lint/format configuration, CI
workflow, repository documents.

## M1 — Browser core

Profiles with isolated data stores, `WebTab` runtime, URL input classification, navigation
safety, back/forward/reload/stop, multiple windows, content card chrome, session restore.

## M2 — Arc shell

Sidebar (address field, favorites, Space header, pinned tree with folders, today tabs, footer),
Spaces with themes, Command Bar with ranking, drag and drop, context menus, auto-archive,
sidebar auto-hide, Space swiping.

## M3 — Browser services

History with FTS search, downloads, site permissions and Site Control Center, per-site zoom and
appearance, find in page, printing/saving/sharing, recently closed tabs, memory saver,
Settings window, onboarding, default-browser handling.

## M4 — Signature features

Split View, Peek, Little window, Boosts, Notes, Library (downloads, archive, media, boosts,
notes), media mini player.

## M5 — Extended platform

Content blocker, web extensions, password manager, importers (Arc, Chrome, Safari, HTML), AI
features (Claude API and on-device models), Sparkle updates.

## M6 — Polish and release readiness

Motion tuning against the reference, accessibility audit, performance pass (launch time, memory
with many tabs), UI tests, release workflow with signing and notarization.

## Later

Sidebar on the right, Easels-like canvas, sync between Macs, page capture tool.
