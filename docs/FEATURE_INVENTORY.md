# Feature Inventory

This inventory was compiled by studying Arc 1.169 on macOS 26 (menus and shortcuts via the
Accessibility API, geometry via accessibility frames, colors and type sizes via pixel sampling of
Retina screenshots) and from Arc's publicly documented behavior. Arc is used strictly as a
behavioral and visual reference: no code, assets, icons or trademarks are reused.

Status legend: **v1** — in scope for the first release · **later** — planned, not in v1 ·
**limited** — implemented with a documented platform limitation (see [LIMITATIONS.md](LIMITATIONS.md)).

## 1. Window and chrome

| Arc behavior | Observed details | Marc | Status |
| --- | --- | --- | --- |
| Hidden title bar, full-size content | Traffic lights at x=12, centered ~24 pt from the top; no window title | `BrowserWindow` with transparent titlebar, repositioned standard buttons | v1 |
| Sidebar toolbar | Sidebar toggle, back, forward, reload: 32×32 pt hit areas at y=7 | Same layout, SF Symbols | v1 |
| Content "card" | Web content inset 10 pt top/right/bottom, flush with the 250 pt sidebar on the left; continuous corner radius ≈ 7 pt; hairline highlight on window top edge | `ContentCard` design-system component | v1 |
| Space theme behind chrome | Window background is the Space gradient (e.g. `#0E0D20` → `#1B0D20`) with soft color glows | `ThemeBackground` (gradient + optional grain) | v1 |
| Multiple windows, each showing one Space | `New Window ⌘N`, `Close Window ⇧⌘W` | `WindowCoordinator` | v1 |
| Blank Window `⌃⌘N` | Window not bound to a Space ("This Window" section) | Ephemeral window-scoped tab list | v1 |
| Incognito Window `⇧⌘N` | Non-persistent data, distinct styling | Non-persistent `WKWebsiteDataStore`, dark incognito theme | v1 |
| Full screen `⌃⌘F` | — | Native full screen | v1 |
| Sidebar on the right | Preference | Preference | later |

## 2. Sidebar

| Arc behavior | Observed details | Marc | Status |
| --- | --- | --- | --- |
| Width & insets | 250 pt default; rows 234×36 pt at 8 pt inset; row pitch 41 pt | Tokens `Sidebar.width`, `Row.height`, `Row.pitch` | v1 |
| Resizable sidebar | Drag the content edge | Drag handle, min 200 / max 400 pt | v1 |
| Toggle / auto-hide `⌘S` | Hidden sidebar slides over content when the pointer hits the left edge | Overlay sidebar with spring slide + shadow | v1 |
| Address field | Empty: magnifier + "Search or Enter URL…". Loaded: host on line 1, status on line 2 (e.g. "Translation Available"); trailing *Copy URL* and *Site Control Center* buttons (30×30) | `AddressField` opening the inline Command Bar | v1 |
| Favorites | Tile grid at the top, tiles 113×47 pt with 8 pt gaps for 2 items, 18 pt icons, 10 % white fill; shared by all Spaces of a profile | `FavoritesGrid` (adaptive columns, max 4) | v1 |
| Space header | Space name in 13 pt semibold, 45 % white | `SpaceHeader` with rename + context menu | v1 |
| Pinned tabs & folders | Persist across sessions; folders nest and collapse; pinned tab remembers its home URL | `SidebarTree` (pinned section) | v1 |
| Divider with *Clear* | 1 pt line + "Clear" (11 pt semibold, 30 % white) clears Today tabs `⇧⌘K` | `TodayDivider` + sweep animation | v1 |
| `+ New Tab` row | 14 pt label, 50 % white | `NewTabRow` | v1 |
| Today tabs | Newest on top; 16 pt favicon at x=18, title 14 pt at x=44; selected row 20 % white fill, radius ≈ 10 pt; hover shows close button | `TabRow` | v1 |
| Auto-archive | Unpinned tabs archive after 12 h / 24 h / 7 d / 30 d of inactivity | `ArchivePolicy` + background sweep | v1 |
| Drag & drop | Reorder; between Pinned/Today/Favorites; into folders; onto Space icons; out to a new window; onto content to split | `SidebarDropDelegate` + core move rules | v1 |
| Context menus | Copy link, duplicate, pin, add to favorites, move to Space, split with, rename, mute, archive, close below… | `TabContextMenu` | v1 |
| Bottom bar | Library button (left), Space switcher icons 25×34 pt (center), `+` 32×32 (right) | `SidebarFooter` | v1 |
| Swipe between Spaces | Two-finger horizontal swipe, interactive | `SpacePager` with gesture-driven offset | v1 |
| Media mini player | Appears above the footer while a background tab plays media | `MediaMiniPlayer` | limited |
| Download progress | Progress indicator in the footer | `DownloadIndicator` | v1 |
| "New version available" pill | Above the footer | Sparkle-driven update pill | v1 |

