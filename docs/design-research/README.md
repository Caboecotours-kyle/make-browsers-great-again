# Browser design research, October 2026

What new and enthusiast browsers do with their UI, what people call premium
or cheap, and what MBGA should take from it. Gathered on 2026-10-21 from
official sites, changelogs and GitHub, Product Hunt, Reddit, X and designer
write-ups.

- `notes/` has the detail with a source link for every claim:
  [AI and Arc-lineage browsers](notes/ai-browsers.md),
  [Mac-native and minimal browsers + Apple guidance](notes/mac-native.md),
  [Product Hunt](notes/producthunt.md), [Reddit](notes/reddit.md),
  [X and designers](notes/x-design.md).
- `img/` has 73 screenshots, named `<product>-<what>.webp`, with sources in
  each notes file's Images table.

Gaps: Dribbble and Behance blocked every request and Mobbin needs a login, so
design-gallery coverage is thin. Reddit's API refused requests, so threads
were read through RSS and the Arctic Shift archive, whose scores can lag.
Claims resting on a single forum post or search snippet are marked
"unverified" in the notes.

## The field in October 2026

- **The Arc-style shell lasted, separate AI modes didn't.** OpenAI shut
  ChatGPT Atlas down on 2026-08-09, nine months after launch
  ([TechRadar](https://www.techradar.com/pro/openai-shuts-down-its-atlas-browser-after-not-even-a-year)).
  Microsoft retired Edge's Copilot Mode on 2026-05-13 and folded it into
  normal Edge ([TechRepublic](https://techrepublic.com/article/news-microsoft-retires-copilot-mode-edge)).
  Dia spent 2026 adding Arc's sidebar, pinned tabs, spaces and an Arc importer
  ([changelog](https://www.diabrowser.com/changelog)).
- **Zen is the enthusiast default.** It won r/browsers' 24-round bracket in
  March and shipped sync in September. **Helium** is the year's "just a
  browser" favorite: fast, with uBlock Origin built in. **Arc** gets Chromium
  updates only, and The Browser Company is emailing Arc users to move to Dia.
- **Apple changed course twice.** macOS 26 Tahoe put sidebars in floating
  inset glass. macOS 27, released 2026-09-14, made them edge-to-edge again,
  made the window shape the same in every app, and added a glass-transparency
  slider ([9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/)).
  Kagi Orion 1.1 dropped its own home-made glass, citing "technical and UX
  challenges" ([Orion 1.1](https://orionbrowser.com/updates/versions/1.1)).
- **Indie Arc successors are everywhere,** including native Swift ones close
  to MBGA's stack: Crest (SwiftUI on Chromium), Phi, Mori, Nook, Ora, and
  Search, a 3.7 MB WebKit browser from a Paris design studio. Reddit dismisses
  any that look "vibe-coded" or likely to be abandoned.
- **Ad-blocking is the year's biggest worry,** as uBlock Origin disappears
  from Chromium browsers (Edge dropped it at the end of September).

## What makes a browser feel premium

These principles come up again and again across the five sources.

1. **Speed beats motion.** Actions you do hundreds of times a day (⌘T, ⌘W,
   switching tabs) get no animation at all. Dia's engineers: "Opening and
   closing tabs feels instant."
2. **Native density.** Dia shrank Arc's oversized sidebar to the macOS scale,
   so more tabs and longer titles fit.
3. **The browser recedes and the page leads.** The page sits in a calm,
   inset card. The colour of the chrome comes from the space or the page.
   Structure is felt rather than seen.
4. **Glass only where Apple puts it.** Use the system sidebar and toolbar.
   No glass on glass, and never glass behind web pages; Reddit calls
   transparent pages "cheap" and "illegible".
5. **One motion vocabulary.** Two springs plus a quick fade, used
   everywhere. Search's design file says this is "most of why a thing feels
   like a single piece of software".
6. **Automation you can trust.** Dia's tab clean-up rule: "visible the first
   time, reversible every time, predictable forever."
7. **Forgiving direct manipulation.** A dragged tab stays centred under the
   cursor and turns into a window preview when it leaves the sidebar.
8. **Delight only in rare places.** Onboarding and first-run moments can be
   expressive. Daily paths stay quiet.
9. **Craft in the details.** Concentric corner radii, a hairline instead of
   a border, an active tab you can't miss.

## What to change in MBGA

Ranked by impact on how premium MBGA feels, against what the code does
today.

| # | Change | MBGA today | Proposed | Where |
|---|---|---|---|---|
| 1 | **Page as a card** | Fixed 9 pt radius, 8 pt inset, shadow black 18% r2 | Radius = window radius − inset, read at runtime (it differs between Tahoe and macOS 27); 1 px hairline at primary 8%; shadow black 7% r6 y1; no inset in Focus | `RootView.swift` |
| 2 | **Active tab you can't miss** | White 0.8 in light mode but **0.2 in dark mode**, the same mistake Reddit mocks in Dia | Opaque pill in both modes, medium-weight title, hairline shadow | `Rows.swift` `RowBackground` |
| 3 | **Native density** | 32 pt rows, Arc scale | 28–30 pt rows at the macOS sidebar scale | `Rows.swift` `rowHeight` |
| 4 | **Calmer space colour** | Full-window gradient, same when the window is inactive | Wash the space colour toward `windowBackgroundColor` and fade it further when the window is inactive; text stays monochrome | `Theme.swift` |
| 5 | **One motion vocabulary** | Four unrelated curves: springs (0.28, 0.9), (0.3, 0.9), (0.35, 0.86) and easeOut 0.15 | `quick` easeOut 0.14, `glide` spring(0.34, 0.82), `settle` spring(0.30, 0.86), `fold` spring(0.14, 0.86) out and (0.13, 1.0) back; nothing on ⌘T/⌘W; respect Reduce Motion | new `Motion` in `Theme.swift` |
| 6 | **Sidebar peek that never feels clunky** | 12 pt trigger, closes the moment the pointer leaves | 120 ms intent delay, stays open within width + 24 pt including the screen edge, stays open while a menu is open, Arc/Dia's ~95 ms out / 70 ms back | `RootView.swift` `SidebarPeek` |
| 7 | **Focus mode (⌘S)** | Hiding the sidebar leaves the page in its card | No chrome, page edge-to-edge, traffic lights only on hover, ⌘L opens a floating address field | `RootView.swift`, `AppDelegate.swift` |
| 8 | **Sleeping tabs at about 55%** | Only the favicon dims to 0.5 | Whole row at 55%, plus "Keep this site awake" | `Rows.swift` |
| 9 | **Command bar that does things** | URL or search plus up to 6 open tabs, on `.regularMaterial` | Solid card with a hairline; sections Tabs / Pinned / Spaces / Actions; verbs like "split", "pin", "sleep", "new space"; shortcut chips; ranked by how often you visit; ⌘⏎ forces a search | `CommandBar.swift` |
| 10 | **Favorites in the site's colour** | Active tile white 0.85 | Active tile fills with a colour sampled from the favicon or `theme-color` | `Sidebar.swift` `FavoriteTile` |
| 11 | **Space dots only when they matter** | Always shown | Hidden until a second space exists; only 5.52% of Arc's daily users used several spaces | `Sidebar.swift` `SidebarBottomBar` |
| 12 | **Undo and quiet feedback** | None | ⌘Z with an "Undo" pill for closed tabs, folders and Clear; a "Copied" toast; a mini player card that follows you across spaces | new |
| 13 | **Clean-up you can trust** | Clear archives Today | First time: "Not now / Clean once / Clean daily" card; favicons fly into the archive once; always restorable | `Sidebar.swift` `TodayDivider` |
| 14 | **Forgiving drag** | Standard SwiftUI drag | Row stays centred under the cursor; a haptic tick on drop targets; the row becomes a window preview outside the sidebar | `Rows.swift` |
| 15 | **"Choose a style" in the welcome sheet** | Import only | Sidebar / Compact / Focus previews, changeable later | `Onboarding.swift` |

Items 1–8 are a polish pass of a few hundred lines in `Theme.swift`,
`Rows.swift` and `RootView.swift`, with no core changes.

### Status (2026-10-21)

Built: all 15 items, plus ad and tracker blocking (dealbreaker 1), the
Vivid / Calm / Neutral color setting, Match Page Colour and the Compact rail.

How some of it differs from the research:
- **Item 14:** tabs drag as a compact pill centred under the pointer that
  turns into a little-window preview over the page; dropping it there opens
  the tab in a little window.
- **Mini player equaliser:** drawn by Core Animation in the render server,
  so it costs the app no work per frame.
- **Ad blocker scriptlets:** come from uBlock Origin 1.48, the last release
  in the format Brave's engine reads.

## Avoid

- Glass or transparency behind web content
  (`img/reddit/zen-transparency-everywhere.webp`).
- An active tab that blends into the sidebar
  (`img/reddit/dia-active-tab-indistinct.webp`).
- Thick window borders and big radii; Vivaldi 8's border drew complaints.
- Busy new-tab pages with clocks and widgets, which Reddit calls "bloated".
- Taking over standard macOS or Chrome shortcuts.

## Dealbreakers that matter more than looks

From Reddit, in order of how often they come up:

1. **No uBlock Origin-grade blocking.** Brave's `adblock-rust` is Rust and
   reads uBO/EasyList filters, so it could live in MBGA's core.
2. RAM, heat and battery. This is MBGA's strength; say so.
3. **No Widevine DRM, so no Netflix or Spotify.** Stock CEF builds don't
   include it; check before launch.
4. No sync.
5. No 1Password/Bitwarden or extensions.
6. Looking abandoned or "vibe-coded". A visible changelog, the Chromium
   version in About, and a named maker help.
7. Missing Arc basics: spaces as profiles, nested folders, link routing,
   Peek. Missing import was also on the list, and MBGA now has it.

## Name clash

OMEGA, a Swift + WebKit browser that was #1 of the day on Product Hunt on
2026-01-18, uses "MAKE BROWSERS GREAT AGAIN" as the headline of its gallery
image (`img/producthunt/omega-mbga-headline.webp`). Worth knowing before any
public launch under the MBGA name.

## Gallery

### Page as a card on a coloured window

![Arc](img/ai-browsers/arc-sidebar-zero-chrome.webp)
![Helium](img/mac-native/helium-vertical-rounded-frame.webp)
![Search](img/mac-native/search-officecommun-sidebar.webp)

### Density and the active tab

![Arc vs Dia](img/x-design/dia-sidebar-density-vs-arc.webp)
![Dia active tab](img/reddit/dia-active-tab-indistinct.webp)
![Thravik](img/producthunt/thravik-sidebar-space-dock.webp)

### Colour from the space and the page

![Dia pinned tiles](img/reddit/dia-pinned-tiles-brand-color.webp)
![Thravik appearance](img/producthunt/thravik-appearance-settings.webp)
![Arc theme picker](img/ai-browsers/arc-theme-picker.webp)

### Command bar

![Thravik command bar](img/producthunt/thravik-command-bar.webp)
![Zen command bar](img/x-design/zen-command-bar-action.webp)

### Compact and Focus modes

![Helium frameless](img/x-design/helium-zen-frameless-mode.webp)
![Orion Focus Mode](img/mac-native/orion-focus-mode-border.webp)
![Brave concept](img/x-design/layers-brave-vertical-tabs-concept.webp)

### Trust and small feedback

![Dia clean-up prompt](img/x-design/dia-tab-cleanup-prompt.webp)
![Dia drag preview](img/x-design/dia-tab-drag-window-preview.webp)
![Arc mini player](img/reddit/arc-mini-player.webp)

### Onboarding and settings

![Vivaldi choose a style](img/mac-native/vivaldi-choose-a-style.webp)
![Crest appearance](img/mac-native/crest-appearance-settings.webp)
![Zen routing](img/reddit/zen-smart-routing-settings.webp)

### Apple

![Safari 26](img/mac-native/safari-tahoe-floating-sidebar.webp)
![Safari 27](img/mac-native/safari27-topic-tab-groups.webp)
