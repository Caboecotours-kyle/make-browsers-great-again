<img src="assets/icon.svg" width="64" height="64" alt="">

# make-browsers-great-again

MBGA is a macOS browser with Arc's sidebar, built to use as little memory as
possible. Pages are rendered by Chromium (through the prebuilt Chromium
Embedded Framework), all browser state lives in a Rust core, and the window is
a thin native AppKit shell (no SwiftUI: views update only the parts that
changed, lists reuse their rows, and Core Animation does the motion).

## Architecture

```
core/          Rust: spaces, profiles, tabs, favorites, pinned folders,
               drag-and-drop moves, persistence, tab sleep policy, omnibox.
               Exposed to Swift through UniFFI.
shell/engine/  Objective-C++ bridge to CEF: app class, per-profile storage,
               one client per tab, popups, downloads, permissions, favicons.
shell/helper/  Entry point of Chromium's subprocesses (renderer, GPU, ...).
shell/app/     AppKit UI: sidebar (a table per space), swipeable spaces,
               command bar, sheets. The store reports what changed; each
               view redraws only its part.
```

The core owns the data; the shell renders snapshots of it and forwards engine
events back. Nothing in the UI layer keeps browser state of its own.

## What it does

- **Spaces**: swipe between them with two fingers anywhere in the sidebar, or
  press Ctrl+1…9. Each space has a name, an emoji and a color that tints the
  window, blending while you swipe.
- **Profiles**: each space can use its own profile, with separate cookies,
  logins and site data. Spaces that share a profile share their Favorites.
  Spaces with different profiles sit side by side in the same window.
- **Favorites, pinned tabs and folders**: favorites form the grid at the top,
  pinned tabs and nested folders are kept per space, and Today tabs sit below
  the divider. Closing a pinned tab unloads it and resets it to its pinned URL,
  as in Arc. "Clear" archives all Today tabs.
- **Drag and drop**: reorder tabs, drop them into folders, onto the favorites
  grid or onto another space's icon. Links dragged in from pages or other apps
  open as tabs.
- **Command bar** (⌘T / ⌘L): open a URL or search, switch to an open tab or
  a space, run a command ("pin", "clear", "focus", "new space"…), or reopen a
  closed tab. Pages you visit often come first (a small local history, which
  Clear History in the bar forgets). ⌘↩ always searches the web.
- **Layouts**: the full sidebar, a Compact rail of favicons, or Focus mode
  (⌘S), where the page fills the window but for a thin frame. In the last
  two, resting the pointer at the left edge slides the sidebar out over the
  page; in Focus the traffic lights appear at the top-left corner.
- **Little windows**: drag a tab from the sidebar onto the page (or choose
  Open in Little Window) to give it a small window of its own. It stays in
  its space and never sleeps while open; Open in Sidebar puts it back.
- **Windows**: File ▸ New Window (⌘N) opens another window on the same
  spaces and tabs, as in Arc. Each window has its own space and tab; a page
  shows in one window at a time, so choosing a tab another window shows
  moves it over, and that window offers to show it again.
- **Undo**: closing a Today tab, Clear and deleting a folder can be undone
  with ⌘Z (when no page or text field takes it), ⇧⌘T or the toast's Undo.
- **Tidying up**: when old Today tabs pile up, MBGA offers once to archive
  those untouched for 12 hours, now or every day (Tabs ▸ Archive Unused
  Today Tabs). Archived tabs can always be reopened.
- **Ad and tracker blocking**: EasyList, EasyPrivacy and uBlock Origin's
  filter and privacy lists, matched by Brave's engine in the Rust core,
  cancel requests before they load. Pages also get hiding rules (site-
  specific, and generic ones for the class and id names a page uses) and
  uBlock Origin's scriptlets. The lists refresh every few days; the address
  field shows how much was blocked. Add your own rules with MBGA ▸ Edit My
  Filters…, turn blocking off per site from the tab's menu, or entirely from
  the MBGA menu.
- **Extensions**: Chrome extensions from the Chrome Web Store. MBGA ▸
  Extensions… (or Settings ▸ Privacy, the command bar, or the puzzle piece
  in the sidebar's toolbar) opens Chrome's own window for the space's
  profile, where chrome://extensions and Web Store installs work; typing
  those addresses or following a Web Store link opens it too. Installed
  extensions run in all of the profile's tabs at once: content scripts,
  network rules, background workers, and the tabs and windows APIs see
  MBGA's tabs (which tab is active, tab events, opening and closing tabs).
  Their buttons sit in the sidebar's toolbar with their badges and popups,
  their items in the page's menu, their shortcuts work, and their options
  open in a tab. Manifest V2 extensions (classic uBlock Origin) no longer
  load in Chromium; uBlock Origin Lite does.
- **Media**: a tab playing sound shows an equaliser, and out of sight a mini
  player at the bottom of the sidebar. Right-click a tab to keep its site awake (never
  slept or frozen) or to put it to sleep now.
- **Look**: the page sits in a card whose corners follow the window's; space
  colors are a calm wash that fades when the window is inactive (View ▸
  Sidebar Colour: Vivid, Calm or Neutral, or Match Page Colour to take each
  site's theme color); the selected favorite lights up in its site's color. The welcome sheet ends with a choice of layout and color.
- **Import from other browsers**: at first launch (and from File ▸ Import from
  Another Browser…) MBGA lists the browsers it finds on the Mac and what each
  would bring. From Arc it takes spaces with their icons, colors and profiles,
  pinned tabs and folders, favorites and Today tabs. From Chrome, Helium,
  Brave, Edge, Vivaldi, Opera and any other Chromium-based browser it takes
  each profile's bookmarks, pinned tabs and open tabs. From Firefox (and Zen,
  LibreWolf, Waterfox) and Safari it takes bookmarks; Safari needs Full Disk
  Access. Every source profile becomes an MBGA profile with its own space, and
  bookmarks land in folders under its pinned tabs. Nothing loads until opened.
- **Passwords**: saved passwords come along from Chrome-family browsers, Arc
  and Firefox (macOS asks before MBGA reads a Chromium browser's keychain key;
  a Firefox Primary Password needs an export instead). Safari's, and any
  password manager's, come from the CSV file they export (Settings ▸
  Passwords ▸ Import a File…). MBGA offers them under a site's username or
  password field, fills the one you pick, and offers to save new ones once a
  sign-in goes through. They stay per profile, sealed with a key in your
  keychain; showing or copying one in Settings asks for Touch ID or your
  Mac's password.