## 3. Spaces and profiles

| Arc behavior | Observed details | Marc | Status |
| --- | --- | --- | --- |
| Create Space | Inline sidebar form: icon picker, name, profile picker, *Choose a Theme*, *Create Space* / *Cancel* | `CreateSpaceForm` | v1 |
| Switch Space | `⌃1…⌃9`, `⌥⌘←/→`, footer icons, swipe | `SpaceSwitcher` | v1 |
| Edit theme | Gradient of 1–3 colors, light/dark/auto, grain intensity | `ThemeEditor` (original color-field UI) | v1 |
| Rename / delete / reorder Spaces | Spaces menu, *Manage Spaces…* | `ManageSpacesView` | v1 |
| Profiles | Each Space belongs to a profile; profiles isolate cookies, history, passwords and extensions | One `WKWebsiteDataStore(forIdentifier:)` + one SQLite file per profile | v1 |

## 4. Command Bar and navigation

| Arc behavior | Observed details | Marc | Status |
| --- | --- | --- | --- |
| Command Bar `⌘T` / `⌘L` | Centered panel ≈ 764 pt wide; 20 pt query field; 50 pt result rows; selected row uses the accent fill; info button | `CommandBar` | v1 |
| Results | URL navigation, search, open tabs (switch), history, commands, search suggestions | `CommandBarRanker` (pure, frecency-based) | v1 |
| Site search with Tab | e.g. type a site then Tab to search it | `SearchEngineShortcut` | v1 |
| Back/forward `⌘[` `⌘]`, reload `⌘R`, force reload `⇧⌘R`, stop `⌘.` | — | `WebTab` commands | v1 |
| Next/previous tab `⌥⌘↓/↑`, `⌘1…⌘9` | — | `TabNavigator` | v1 |
| Restore closed tab `⇧⌘T` | — | `RecentlyClosedStack` | v1 |
| Copy URL `⇧⌘C`, as Markdown `⌥⇧⌘C`, as quote `⌃⇧⌘C` | Toast confirmation | `PasteboardService` + `Toast` | v1 |
| Find `⌘F`, next `⌘G`, previous `⇧⌘G` | — | `FindBar` (WebKit find + match counting) | v1 |
| Zoom `⌘+ ⌘- ⌘0` | Per site | `SiteSettings.zoom` | v1 |
| Website appearance | Automatic / Light / Dark | Per-window `NSAppearance` override | v1 |
| Clear cookies/cache and refresh | — | `WebsiteDataCleaner` | v1 |
| Print `⌘P`, Save Page As `⇧⌘S`, Share | — | WebKit print, web archive / PDF, `NSSharingServicePicker` | v1 |
| Developer tools `⌥⌘I`, view source `⌥⌘U` | — | `isInspectable` + Safari Web Inspector; native source viewer | limited |
| Capture `⇧⌘2` | Area / full page capture | Visible-area and full-page snapshot to file/clipboard | later |

## 5. Signature features

