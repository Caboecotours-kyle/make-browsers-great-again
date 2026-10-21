# Mac-native, minimal and enthusiast browsers: design research for MBGA

Researched 2026-10-21. Covers Safari 26/27, Apple's Liquid Glass guidance, Kagi Orion, SigmaOS, Zen, Helium, Vivaldi, Floorp, Ladybird, Min and the native Swift Arc-likes (Nook, Ora, Search, Crest, Phi, Web, chromeless). Every claim has a source link. "Observed" means I read it off a screenshot, not off text. Things I could not confirm are marked **unverified**.

**Context to keep in mind:** macOS 27 "Golden Gate" shipped on **September 14, 2026** ([MacTrast](https://www.mactrast.com/2026/09/apple-announces-27-operating-systems-public-release-date/)). It moved sidebars back from Tahoe's floating, inset glass panes to **edge-to-edge sidebars** and made window corner radii uniform ([9to5Mac, 2026-06-09](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/), [apple.com/os/macos](https://www.apple.com/os/macos/)). MBGA has to look right on both Tahoe and Golden Gate.

---

## 1. Safari 26 (macOS Tahoe), with notes on Safari 27

- **Platform / engine:** macOS-only (also iOS/iPadOS), WebKit. Safari 26 shipped with macOS Tahoe 26 in September 2025 (announced 2025-06-09). Safari 27 shipped with macOS 27 on 2026-09-14.
- **Layout and tab model:**
  - Apple: "a rounded tab design that floats in the toolbar, along with a refreshed sidebar". The sidebar gained sections for saved content such as iCloud Tabs ([Apple Newsroom, 2025-06-09](https://www.apple.com/newsroom/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/)).
  - Tabs look like rounded "sunken pills" in a slot above the page, which makes the active tab easier to spot ([MacStories Tahoe review, p.2](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/2/)).
  - The active-tab cue changed during beta. An underline on *inactive* tabs confused people, and beta 4 replaced it with a color fill ([MacRumors review, 2025-08-01](https://www.macrumors.com/2025/08/01/macos-tahoe-review)).
- **Compact tab bar:** removed in 26.0, so Safari had a separate toolbar above a separate tab strip ([allthings.how, 2025-09-16](https://allthings.how/safaris-compact-tabs-removed-on-macos-26-and-ipados-26-what-changed/)). It came back in **26.4** after user complaints, as an optional "single row encompassing address bar, current tabs, and more" ([9to5Mac, 2026-03-26](https://9to5mac.com/2026/03/26/macos-tahoe-26-4-and-ipados-26-4-add-compact-tab-bar-in-safari/)).
- **Chrome and materials:**
  - The toolbar and sidebar are more translucent than in Sequoia. Toolbar buttons sit in always-visible groups (Sequoia only showed them on hover) that are more opaque than the space around them. Extension buttons are grouped into one piece. Window corners are rounder ([MacStories](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/2/)).
  - Observed in `safari-tahoe-floating-sidebar.webp`: the sidebar is an inset, rounded pane floating inside the window. The page scrolls under the toolbar and favorites bar, softened by the scroll-edge effect. Web content sits beside the sidebar, never under it.
  - Observed in `safari-tahoe-grouped-toolbar.webp`: with one tab open there is no tab strip. Controls form three glass capsules (sidebar+menu, back/forward, share/new/tabs) around a centred address field.
- **Theming:** macOS 26.1 added a Liquid Glass setting: default "clear" or a new "tinted" look with more opacity ([Apple Support 122868](https://support.apple.com/en-us/122868)). macOS 27 replaced it with a slider "from ultraclear to fully tinted" ([apple.com/os/macos](https://www.apple.com/os/macos/)).
- **Safari 27 / macOS 27:**
  - "Uniform toolbars, edge-to-edge sidebars, and updated window shapes" ([apple.com/os/macos](https://www.apple.com/os/macos/)).
  - Tabs "can be automatically grouped into topics". Apple's image (`safari27-topic-tab-groups.webp`) shows collapsed groups as capsules with counts ("Coffee 7 >"), the active tab as a raised pill, and the toolbar and tab strip **tinted with the page's colour**.
  - 9to5Mac: window corner radius is now the same in every app, sidebar icon colour is back, and the active window stands out more ([9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/)).
- **Praise and complaints:**
  - MacStories liked the Safari/Finder approach of opaque buttons on translucent bars. Its main legibility complaints were about Music and Photos ([MacStories](https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/2/)).
  - MacRumors: "the glass parts of the interface feel cobbled together with the previous design language". A commenter complained that "all of the icons in the Safari and Finder toolbars have giant circles around them" ([MacRumors](https://www.macrumors.com/2025/08/01/macos-tahoe-review)).
  - On AI tab grouping, a commenter on Michael Tsai's blog asked: "Does anyone actually want an LLM to organize their tabs?" ([mjtsai.com, 2026-06-12](https://mjtsai.com/blog/2026/06/12/safari-27-announced/)).
- **Idea for MBGA:** copy Safari's grouping discipline: at most three glass groups, with the address field as its own element. Build the sidebar as a real `NSSplitViewController` sidebar item so it floats inset on Tahoe and runs edge-to-edge on Golden Gate for free. Keep the CEF view beside the sidebar, not under it.

## 2. Apple guidance (HIG + WWDC25/26): rules for a native shell

HIG text was pulled from Apple's HIG JSON on 2026-10-21. The change logs show sidebars updated **2026-06-08**, toolbars 2025-12-16, materials 2025-09-09, scroll views 2026-06-08 and layout 2026-09-09.

**Layering and material**
1. **Glass is for the navigation/control layer only.** "Don't use Liquid Glass in the content layer." "Use Liquid Glass effects sparingly … Limit these effects to the most important functional elements" ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)).
2. **Regular vs clear.** Use *regular* for anything text-heavy: "alerts, sidebars, or popovers". Use *clear* only over media, and when the content underneath is bright, add "a dark dimming layer of 35% opacity" ([HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials)).
3. **Larger glass is more opaque.** "Liquid Glass appears more opaque in larger elements like sidebars". Toolbar symbols are monochrome by default and flip light/dark with the content underneath ([HIG Color](https://developer.apple.com/design/human-interface-guidelines/color)).
4. **Don't paint toolbar backgrounds.** "Reduce the use of toolbar backgrounds and tinted controls … use the content layer to inform the color and appearance of the toolbar, and use a ScrollEdgeEffectStyle when necessary" ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
5. **Use the system sidebar, not a visual-effect view.** On Tahoe, sidebars are "a pane of glass that floats above the window's content". Use `NSSplitViewController`. "If you're using an NSVisualEffectView … it will prevent the glass material from showing through. You should remove these visual effect views." Set `splitViewItem.automaticallyAdjustsSafeAreaInsets = true` on the content item to extend it under the sidebar ([WWDC25-310](https://developer.apple.com/videos/play/wwdc2025/310/)).
6. **Inactive windows drop materials.** Inactive windows "don't use materials … which makes them appear subdued". Custom chrome has to copy this itself ([HIG Windows](https://developer.apple.com/design/human-interface-guidelines/windows)).

**Toolbars**
7. **At most three groups.** "Minimize the number of groups … aim for a maximum of three." Don't put a text-labelled button next to a symbol button. Leading edge: back and show/hide sidebar. Trailing edge: items that must always stay visible ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
8. **No borders on symbols.** "Prefer system-provided symbols without borders … Borders (like outlined circle symbols) aren't necessary because the section provides a visible container." Only one `.prominent` (tinted) action, and it goes on the trailing side ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
9. **Automatic grouping, with escape hatches.** AppKit groups same-type buttons onto one piece of glass automatically. Override with `NSToolbarItemGroup` or spacers. Remove glass from non-interactive items with `isBordered = false`. Badges use `NSItemBadge` ([WWDC25-310](https://developer.apple.com/videos/play/wwdc2025/310/)). SwiftUI equivalents: `ToolbarSpacer(.fixed/.flexible)` and `.sharedBackgroundVisibility(.hidden)` ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)).
10. **Every toolbar item also needs a menu command.** "Make every toolbar item available as a command in the menu bar" ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
11. **Hiding chrome is allowed, with a way back.** "Consider temporarily hiding toolbars for a distraction-free experience … offer ways to reliably restore hidden interface elements" ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).

**Shape, corners, sizing**
12. **Concentric corners.** There are three shape types: fixed, capsule, and concentric ("radius calculated by subtracting padding from parent"). On Mac, controls near a window edge should be concentric ([WWDC25-356 notes](https://wwdcnotes.com/documentation/wwdc25-356-get-to-know-the-new-design-system/)). In SwiftUI: `.rect(corner: .containerConcentric)`. In AppKit: `layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))` (the `NSView.LayoutRegion` API) keeps content clear of window corners ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/), [WWDC25-310](https://developer.apple.com/videos/play/wwdc2025/310/)).
13. **Window radius depends on window type.** On Tahoe, toolbar windows have a larger radius that wraps concentrically around the glass toolbar, and titlebar-only windows keep a smaller one. Large corners "can also clip content that sits close to the edge" ([WWDC25-310](https://developer.apple.com/videos/play/wwdc2025/310/)). macOS 27 makes the radius uniform across apps ([9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/)). **Read the radius from the system. Never hard-code it.**
14. **Controls got taller.** Mini, small and medium controls are "slightly taller". Mini to medium stay rounded rectangles, while large and extra-large become capsules. Don't hard-code heights. `prefersCompactControlSizeMetrics` restores the old metrics for dense UI ([WWDC25-310](https://developer.apple.com/videos/play/wwdc2025/310/)).
15. **Group neighbouring glass.** Glass can't sample other glass. Put nearby glass in a `GlassEffectContainer` / `NSGlassEffectContainerView`, and use `glassEffectID` for morphing ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)).

**Scroll edge, sidebar content, symbols, type**
16. **Scroll-edge effect rules.** Prefer the automatic style. "Only use a scroll edge effect when a scroll view is behind floating interface elements." Use one per view. In split views, give each pane its own and keep their heights consistent ([HIG Scroll views, updated 2026-06-08](https://developer.apple.com/design/human-interface-guidelines/scroll-views)).
17. **Sidebar content.**
    - "Show no more than two levels of hierarchy". Use disclosure controls.
    - Let people customise the sidebar. "Avoid hiding the sidebar by default". Offer Show/Hide Sidebar in the View menu.
    - "Avoid putting critical information or actions at the bottom of a sidebar."
    - Row height, text and glyph size follow the user's small/medium/large sidebar setting.
    - Icons follow the user's accent colour. Use fixed colours sparingly ([HIG Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)).
18. **SF Symbols.** There are four rendering modes, nine weights matched to SF font weights, and three scales "relative to the cap height". Use variable colour for change and hierarchical mode for depth ([HIG SF Symbols](https://developer.apple.com/design/human-interface-guidelines/sf-symbols)). Menus now put icons on the leading edge on macOS too ([WWDC25-323](https://developer.apple.com/videos/play/wwdc2025/323/)), though macOS 27 cut back icons in sub-menus ([9to5Mac](https://9to5mac.com/2026/06/09/macos-27-golden-gate-includes-these-changes-that-tahoe-critics-will-appreciate/)).
19. **Type and emphasis.** "Typography is bolder and left-aligned." "Don't rely on (color) decoration, but on grouping and layout" ([WWDC25-356 notes](https://wwdcnotes.com/documentation/wwdc25-356-get-to-know-the-new-design-system/)).
20. **Principles (reintroduced 2026-06-08).** "Stay out of the way." "Simplicity isn't minimalism." "Quality sets the tone … smooth animations, precise wording." "Don't mistake delight for decoration" ([HIG Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles)).

---

## 3. Kagi Orion

- **Platform / engine:** macOS + iOS/iPadOS, WebKit. **1.0 for Mac shipped in November 2025** after a six-year beta ([9to5Mac, 2025-11-26](https://9to5mac.com/2025/11/26/new-mac-browser-orion-is-inspired-by-apple-with-speed-privacy-and-webkit/)). 1.1 shipped in June 2026 ([PiunikaWeb, 2026-06-25](https://piunikaweb.com/2026/06/25/orion-browser-1-1-update/)). Kagi dropped Linux/Windows on 2026-10-02 to focus on Apple platforms ([Next.ink](https://next.ink/brief-article/le-navigateur-orion-pour-mac-abandonne-ses-versions-linux-et-windows/), citing [blog.kagi.com/update-orion-linux-windows](https://blog.kagi.com/update-orion-linux-windows)).
- **Layout and tabs:**
  - A View-menu toggle shows a vertical-tabs sidebar ([help: vertical tabs](https://help.kagi.com/orion/features/vertical-tabs.html)).
  - The **Compact** tab layout puts tabs "into a single compact bar" next to the address bar, each tab showing a favicon plus a short title ([help: compact tabs](https://help.kagi.com/orion/features/compact-tabs.html)).
  - 1.1's "interface refresh opts for more space in compact mode". Its caption reads "the sidebar and the new compact tab view with pinned and normal tabs" ([Orion 1.1 notes](https://orionbrowser.com/updates/versions/1.1)).
  - Observed in `orion-compact-tabs-sidebar.webp`: pinned favicons as a row in the sidebar, then a plain tab list, and a single toolbar row holding favicon-only pinned tabs, titled tabs and the search field.
- **Liquid Glass reversal:** "After many lively discussions and tense tests, the Orion team created our own Liquid Glass interface … We've now decided to step back, learn from our mistakes (and the mistakes of others), and take a new direction" ([Orion 1.1](https://orionbrowser.com/updates/versions/1.1)). PiunikaWeb says the notes describe it as having "caused too many UX issues" ([PiunikaWeb](https://piunikaweb.com/2026/06/25/orion-browser-1-1-update/)).
- **Declutter:** location-bar status indicators are "grouped under a single icon to keep things clean and readable". There's a toggle under Settings > Appearance > Group searchbar status indicators ([Orion 1.1](https://orionbrowser.com/updates/versions/1.1)).
- **Hiding chrome:** Focus Mode turns a site into a "distraction-free web app" ([9to5Mac](https://9to5mac.com/2025/11/26/new-mac-browser-orion-is-inspired-by-apple-with-speed-privacy-and-webkit/)). Orion+ **browser borders** draw a coloured frame around the window, with settings for size, solid or gradient colour, transparency and animation. "Used in conjunction with Focus Mode, which hides the browser UI" ([Orion 1.1](https://orionbrowser.com/updates/versions/1.1)). See `orion-focus-mode-border.webp`.
- **Other standouts:** Profiles as Apps, per-tab Containers (1.1), Link Preview, Mini Toolbar, Page Tweak, and no AI code in the core ([9to5Mac](https://9to5mac.com/2025/11/26/new-mac-browser-orion-is-inspired-by-apple-with-speed-privacy-and-webkit/), [PiunikaWeb](https://piunikaweb.com/2026/06/25/orion-browser-1-1-update/)).
- **Praise and complaints:** the 1.1 grouped indicators were described as making the bar "feel less cluttered" ([PiunikaWeb](https://piunikaweb.com/2026/06/25/orion-browser-1-1-update/)). Anecdotal reports mention disappearing tabs and crashes ([Tildes thread](https://tildes.net/~tech/1way), per search snippet, **unverified**) and partial extension compatibility (search snippets, **unverified**).
- **Idea for MBGA:** (a) a **Focus mode with an optional 2–4 pt space-coloured border** (colour = the space's colour), so a chrome-free window still tells you which space you're in. (b) Collapse address-bar status icons (secure, permissions, blocker count) into one "site" glyph that opens a popover.

## 4. SigmaOS

- **Platform / engine:** macOS-only, WebKit, "Native SwiftUI for macOS" ([sigmaos.com](https://sigmaos.com/)). YC S21, beta in 2021, **1.0 in November 2022** ([TechCrunch, 2022-11-16](https://techcrunch.com/2022/11/16/sigmaos-raises-4-million-to-build-a-browser-for-productivity-nerds/)). Current activity is **unclear**: the updates page shows 1.17.0 as its newest entry ([sigmaos.com/updates](https://sigmaos.com/updates)), and AlternativeTo reportedly flags it as having had no updates since mid-2024 (search snippet, **unverified**).
- **Layout and tabs:**
  - Workspaces are "like rooms in a house" ([sigmaos.com/old-home](https://sigmaos.com/old-home)).
  - Tabs behave like email. You can snooze them, and **marking a tab done closes it**. A "lazy search" bar searches open tabs or the web ([TechCrunch](https://techcrunch.com/2022/11/16/sigmaos-raises-4-million-to-build-a-browser-for-productivity-nerds/)).
  - Fast Company described a row of workspace icons down the left, no horizontal tab bar, no bookmarks and one window (via search snippet; the article itself returned 403).
  - Observed in `sigmaos-mark-as-done.webp`: a left rail of emoji workspace icons, a workspace title with emoji, lock icons on kept tabs, and a hover action strip (⋮, lock, ✓) whose tooltip says "Mark as done **D**".
- **Theming:** "Magic Theme" matches the browser's colours to the current site. Focus Mode "hides everything except the current page" ([sigmaos.com](https://sigmaos.com/)).
- **Praise and complaints:** founder quote: "you focus on doing your best work, while we take care of organizing" ([TechCrunch](https://techcrunch.com/2022/11/16/sigmaos-raises-4-million-to-build-a-browser-for-productivity-nerds/)). Pricing has moved to AI tiers at $20 and $30 a month ([sigmaos.com](https://sigmaos.com/)).
- **Idea for MBGA:** in the Today section, a **hover-only ✓ "done" button** with a tooltip that shows its single-key shortcut. Done closes the tab and archives it, giving a to-do-style "inbox zero" feeling.

## 5. Zen Browser

- **Platform / engine:** Win/macOS/Linux, Firefox/Gecko (Firefox 158 as of October 2026, [README](https://raw.githubusercontent.com/zen-browser/desktop/dev/README.md)). First release **2024-07-11**. The current build is 1.23.3b (2026-10-16), and the "b" suffix is still on every release ([Wikipedia](https://en.wikipedia.org/wiki/Zen_Browser), [release notes](https://zen-browser.app/release-notes)).
- **Layout and tabs:**
  - A vertical sidebar on the left or right with **Essentials** (favourite tiles), then Spaces (emoji + name), then pinned tabs, then normal tabs. Folders since August 2025 ([Wikipedia](https://en.wikipedia.org/wiki/Zen_Browser)).
  - "Collapse all pinned tabs by clicking on the space name below the essentials" (1.18b). "Close buttons now only show when hovering over tabs" (1.17.8b) ([release notes](https://zen-browser.app/release-notes)).
  - Observed in `zen-sidebar-essentials.webp`: two large Essentials tiles, an emoji space header, a divider before "+ New Tab", and space icons in the bottom bar.
- **Compact mode** ([docs](https://docs.zen-browser.app/user-manual/compact-mode), [release notes](https://zen-browser.app/release-notes)):
  - Hides the sidebar, the top toolbar, or both. Hovering the edge reveals them, and floating shortcuts pin them open.
  - Since 1.17b, compact mode in double-toolbar layout "overlays the web view instead of sliding".
  - Since 1.21.11b, it "tracks your mouse even after it leaves the window".
- **Materials and visual changes** ([release notes](https://zen-browser.app/release-notes)):
  - 1.17b: "Zen will now start using the new MacOS Tahoe look and feel".
  - 1.22b (2026-09-03): squircle-based chrome styling, larger sidebar font, and a new onboarding flow.
  - 1.23b (2026-10-01): "the sidebar and the command bar now appear with blur effects". On macOS the sidebar's bottom buttons got bigger.
- **Other standouts:** Glance opens links in a dismissible modal ([Wikipedia](https://en.wikipedia.org/wiki/Zen_Browser)). Split View: drag a tab onto a tab for one second to split (1.19b). Spaces, folders and splits can be shared by link (1.22.1b). Monochrome themes plus a colour-algorithm picker (1.17.13b). Library (1.23b).
- **Praise and complaints:** praised for customisation and Arc-likeness. The main downside cited is no DRM ([Wikipedia](https://en.wikipedia.org/wiki/Zen_Browser), citing ZDNET, XDA and The Register). One user called it "only a shadow" of Arc that lacks "many less visible details" (Habr comment via search snippet, **unverified**). Compact mode has needed repeated fixes, including flicker and toolbar spacing ([release notes](https://zen-browser.app/release-notes)).
- **Idea for MBGA:** (a) a **click on the space name collapses all pinned tabs**, a one-gesture declutter. (b) A compact-mode sidebar that **overlays** the page instead of reflowing it, and keeps tracking the pointer after it leaves the window so it doesn't flicker.

## 6. Helium (imput)

- **Platform / engine:** macOS/Linux/Windows, ungoogled-Chromium. Repo created February 2025. First macOS build 0.0.1.1 on **2025-05-04** (GitHub API). Still labelled "beta" ([README](https://github.com/imputnet/helium)).
- **Layouts:** the site advertises layouts including **dynamic, compact, vertical, classic and frameless** ([helium.computer](https://helium.computer/)). You switch by right-clicking the window frame ([AlternativeTo, 2026-02-17](https://alternativeto.net/news/2026/2/helium-browser-debuts-experimental-vertical-tabs-for-improved-user-experience)).
  - **Dynamic:** "something like default safari, in-between compact and classic, but more minimal visually". Pairs with a **minimal, centred location bar showing only the origin**, capped at 700 px wide ([PR #1164, merged 2026-04-06](https://github.com/imputnet/helium/pull/1164)).
  - **Compact:** the address field and tabs share one row (`helium-compact-layout.webp`).
  - **Vertical:** ⌘S toggles it (0.10.4.1) ([macOS releases](https://github.com/imputnet/helium-macos/releases)).
  - **Frameless:** renamed from "Zen mode" in 0.13.1.1. The sidebar is now a **floating surface "with proper padding, margins, rounded corners, and an outline"** that **slides instead of scaling down in width**. It uses a thinner trigger area with a grace period, and the top chrome auto-pins while a bubble or menu is open ([PR #1590, 2026-05-12](https://github.com/imputnet/helium/pull/1590)).
- **Polish commits** ([helium-macos releases](https://github.com/imputnet/helium-macos/releases)):
  - 0.11.4.1 (2026-04-25): "add a rounded webview frame with adaptive corners", "create a frame radius helper for best corners on every OS", "transparent tabs by default".
  - 0.12.2.1: "remove toolbar dividers".
  - 0.14.4.1: "remove rounded corner on attached side".
  - 0.18.2.1: minimum window width set to 400 dp in every layout.
  - Observed in `helium-vertical-rounded-frame.webp`: page content inset in a rounded frame next to the tab column.
- **Other standouts:** built-in uBlock Origin, more than 13k local !bangs, tab hibernation, split view with a "stacked" option ([helium.computer](https://helium.computer/), [releases](https://github.com/imputnet/helium-macos/releases)).
- **Praise and complaints:** It's FOSS called it "polished and clean" ([2025-12-10](https://itsfoss.com/helium-browser/)). Techlore: "I'm not a fan of Helium's UI … barebones to a fault". It argued that removing features doesn't by itself make good design, and pointed to Brave's tab spacing and scaling as better ([Techlore, 2026-04-22](https://techlore.tech/helium-browser-review-a-truly-minimal-privacy-focused-chromium-browser/)). **Lesson for MBGA: minimal is not the same as premium.**
- **Idea for MBGA:** a **"minimal address" mode**: centred, origin-only, at most about 700 pt wide, showing the full URL only on focus (⌘L). Corner radius should come from one helper that adapts to window state. Drop the radius on edges that touch other chrome.

## 7. Vivaldi 8

- **Platform / engine:** Win/macOS/Linux, Chromium. 1.0 shipped in April 2016. **8.0 shipped 2026-05-21** ([press release](https://vivaldi.com/press/vivaldi-8-0-the-most-significant-design-overhaul-in-the-browsers-history/)). 8.1 followed on 2026-08-21 with tab and auto-hide refinements ([LinuxToday](https://www.linuxtoday.com/blog/vivaldi-8-1-browser-released-with-tab-behavior-improvements/)).
- **The "Unified" design:**
  - Tabs, toolbars, panels and content used to be separate layers. Now all toolbars sit on "one continuous surface that wraps the browser", and themes flow from the tab bar through panels to the window edges ([press release](https://vivaldi.com/press/vivaldi-8-0-the-most-significant-design-overhaul-in-the-browsers-history/)).
  - Web content is "framed" with rounded corners instead of running edge to edge ([OMG! Ubuntu](https://omgubuntu.co.uk/2026/05/vivaldi-8-0-released-redesigned)).
  - It uses transparency and blur ([WinFuture](https://winfuture.de/news,158887.html)).
  - The previous look is still available as a setting ([press release](https://vivaldi.com/press/vivaldi-8-0-the-most-significant-design-overhaul-in-the-browsers-history/)).
- **Layout presets:** Simple, Classic, Vertical Left, Vertical Right, Auto-hide ("edge-to-edge content with a fully hidden UI") and Bottom. They're offered during onboarding as a "Choose a style" page (`vivaldi-choose-a-style.webp`) and again in Settings ([press release](https://vivaldi.com/press/vivaldi-8-0-the-most-significant-design-overhaul-in-the-browsers-history/)).
- **Praise and complaints:**
  - Forum feedback was mixed. Some called it "gorgeous" or said the "UI polish was much-needed". Others said it is "a bit too unified", with background tabs lacking separation, and that the tab bar takes more space in compact mode (forum posts via search snippets, e.g. [forum.vivaldi.net/post/903348](https://forum.vivaldi.net/post/903348), **unverified** individually).
  - WinFuture frames 8.0 as a response to "cluttered" complaints, while customisation still takes time in deep settings ([WinFuture](https://winfuture.de/news,158887.html)).
- **Idea for MBGA:** (a) a **"Choose a style" step in the existing welcome sheet** with 3–4 live thumbnails (Sidebar, Compact, Focus, maybe Top tabs), which can be changed later. (b) When unifying chrome, **keep a visible selected-tab state**, because "too unified" was the main complaint.

## 8. Floorp

- **Platform / engine:** Win/macOS/Linux, Firefox (back on rapid-release Firefox since 12.1.0). Made in Japan by Floorp Projects. First public build 7.0.0 in September 2021. 12.20.2 as of 2026-10-17 ([Wikipedia](https://en.wikipedia.org/wiki/Floorp)).
- **UI decisions in 12.0 (2025-08-19):**
  - Floating Panel Sidebar mode (web panels), native mouse gestures, and "Floorp Hub" settings separated from Firefox prefs.
  - Workspaces sync across windows.
  - **Native vertical tabs were removed** in favour of Firefox's own. Dual themes and CSS customisation were removed too ([AlternativeTo](https://alternativeto.net/news/2025/8/floorp-browser-12-0-adds-floating-panel-sidebar-and-native-mouse-gestures)).
  - One workspace shows per window ([docs](https://docs.floorp.app/docs/features/workspaces)).
- **Praise and complaints:** "convenient". Fast Company found it unfriendly to beginners ([Wikipedia](https://en.wikipedia.org/wiki/Floorp)).
- **Idea for MBGA:** keep MBGA-specific settings in **one dedicated settings surface** (Floorp Hub) rather than mixing them into Chromium's settings pages.

## 9. Ladybird

- **Platform / engine:** its own engine (LibWeb/LibJS) built by a non-profit. Alpha for macOS and Linux is due "later this year" (2026). Beta is expected in 2027 and stable in 2028 ([ladybird.org](https://ladybird.org/), [Wikipedia](https://en.wikipedia.org/wiki/Ladybird_(web_browser))).
- **UI:** a conventional top-tab Chromium-like chrome (observed in the site's hero screenshot). As of 2026-10-21 the repo's `UI/` folder contains **Qt and Android only**: `UI/AppKit` returns 404, while the 2023–2025 docs listed AppKit as the native macOS chrome ([repo UI/](https://github.com/LadybirdBrowser/ladybird/tree/master/UI)). When and why AppKit was removed is **unverified**.
- **Why it matters:** philosophy rather than UI. No default search deals and no monetisation ([ladybird.org](https://ladybird.org/)).
- **Idea for MBGA:** none on visuals. Its "just a browser" positioning backs a calm, non-upselling UI with no promo cards on the new-tab page.

## 10. Min

- **Platform / engine:** Win/macOS/Linux on Electron (Chromium). `electron` is 43.4.1 in [package.json](https://raw.githubusercontent.com/minbrowser/min/master/package.json). Repo created 2015-10-31. v1.35.7 shipped 2026-08-23 ([GitHub](https://github.com/minbrowser/min)).
- **UI decisions:**
  - The tab bar is the address bar. Typing turns the window into a **full-width, large-type result list** (`min-full-window-search.webp`).
  - "Tabs take up less space, and pages you haven't viewed in a while fade out." Focus Mode hides the other tabs.
  - Tasks are tab groups that auto-collapse when unused ([minbrowser.org](https://minbrowser.org/)).
- **Praise and complaints:** long-lived and very minimal. The README screenshots look dated (**date unknown**).
- **Idea for MBGA:** let **untouched tabs visually fade** over time (age is part of the opacity), which pairs naturally with tab sleeping. Min's full-window result list is also a nice model for a Cmd+L takeover.

## 11. Native Swift Arc-likes and other newcomers (2025–2026)

GitHub star counts were read via the API on 2026-10-21.

### Nook (nook-browser/Nook), about 1.96k stars
- **What it is:** SwiftUI/AppKit on WebKit (WKWebExtension), "sidebar-first", macOS 26+ on Apple Silicon. Repo created 2025-08-01. "Development started back up in September 2026 under a new maintainer" ([README](https://github.com/nook-browser/Nook)).
- **Design tokens** in [`NookDesign.swift`](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift) ("No literal radius, font size, shadow, or animation duration may appear in the UI layer outside this file"):
  - **Radius** (continuous): 4 favicon, 6 icon button, 8 tab row / URL bar, 12 essentials tile / card, 16 dialog / toast, 24 command palette.
  - **Size:** row 32, essentials tile 44, chrome control 36, sidebar top band 52, traffic-light area 88, folder indent 20, minimum sidebar width 206.
  - **Type:** 13 medium for tab titles, 13 semibold for space names, 12 medium for the URL bar, 11 semibold for section headers.
  - **Motion:** hover `easeOut 0.12`, selection `smooth 0.22`, palette/dialog `snappy 0.3`.
  - **Surfaces:** hover fill `primary @ 4.5%`, hairline `primary @ 8%`, **unloaded tabs at 55% opacity**, floating shadow `black 16%, r32, y12`.
  - **Sidebar fill** = the space accent blended toward window background, 55% when the window is active and 80% when inactive, "approximating the dimming NSVisualEffectView.followsWindowActiveState used to give".
- **Glass stance:** "Nook draws no Liquid Glass: floating layers are solid cards" ([View+Surface.swift](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/View+Surface.swift)).
- **Reception:** #9 on Product Hunt the day it launched ([Product Hunt](https://www.producthunt.com/products/nook-an-open-source-arc-alternative)). One commenter said it "looks extremely similar to Zen" ([AlternativeTo](https://alternativeto.net/software/nook-browser/about)).
- **Idea for MBGA:** adopt a **single tokens file** with this kind of scale. The "space accent → window background" gradient with inactive-window dimming is a cheap, legible substitute for custom glass.

### Ora (the-ora/browser), about 2.24k stars
- **What it is:** SwiftUI + AppKit + WebKit, "Less noise, more browsing". Repo created 2025-08-09. "Not ready for daily use yet" ([README](https://github.com/the-ora/browser)). Part of Vercel OSS Fall '25 ([Vercel community](https://community.vercel.com/t/ora-browser-the-open-source-arc-alternative-for-macos/29424)).
- **Features:** Spaces, pinning, floating tab switcher and inactive-tab cleanup are available. Split view, folders and extensions are near-term ([ROADMAP, March 2026](https://github.com/the-ora/browser/blob/main/ROADMAP.md)).
- **Status:** orabrowser.com didn't resolve when I checked, and the repo has no UI screenshots.
- **Idea for MBGA:** a **floating tab switcher** (Ctrl-Tab HUD) as a native panel.

### Search by Office Commun (driceroland/Search), about 2.57k stars, new in September 2026
- **What it is:** SwiftUI + AppKit + WKWebView, MIT licence, about 42k lines of Swift. A Paris design studio's "browser with nothing in the way": tabs on top or left, no toolbar, no start page, one field ([README](https://github.com/driceroland/Search)). Covered by [MacGeneration (Oct 2026)](https://www.macg.co/logiciels/2026/10/search-un-navigateur-web-base-sur-webkit-qui-fait-le-pari-de-la-legerete-311355) and [iThinkDiff](https://www.ithinkdiff.com/search-browser-for-mac-free-3-7-mb/), which reports 3.7 MB and a 320 ms cold launch (self-reported).
- **Metrics with stated reasons** ([Design.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Design.swift)):
  - The tab strip is 52 pt, and the title bar grows to match "so the traffic lights come down with the tabs".
  - The first tab starts at x = 100 because the lights "run from 19 to 79 — measured".
  - With side tabs, **the page is a card: 8 pt from the window edges, 10 pt continuous radius, 1 px edge at `primary 8%`, shadow `black 7%, r6, y1`**. With top tabs it isn't a card.
  - Tabs are a **fixed 186 pt wide** "so the cross always lands in the same place". They shrink to the site mark below 80 pt and stop at 36. Pins are 30 pt squares holding one letter.
  - The sidebar is 232 pt by default (range 176–440). The address field is 560 pt wide.
- **Motion** ([Design.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Design.swift)):
  - The rule is "one spring for anything that moves between two places, one for anything that arrives or leaves … most of why a thing feels like a single piece of software".
  - `glide` is spring(0.34, 0.82), `settle` is spring(0.30, 0.86), `quick` is easeOut 0.14, and all of them respect Reduce Motion.
  - The folded sidebar's reveal was timed **against Arc and Dia frame by frame: "90% of the way out in about 95ms and back in about 70ms"**, so `fold` uses (0.14, 0.86) going out and (0.13, 1.0) coming back.
- **Features:** ⌘K tab list, "Keep This Site Awake" per site (exempt from sleeping), ⇧⌘H to hide page elements permanently, PiP, built-in password vault in the keychain, Chrome extensions via WKWebExtension ([README](https://github.com/driceroland/Search)).
- **Idea for MBGA:** this file is the best "premium feel" reference in the slice. Copy the **page-as-card recipe, the two-spring motion vocabulary and the measured sidebar timings**.

### Crest (pauljoda/Crest), about 450 stars, new in August 2026
- **What it is:** SwiftUI shell on Mac, **running Chromium (ungoogled) by default plus WebKit per site**, which is the closest architecture to MBGA's ([README](https://github.com/pauljoda/Crest), [crestbrowser.com](https://crestbrowser.com/)).
- **Spaces:** each Space has its own cookies, history, credentials and sync identity. "Switching Spaces changes more than the color of the window. It changes the browsing context." "Crest Studio" draws a heraldic crest or banner on each Space's sidebar background (`crest-space-banner-sidebar.webp`: diagonal two-colour banner, folder with count, Split View groups shown as cards, space switcher at the bottom).
- **Appearance settings:** dock the sidebar on either side, go borderless. Observed in the screenshot: a window border slider (set to 8 pt), tab corner radius (Square/Soft/Round/Capsule), tab scale (Compact/Default/Comfortable), "Website colors for pins", "**Dim unloaded tabs**", "Animate pages when switching Spaces". Settings open as a tab with a searchable category sidebar (`crest-appearance-settings.webp`).
- **Other standouts:** Split View with 2–4 pages, Peek, Quick Window, Link Routing to a Space ([README](https://github.com/pauljoda/Crest)).
- **Idea for MBGA:** a **per-space banner or illustration** at the top of the sidebar, plus a settings "Appearance" page with live preview, built as a SwiftUI form in grouped rounded sections.

### Phi (phibrowser/phibrowser-mac), about 240 stars
- **What it is:** "a Chromium-based browser built as a real native macOS app (AppKit + SwiftUI)", with an AI agent. Apache-2.0 client, closed Chromium framework ([README](https://github.com/phibrowser/phibrowser-mac)).
- **Design stance:** "Simple until you want more … opens as a clean tabbed browser … then it unfolds: spaces, profiles, split views". This progressive disclosure matches HIG layout guidance.
- **Idea for MBGA:** a reference implementation for native-Swift-on-Chromium plumbing, worth reading for CEF/Chromium embedding patterns (read only; don't run it).

### Web (nuance-dev/Web), about 660 stars
- **What it is:** native macOS on WebKit with local MLX AI, macOS 26.5+ ([README](https://github.com/nuance-dev/Web)).
- **Features:** tabs on the side, on top or hidden. ⌘K for tabs and commands. **Focus Mode ⇧⌘B "for just the page. ⌘L brings back the address field."** ⌃⌥Space "Glance" opens a corner lookup window.
- **Idea for MBGA:** in Focus mode, ⌘L should bring up only the address field as a floating HUD, not the whole chrome.

### chromeless (antiwork/chromeless), about 280 stars
- **What it is:** "The window *is* the webpage". ⌘L opens a floating HUD, ⌘-drag moves the window from anywhere, and "the traffic-light buttons exist but stay invisible — hover the top-left corner to reveal them" ([README](https://github.com/antiwork/chromeless)).
- **Idea for MBGA:** in Focus mode, **hide the traffic lights until the pointer reaches the top-left corner**.

Others found but not reviewed in depth: mori-browser (Arc alternative with Codex, about 140 stars), Talos (WebKit, Spaces), Aura (2024, stale).

---

## 12. Top ideas for MBGA (ranked)

1. **Page-as-card with concentric corners.**
   - In sidebar layouts, inset the CEF view 6–8 pt from the window and sidebar. Give it a continuous corner radius of window radius minus inset, a 1 px `primary 8%` edge and a faint `black 7% r6 y1` shadow.
   - Go edge-to-edge (no card) in Focus/fullscreen.
   - Implement as an AppKit container with `layer.cornerCurve = .continuous` and `masksToBounds`. Read the window radius from the system, since it differs between Tahoe and Golden Gate.
   - Sources: [Search Design.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Design.swift), [Helium 0.11.4.1](https://github.com/imputnet/helium-macos/releases), [Vivaldi 8](https://omgubuntu.co.uk/2026/05/vivaldi-8-0-released-redesigned), [WWDC25-356 concentricity](https://wwdcnotes.com/documentation/wwdc25-356-get-to-know-the-new-design-system/), [WWDC25-310 corners clip content](https://developer.apple.com/videos/play/wwdc2025/310/).
2. **Glass discipline: native glass only.**
   - Get Liquid Glass only from system containers: an `NSSplitViewController` sidebar item and an `NSToolbar` if one is used.
   - Remove any `NSVisualEffectView` from the sidebar.
   - Draw floating UI (command bar, popovers, toasts) as **solid cards with a hairline and a soft shadow**, not hand-made glass.
   - Sources: [Orion 1.1 stepped back from its custom Liquid Glass](https://orionbrowser.com/updates/versions/1.1), [Nook draws no Liquid Glass](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/View+Surface.swift), [HIG Materials "sparingly"](https://developer.apple.com/design/human-interface-guidelines/materials), [WWDC25-310](https://developer.apple.com/videos/play/wwdc2025/310/).
3. **Space colour as a washed gradient, not a flood.**
   - Sidebar background = a vertical gradient. The top stop is the space colour blended 55% toward `windowBackgroundColor` (80% when the window is inactive), and the bottom stop is plain `windowBackgroundColor`.
   - Keep text monochrome on top of it.
   - Sources: [Nook containerGradient](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift), [HIG inactive windows drop materials](https://developer.apple.com/design/human-interface-guidelines/windows), [HIG avoid similar colours in labels and background](https://developer.apple.com/design/human-interface-guidelines/color), [Crest Space banners](https://github.com/pauljoda/Crest).
4. **One motion vocabulary.**
   - `quick` = easeOut 0.12–0.14 for hover and press.
   - `glide` = spring(0.34, 0.82) for moves and reorders.
   - `settle` = spring(0.30, 0.86) for things arriving.
   - Sidebar reveal in compact mode = spring(0.14, 0.86) out and (0.13, 1.0) in, which matches Arc and Dia's measured ~95/70 ms.
   - Everything respects Reduce Motion.
   - Sources: [Search Design.swift](https://github.com/driceroland/Search/blob/main/Sources/Search/Design.swift), [Nook Motion](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift).
5. **Compact mode = floating sidebar card that slides.**
   - Hidden sidebar comes back as a rounded, outlined, padded card over the page, using translate rather than width animation.
   - Thin edge trigger with a grace period. Auto-pin while a menu, popover or drag is active. Keep tracking the pointer outside the window.
   - Sources: [Helium PR #1590](https://github.com/imputnet/helium/pull/1590), [Zen 1.17b / 1.21.11b](https://zen-browser.app/release-notes), [Zen docs](https://docs.zen-browser.app/user-manual/compact-mode).
6. **A 52 pt title band instead of a toolbar.**
   - Grow the titlebar so the traffic lights sit vertically centred in a 52 pt band shared with the sidebar's nav buttons. Start sidebar content at x ≈ 88–100 to leave the lights equal air.
   - At most three control groups, symbols without borders, each mirrored as a menu command.
   - Sources: [Search Metrics](https://github.com/driceroland/Search/blob/main/Sources/Search/Design.swift), [Nook sidebarTop/trafficLights](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift), [HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars).
7. **Make tab sleeping visible but calm.**
   - Sleeping tabs at about 55% opacity. Optionally fade further with age.
   - Right-click "Keep this site awake" exempts a site.
   - Sources: [Nook unloadedOpacity 0.55](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift), [Crest "Dim unloaded tabs"](https://github.com/pauljoda/Crest), [Min fading tabs](https://minbrowser.org/), [Search Keep Site Awake](https://github.com/driceroland/Search).
8. **Focus mode done properly.**
   - Zero chrome, with an optional 2–4 pt space-coloured window border.
   - Traffic lights appear only when the pointer hovers top-left.
   - ⌘L summons just a floating address HUD. Esc or the same shortcut restores everything.
   - Sources: [Orion 1.1 borders](https://orionbrowser.com/updates/versions/1.1), [chromeless](https://github.com/antiwork/chromeless), [Web Focus Mode](https://github.com/nuance-dev/Web), [HIG "reliably restore hidden interface"](https://developer.apple.com/design/human-interface-guidelines/toolbars).
9. **Folder and group pills, plus page-tinted chrome.**
   - Collapsed folders show as a capsule with a count ("Research 7 ›").
   - Optionally tint the title band or card edge with the page's `theme-color` (very low alpha) while keeping labels monochrome.
   - Sources: [Safari 27 image and copy](https://www.apple.com/os/macos/), [SigmaOS Magic Theme](https://sigmaos.com/), [HIG Color cautions](https://developer.apple.com/design/human-interface-guidelines/color).
10. **"Choose a style" in the welcome sheet.**
    - 3–4 live thumbnails (Sidebar, Compact, Focus, Top tabs), changeable later.
    - Sources: [Vivaldi 8 presets in onboarding](https://vivaldi.com/press/vivaldi-8-0-the-most-significant-design-overhaul-in-the-browsers-history/), [Helium layouts](https://helium.computer/).
11. **Space-name tap collapses pins, and hover-only row actions.**
    - Clicking the space header collapses all pinned tabs.
    - Close, sleep and done (✓) appear only on hover, with shortcut hints in tooltips.
    - Sources: [Zen 1.18b, 1.17.8b](https://zen-browser.app/release-notes), [SigmaOS "Mark as done D"](https://techcrunch.com/2022/11/16/sigmaos-raises-4-million-to-build-a-browser-for-productivity-nerds/).
12. **Command bar as a big, quiet card.**
    - 24 pt radius solid card, 15 pt semibold input, tabs first, then history, then commands.
    - Or Min-style full-window large-type results for Cmd+L.
    - Sources: [Nook Radius.xxl and Font.title](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift), [Min](https://minbrowser.org/), [Zen 1.22.3b command bar searches tabs and folders](https://zen-browser.app/release-notes).
13. **Fixed-width tabs and letter pins in the compact or top layout.**
    - Tabs about 186 pt wide so the close button never moves. Pins as 30 pt squares.
    - Collapse status icons into one site glyph.
    - Sources: [Search Metrics](https://github.com/driceroland/Search/blob/main/Sources/Search/Design.swift), [Orion 1.1 grouped indicators](https://orionbrowser.com/updates/versions/1.1).
14. **Settings as one dedicated surface.**
    - Category sidebar with tinted 22 pt icon chips. Grouped rounded sections. A search field. Live preview for Appearance.
    - Sources: [Crest](https://github.com/pauljoda/Crest), [Nook settingsChip](https://github.com/nook-browser/Nook/blob/HEAD/Packages/NookDesign/Sources/NookDesign/NookDesign.swift), [Floorp Hub](https://alternativeto.net/news/2025/8/floorp-browser-12-0-adds-floating-panel-sidebar-and-native-mouse-gestures).
15. **Guard against "minimal = unfinished".**
    - Spend the polish budget on spacing, hover and pressed states, and selection visibility before adding features.
    - Sources: [Techlore on Helium "barebones to a fault"](https://techlore.tech/helium-browser-review-a-truly-minimal-privacy-focused-chromium-browser/), [Vivaldi "too unified"](https://forum.vivaldi.net/post/903348) (unverified forum snippet), [HIG "Simplicity isn't minimalism"](https://developer.apple.com/design/human-interface-guidelines/design-principles).

---

## 13. Images

All files are in `docs/design-research/img/mac-native/`, saved as WebP at no more than 1600 px wide.

| File | What it shows | Source URL |
|---|---|---|
| `safari-tahoe-floating-sidebar.webp` | Safari 26 on Tahoe: inset floating sidebar pane (Tab Groups / iCloud Tabs / Saved), grouped glass toolbar capsules, page scrolling under the toolbar (MacStories, September 2025) | https://cdn.macstories.net/cleanshot-2025-09-03-at-13-50-33-2x-1756921851415.png (from https://www.macstories.net/stories/macos-26-tahoe-the-macstories-review/2/) |
| `safari-tahoe-grouped-toolbar.webp` | Safari 26 single-tab window: three glass control groups around a centred address field, no tab strip (Apple press image, cropped to the window) | https://www.apple.com/newsroom/images/2025/06/macos-tahoe-26-makes-the-mac-more-capable-productive-and-intelligent-than-ever/article/Apple-WWDC25-macOS-Tahoe-26-Safari-250609_big.jpg.large_2x.jpg |
| `safari27-topic-tab-groups.webp` | Safari on macOS 27: topic tab groups as capsules with counts, raised active-tab pill, toolbar and tab strip tinted by the page colour | https://www.apple.com/v/os/g/images/macos/apple_intelligence/safari__wwqti2pesg22_large_2x.jpg (from https://www.apple.com/os/macos/) |
| `orion-compact-tabs-sidebar.webp` | Orion 1.1: sidebar with a pinned-favicon row plus tab list, and a single-row compact tab bar with the search field | https://media.kagi.com/orion-1.1-interface.webp (from https://orionbrowser.com/updates/versions/1.1) |
| `orion-focus-mode-border.webp` | Orion 1.1 Focus Mode with an Orion+ window border: no chrome, page framed by a thin border | https://media.kagi.com/orion-1.1-border.webp |
| `zen-sidebar-essentials.webp` | Zen on macOS: Essentials tiles, emoji space header, pinned tabs, divider, "New Tab", space icons in the bottom bar (date unknown) | https://dl.flathub.org/media/app/zen_browser/zen/d60bd1687b643e1eceb358478d133c8f/screenshots/image-1_orig.png (from https://flathub.org/apps/app.zen_browser.zen) |
| `helium-compact-layout.webp` | Helium compact layout: address field and tabs in one row, minimal toolbar | https://helium.computer/landing/interface/compact.avif |
| `helium-vertical-rounded-frame.webp` | Helium vertical layout: plain tab column, page inset in a rounded frame, centred address field | https://helium.computer/landing/interface/vertical.avif |
| `sigmaos-mark-as-done.webp` | SigmaOS (2022): emoji workspace rail, tab rows with lock icons, hover "Mark as done (D)" tooltip | https://techcrunch.com/wp-content/uploads/2022/11/mark-as-done.jpg (from https://techcrunch.com/2022/11/16/sigmaos-raises-4-million-to-build-a-browser-for-productivity-nerds/) |
| `vivaldi-choose-a-style.webp` | Vivaldi 8 onboarding "Choose a style": six layout presets as schematic cards | https://vivaldi.com/wp-content/uploads/8.0_desktop_layouts_onoarding.png |
| `min-full-window-search.webp` | Min: typing in the tab bar turns the whole window into a large-type result list (older screenshot, date unknown) | https://minbrowser.org/tour/img/searchbar_duckduckgo_answers.png |
| `search-officecommun-sidebar.webp` | Search (Office Commun, 2026): letter-pin tiles, quiet tab list, no toolbar, page as a card | https://raw.githubusercontent.com/driceroland/Search/main/.github/screenshot.png |
| `crest-space-banner-sidebar.webp` | Crest (SwiftUI + Chromium): space banner art on the sidebar, folder with count, Split View groups as cards, space switcher at the bottom | https://raw.githubusercontent.com/pauljoda/Crest/main/Website/assets/crest-work-mac.png |
| `crest-appearance-settings.webp` | Crest settings as a tab: category sidebar and grouped Appearance controls (window border, tab radius, tab scale, dim unloaded tabs) | https://raw.githubusercontent.com/pauljoda/Crest/main/Website/assets/crest-look-and-feel-mac.png |