## Memory

Measured against Chrome 155 on 3 profiles and 50 real sites, with every tab
loaded (method and tools in [`bench/`](bench/README.md)):

| | Chrome | MBGA, sleeping off | MBGA, defaults |
|---|---:|---:|---:|
| Memory, all 50 tabs loaded | 4,320 MB | 2,122 MB (49%) | 900 MB (21%) |
| Memory after 12 idle minutes | 4,302 MB | 2,116 MB (49%) | 681 MB (16%) |
| Idle CPU after 12 minutes | 18.4% | 0.4% | 0.2% |
| Idle power after 12 minutes | 202 mW | 3 mW | <1 mW |
| Memory 90 s after restoring the session | 1,659 MB | 254 MB | – |

"Sleeping off" keeps every tab loaded, so it compares the engines like for
like. With the defaults, idle tabs are also unloaded.

What MBGA does, roughly in order of impact:

- **Shared renderer processes.** Like Chrome on Android, sites share four
  renderer processes instead of one each. Sign-in pages (Google, Microsoft,
  Apple, GitHub, Facebook, PayPal) and sites that ask for isolation (COOP
  headers) keep their own. Turn on **MBGA ▸ Strict Site Isolation** for
  desktop Chrome's one-process-per-site model, the strongest protection
  against one site reading another's memory (Spectre-class attacks). It uses
  about 30% more memory (2.8 GB instead of 2.2 GB in the test above, still a
  third less than Chrome).
- **Tabs sleep.** A background tab idle for 10 minutes, or beyond 8 loaded
  tabs, is unloaded and reloads when selected. Tabs playing audio or using the
  camera, microphone or screen stay awake. Under system memory pressure the
  limits tighten.
- **Today tabs freeze.** A Today tab hidden for a minute is frozen: it keeps
  all its state but runs no JavaScript until shown again. Pinned tabs and
  favorites (usually mail, chat and other apps) keep running so their
  notifications work.
- **Hidden renderers purge.** Renderers whose pages are hidden, or one of
  whose pages froze, release caches, collect garbage and return free memory.
- **Leaner engine.** The network service runs in the browser process, HTTP/3
  is off (its connection buffers cost ~80 MB), Blink and V8 run in low-memory
  mode, cached scripts aren't pinned in memory, off-screen tiles are released
  when idle, and there is no spare renderer, prerendering or optimization-hint
  fetching.
- **Lazy loading.** After a restart only the visible tab loads, and links
  opened in the background load when first shown.

The costs: shared processes weaken the isolation between sites in the same
process and let one heavy page slow others in its process; low-memory V8 runs
heavy JavaScript somewhat slower; frozen Today tabs don't update in the
background.

Run `scripts/measure-memory.sh` while the browser is open to see each
process's physical footprint, the figure Activity Monitor reports.

## Building

Requirements: macOS 15+ on Apple silicon, Xcode, Rust (`rustup`), CMake.

```sh
scripts/build.sh          # downloads CEF (~130 MB) on first run, then builds
scripts/build.sh --run    # build and launch
```

The app is written to `build/cmake/out/MBGA.app`. Browser data lives in
`~/Library/Application Support/MBGA`. Run the core's tests with
`cargo test --manifest-path core/Cargo.toml`.

Development builds are ad-hoc signed and use Chromium's mock keychain, which
avoids a keychain prompt on every rebuild. Configure with
`-DMBGA_MOCK_KEYCHAIN=OFF` for a release that encrypts cookies with the real
keychain. With the mock keychain, the key sealing saved passwords sits in
`passwords.key` in the data folder rather than in the keychain.

## Not yet built

- Chrome extensions: CEF's embeddable browser style does not support them.
- Importing history, and open tabs from Firefox and Safari.
- Passwords in cross-site frames, generated passwords and passkeys.
- Further Arc features: split view, Peek, Little Arc, Boosts, link routing to
  spaces, the archive/library view, and multi-color gradient themes.
- Scriptlets newer than uBlock Origin 1.48 (the last release in the format
  the engine reads), redirect resources (such rules just block), and sync.