| Arc behavior | Marc | Status |
| --- | --- | --- |
| **Split View** `⌃⇧=`, close pane `⌃⇧-`, separate, expand; up to 4 panes; one combined sidebar row | `SplitLayout` (pure tree) + `SplitContainer` with draggable dividers | v1 |
| **Peek**: links from Favorites/Pinned tabs to other hosts open in a floating card that can be expanded into a tab | `PeekPresenter` (navigation policy) + `PeekCard` | v1 |
| **Little Arc** `⌥⌘N`: compact window for links from other apps; "Open in Marc" moves it into a Space | `LittleWindow` + default-browser link routing | v1 |
| **Boosts**: per-site colors, fonts, zapped elements, custom CSS/JS | `Boost` model, isolated-world user scripts, element picker, editor | v1 |
| **Notes** `⌃⇧N`: rich-text notes living in the sidebar | `NoteDocument` (RTFD) rendered natively in the content card | v1 |
| **Library** `⇧⌘L`: Downloads `⇧⌘J`, Archive, Media, Boosts, Notes | `LibraryPanel` (sidebar mode) | v1 |
| **History** `⌘Y` | Native history page, FTS search, range deletion | v1 |
| **Archive** | Archived tabs list with restore and clear | v1 |
| **Arc Max** (AI) | Summarize page, ask the page, tidy tab titles, tidy download names — Claude API or on-device Apple Foundation Models (macOS 26) | v1 |
| Easels | — | not planned |
| Sync | — | later |

## 6. Platform features

| Feature | Marc | Status |
| --- | --- | --- |
| Downloads | `WKDownload`, unique filenames, quarantine, reveal in Finder, resume-less retry | v1 |
| Session restore | Windows, Spaces, selection, back/forward lists via `interactionState` | v1 |
| Site permissions | Camera, microphone, autoplay, pop-ups, external-app links; per-site memory | v1 / limited (geolocation, notifications) |
| Content blocking | Filter lists converted to `WKContentRuleList`, per-site toggle | v1 |
| Web extensions | `WKWebExtensionController` per profile; install from folder, `.zip` or `.crx` | limited |
| Password manager | Keychain-backed, Touch ID gated autofill, generator, isolated content world | v1 |
| Import | Arc (Spaces, pinned, folders, favorites), Chrome (bookmarks, history), Safari (bookmarks, history), HTML bookmarks | v1 |
| Default browser & link handling | `NSWorkspace.setDefaultApplication`, `http/https` URL types | v1 |
| Settings `⌘,` | General, Profiles, Search, Privacy & Security, Passwords, Extensions, AI, Shortcuts, Advanced | v1 |
| Onboarding | Welcome → import → theme → default browser | v1 |
| Auto-update | Sparkle 2 (EdDSA, appcast on GitHub Releases) | v1 |
| Memory saver | Unload inactive tabs, restore via `interactionState` | v1 |

## 7. Keyboard shortcuts (Arc reference)

| Action | Shortcut | | Action | Shortcut |
| --- | --- | --- | --- | --- |
| New tab / Command Bar | `⌘T` | | Toggle sidebar | `⌘S` |
| Open Command Bar on current URL | `⌘L` | | Pin / unpin tab | `⌘D` |
| New window | `⌘N` | | Archive (close) tab | `⌘W` |
| Blank window | `⌃⌘N` | | Close window | `⇧⌘W` |
| Incognito window | `⇧⌘N` | | Restore closed tab | `⇧⌘T` |
| New Little window | `⌥⌘N` | | Clear Today tabs | `⇧⌘K` |
| New note | `⌃⇧N` | | Next / previous tab | `⌥⌘↓` / `⌥⌘↑` |
| Add split | `⌃⇧=` | | Next / previous Space | `⌥⌘→` / `⌥⌘←` |
| Close split pane | `⌃⇧-` | | Switch to Space n | `⌃1…⌃9` |
| Copy URL | `⇧⌘C` | | History | `⌘Y` |
| Copy URL as Markdown | `⌥⇧⌘C` | | Library | `⇧⌘L` |
| Copy URL as quote | `⌃⇧⌘C` | | Downloads | `⇧⌘J` |
| Find / next / previous | `⌘F` / `⌘G` / `⇧⌘G` | | Developer tools | `⌥⌘I` |
| Reload / force reload | `⌘R` / `⇧⌘R` | | View source | `⌥⌘U` |
| Stop loading | `⌘.` | | Zoom in / out / reset | `⌘+` / `⌘-` / `⌘0` |
| Back / forward | `⌘[` / `⌘]` | | Full screen | `⌃⌘F` |
| Save page | `⇧⌘S` | | Print | `⌘P` |
| Preferences | `⌘,` | | Open Little window / Peek in main | `⌘O` |
