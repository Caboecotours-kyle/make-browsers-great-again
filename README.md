<img src="assets/icon.svg" width="64" height="64" alt="">

# make-browsers-great-again

MBGA is a macOS browser with Arc's sidebar, built to use as little memory as
possible. Pages are rendered by Chromium (through the prebuilt Chromium
Embedded Framework), all browser state lives in a Rust core, and the window is
a thin native SwiftUI/AppKit shell.

## Architecture

```
core/          Rust: spaces, profiles, tabs, favorites, pinned folders,
               drag-and-drop moves, persistence, tab sleep policy, omnibox.
               Exposed to Swift through UniFFI.
shell/engine/  Objective-C++ bridge to CEF: app class, per-profile storage,
               one client per tab, popups, downloads, permissions, favicons.
shell/helper/  Entry point of Chromium's subprocesses (renderer, GPU, ...).
shell/app/     SwiftUI/AppKit UI: sidebar, swipeable spaces, command bar.
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
- **Command bar** (⌘T / ⌘L): open a URL, search, or switch to an open tab.
- **Sidebar**: hide it with ⌘S; hovering the left edge slides it back in.

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
keychain.

## Not yet built

- Chrome extensions: CEF's embeddable browser style does not support them.
- Further Arc features: automatic archiving of Today tabs, split view, Peek,
  Little Arc, Boosts, the archive/library view, and multi-color gradient
  themes.
