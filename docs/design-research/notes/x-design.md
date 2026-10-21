# X and the design community: what makes a browser feel premium

Research slice: posts on X from browser teams, makers and designers (2025–2026), browser concepts on design galleries, and designer write-ups on interaction quality. Compiled 2026-10-21 for MBGA.

**Method.** Post URLs came from Brave Search (`site:x.com …`) and web search. Post text, dates, like counts and media came from `api.fxtwitter.com` (including its `/2/thread/<id>` endpoint for full threads). Like and view counts were read on 2026-10-21 and will drift. Video stills are frames I extracted from the posted videos.

**Access limits (affects coverage).**
- Dribbble returned an AWS WAF challenge (HTTP 202, empty body) for every page and RSS feed, so I could not read any shots.
- Behance returned 403.
- Mobbin requires a login.
- Brave Search started showing a captcha partway through, so the later X searches are thinner.
- Layers.to was readable, and it is the gallery source used below.
- Godly, Savee and Cosmos mostly hold marketing sites and moodboards, so I did not mine them.

---

## Part 1: Posts on X

### 1. Dia's sidebar: tighter, macOS-scale density (The Browser Company)
- **Who / what:** Charlie Deets (Dia designer) on the launch of Dia's optional vertical sidebar. Dia's own launch video ran alongside it.
- **Date:** 2025-07-07
- **Links:**
  - https://x.com/charliedeets/status/1942214876438421975 (972 likes, ~175K views)
  - Launch video: https://x.com/diabrowser/status/1942213709088149719 (2,426 likes, ~543K views)
  - Earlier prototype: https://x.com/adamstern_/status/1935728462775345487 (2025-06-19, 1,788 likes, "Building @charliedeets's design for a sidebar option… should we ship it?"). Josh Miller quoted it (https://x.com/joshm/status/1937508547358515705, 2025-06-24, 427 likes) to say it would ship as a "secret menu" option "to maintain simplicity of core product".
- **Design move:** The Dia sidebar is drawn at a tighter scale that is "more related to macOS" than Arc's. That makes the tab area denser: more tabs fit vertically and longer titles fit at the same sidebar width. In the comparison image the Arc and Dia sidebars sit side by side. Dia's rows are smaller, the separators are flat, and the selected row is a white rounded pill with a soft shadow.
- **Idea for MBGA:**
  - Size sidebar rows to native macOS sidebar metrics (NSOutlineView `.sourceList` style and system font sizes) rather than an Arc-like oversized scale.
  - Make the selected tab a white or near-white rounded "card" with a 1-layer soft shadow, not a tinted fill.
  - Dia's exact point sizes are not published, so measure the system sidebar to get them.

### 2. Dia: instant tab ops and a "forgiving" drag framework (Adam Stern thread)
- **Who / what:** Adam Stern (engineer, The Browser Company). Thread on the technical details of the sidebar.
- **Date:** 2025-07-07
- **Link:** https://x.com/adamstern_/status/1942215020592709773 (1,110 likes, ~138K views; 4 posts)
- **Design moves:**
  - "The interactions you do hundreds of times a day in the sidebar are FAST. Opening and closing tabs feels instant." (https://x.com/adamstern_/status/1942215024073904606)
  - "Dia uses a new framework for achieving highly granular drag interactions. Tabs stay centered while dragging, allowing for imprecise mouse movement, and fluidly pop into a window preview when moved outside." (https://x.com/adamstern_/status/1942215025956982885)
  - The video shows the dragged row snapping to the cursor's centre line. Neighbours open a gap. Past the sidebar edge, the row morphs into a miniature window thumbnail of the page.
  - Layouts toggle with ⌘⇧S from the View menu (https://x.com/adamstern_/status/1942215028482117994).
- **Idea for MBGA:**
  - During a drag, lock the row's vertical centre to the cursor so the grab offset doesn't matter, and animate neighbours with a short spring.
  - When the cursor leaves the sidebar, cross-fade the row into a live snapshot (from CEF/NSView `cacheDisplay`) inside a borderless shadowed panel. Dropping it creates a window.
  - Never animate tab creation or closing triggered by Cmd+T or Cmd+W.

### 3. Dia: pinned tabs as web apps that light up in the brand colour
- **Who / what:** Charlie Deets (design), engineered by Adam Stern.
- **Date:** 2025-11-06
- **Link:** https://x.com/charliedeets/status/1986468332673937744 (765 likes, ~207K views)
- **Design move:** Pinned tabs become app-icon tiles. In the sidebar they form a grid; in top-tab mode they form a capsule tray next to the traffic lights. The active or hovered tile fills with the site's brand colour (Spotify green in the screenshot), and the others stay neutral grey. Deets says the goal was to make "your web apps feel more at home" and to welcome Arc members.
- **Idea for MBGA:** Pull a dominant colour from each favourite's favicon or `theme-color` and use it as the tile fill when that favourite is the active tab, with the icon in white. Inactive tiles stay a neutral `quaternarySystemFill`. This gives the favourites grid a "dock" feel at zero cost to calm.

### 4. Dia: Focus Mode, and Arc's "greatest hits"
- **Who / what:** Josh Miller (CEO, The Browser Company).
- **Date:** 2025-10-28
- **Links:**
  - https://x.com/joshm/status/1983246018591215993 (547 likes)
  - Context: TechCrunch on Dia adding Arc's "greatest hits" (sidebar mode and more), 2025-11-03: https://techcrunch.com/2025/11/03/dias-ai-browser-starts-adding-arcs-greatest-hits-to-its-feature-set
- **Design move:** ⌘S hides the vertical sidebar or the horizontal tabs. Miller pitches it for screen-sharing and long writing sessions.
- **Idea for MBGA:** Ship a single-key Focus mode (⌘S) that removes the sidebar and toolbar. Pair it with an edge-hover reveal (see #8 and #9 for how Helium and Zen handle the hover).

### 5. Dia: automatic tab clean-up, designed as a trust exercise (Julia Roggatz thread)
- **Who / what:** Julia Roggatz (The Browser Company), quoted by Charlie Deets ("Tab cleanup is in Dia now", 117 likes).
- **Date:** 2026-05-07
- **Link:** https://x.com/juliaroggatz/status/2052395823011397814 (thread of 4; 93 likes on post 1)
- **Design moves:**
  - Premise: "Your browser should be lighter in the morning than how you left it the night before."
  - The rules: "Every action must be visible the first time, reversible every time, and predictable forever." (post 2)
  - The first run asks through a compact card, "10 tabs haven't been touched in a while", with favicons of the affected tabs. It offers three buttons: "Not Now [ESC]", "Clean Up Once", and a primary "Clean Up Daily [⏎]". The keyboard hints are printed on the buttons.
  - On the very first run, "old tabs … play a little animation, with their icons flying into their new home". In the video the favicons arc from the tab strip into the overflow button, and a "Cleaned up 10 tabs" chip appears (post 3).
  - Restore lives in "Recently Closed", and the whole feature is opt-in (post 4).
- **Idea for MBGA:** This maps directly onto tab sleeping and archiving.
  - Show the same three-choice card with keyboard hints the first time MBGA would sleep or archive tabs.
  - Animate favicons flying into the "Archived" control only on that first run, then go silent.
  - Always offer restore.
  - Copy the three trust rules into MBGA's design doc.

### 6. What not to do: a Dia user's teardown of Chrome's vertical tabs
- **Who / what:**
  - Dy (@evowizz), comparing Chrome's new vertical tabs with Dia's.
  - Context: Bramus (Chrome DevRel) showing the Chrome 145 flag, 2026-01-16 (https://x.com/bramus/status/2012094220627071117, 1,857 likes).
- **Date:** 2026-04-13
- **Link:** https://x.com/evowizz/status/2043631713490747537 (311 likes, ~188K views)
- **Design moves (negative list):** Chrome's version:
  1. is laggy;
  2. moves the expand/collapse button when collapsed, so you can't find it;
  3. has no shortcut to collapse;
  4. when collapsed, shrinks tabs instead of moving them out of view;
  5. doesn't adapt the number of pinned tiles per row to the tile count;
  6. stacks pinned tiles in one column when collapsed, pushing real tabs down.

  The Dia comparison video shows a space-tinted sidebar, a 4-column pinned grid and a folder row ("Pull Requests").
- **Idea for MBGA:**
  - Keep the sidebar toggle in a fixed spot in both states and give it a shortcut.
  - "Collapsed" should mean hidden (with hover peek), not shrunk.
  - Choose favourites-grid columns from the count (e.g. 3–4 per row by width) and never fall back to a single column.

### 7. Helium: three layouts, switched in two clicks; right-side tabs; remembered width
- **Who / what:** Helium (imput), plus wukko (Helium developer).
- **Dates:** 2026-02-17 and 2026-02-21
- **Links:**
  - https://x.com/heliumbrowser/status/2023722252290662908 (2,030 likes)
  - https://x.com/uwukko/status/2023723452914344323 (1,328 likes, "two-click layout switching")
  - https://x.com/heliumbrowser/status/2025166790314119310 (1,127 likes)
- **Design move:** The tab-strip context menu has a "Browser Layout ▸" submenu: Classic, Compact, Vertical (Experimental). Vertical tabs can sit on the right. Sidebar width and collapse state persist across sessions.
- **Context:** In 2023 Josh Miller said a right-hand Arc sidebar was "inefficient ergonomically bc gravity of URLs is always top-left" (https://x.com/joshm/status/1724508113208754356, 2023-11-14, outside the date window). Helium shipped the option anyway because users asked for it.
- **Idea for MBGA:**
  - Put "Sidebar on Left/Right" and "Collapse to Rail" in the sidebar's own context menu, so it's two clicks with no Settings trip.
  - Persist width and collapse state per window or space in the Rust core.

### 8. Helium: centred and minimal address bar, dynamic layout, "zen" frameless mode
- **Who / what:** Helium.
- **Date:** 2026-04-09
- **Links:**
  - https://x.com/heliumbrowser/status/2042262820599758934 (3,714 likes, ~503K views)
  - Zen-mode detail: https://x.com/heliumbrowser/status/2042262823447769243 (413 likes)
- **Design move:** New options include a centred address bar, a minimal address bar, a dynamic layout and an experimental zen/frameless mode behind `helium://flags` → `helium-zen-mode`. In zen mode, ⌘/Ctrl+S pins the sidebar and auto-hides the toolbar. The screenshot shows a dark tab column with the page in a single rounded frame and no toolbar at all.
- **Idea for MBGA:** In Focus mode, render the web view as one rounded "platter" inset from the window edge, with the sidebar as a quiet dark or tinted column beside it. Hide the toolbar until the pointer reaches the top edge or the user presses ⌘L.

### 9. Zen: a command bar that does things, plus a run of motion polish
- **Who / what:** Zen Browser.
- **Date:** 2025-09-22, with release notes through 2026-10
- **Links:**
  - https://x.com/zen_browser/status/1970203987396960580 (1,343 likes)
  - Release notes: https://zen-browser.app/release-notes/
- **Design moves:**
  - The command bar takes actions as well as URLs: "Switch spaces, pin tabs, open extensions, create folders." In the video, typing "split" puts **New Split View** in the top row, with a keyboard-hint chip and a row highlight in the space's sage colour. Open tabs show "Switch to Tab ⇥".
  - The sidebar and page frame take on the space's gradient theme.
  - Motion notes from the official release notes:
    - v1.16b (2025-09-21): compact-mode backgrounds "transition smoothly when switching spaces instead of changing instantly".
    - v1.17b (2025-10-19): Glance (link preview) animations "make it feel like the element is being lifted off the page".
    - v1.19.6b (2026-04-03): respects system "reduce motion" for non-essential animations.
    - v1.21.11b (2026-08-05): compact mode "tracks your mouse even after it leaves the window", so the sidebar stays open near the edge.
    - v1.23b (2026-10-01): the sidebar and command bar "now appear with blur effects".
    - Twilight 1.24t (2026-10-19, via PiunikaWeb): the auto-hidden sidebar no longer collapses while the cursor is still on it (https://piunikaweb.com/2026/10/19/zen-browser-smoother-sidebar-hover-new-boosts-feature/).
- **Idea for MBGA:**
  - Make ⌘T/⌘L action-aware: verbs like "split", "pin", "sleep", "new space" and "move to space" resolve to actions ranked above search, each with a shortcut chip.
  - Tint the highlighted row with the current space colour.
  - Cross-fade the sidebar wash when switching spaces (about 200 ms) instead of snapping.
  - Keep the hover-revealed sidebar open while the pointer is within a few points of the window edge.
  - Honour `NSWorkspace.accessibilityDisplayShouldReduceMotion`.

### 10. ChatGPT Atlas: vertical tabs, MRU Ctrl+Tab, auto-organise (now discontinued)
- **Who / what:** Adam Fry (Atlas product lead, OpenAI).
- **Dates:** 2025-11-19 and 2026-02-18
- **Links:**
  - https://x.com/adamhfry/status/1991209533046493486 (2,319 likes, ~669K views)
  - https://x.com/adamhfry/status/2024232095196037212 (490 likes)
- **Design move:**
  - The November release added vertical tabs "by popular demand", a setting for Ctrl+Tab to cycle most-recently-used tabs, and shift-click multi-select.
  - The February release added revamped tab search and an "auto organize" button. It removes duplicates, merges windows, or lets ChatGPT group tabs.
- **Status:** OpenAI shut Atlas down on 2026-08-09 (https://9to5mac.com/2026/08/04/openai-explains-what-will-happen-when-chatgpt-atlas-shuts-down-this-weekend/).
- **Idea for MBGA:** Offer Ctrl+Tab MRU order (Dia does the same, per a user review: https://retroswork.substack.com/p/dia-browser) and a one-click "Tidy" that de-duplicates tabs and merges windows. Both are deterministic and need no AI.

### 11. Comet: generative UI cards; a designer goes back to Arc
- **Who / what:**
  - Aravind Srinivas (Perplexity CEO), 2025-07-20: https://x.com/AravSrinivas/status/1946992255283405086 (985 likes).
  - Axel (product designer), 2025-10-08: https://x.com/axeldesigns/status/1975968862802673899 (5 likes, low engagement).
- **Design move:**
  - In Comet, sending an email or creating an invite produces an inline, editable card instead of a page.
  - Axel calls Comet's layout "clean and well crafted" but says "Arc's vertical tabs are still the best way for me to browse as a designer. The folders make it even more convenient." He also suspected Comet of draining his battery.
- **Idea for MBGA:** Low priority. The useful signal is that designers stay for vertical tabs plus folders and leave over battery drain. MBGA's tab sleeping and lightness are a design feature to show off (e.g., a calm "sleeping" state on rows).

### 12. Orion and SigmaOS: little design-specific material found
- **Orion:** 1.0 for macOS shipped 2025-11-25 (https://x.com/OrionBrowser/status/1993357734729621908, 486 likes). Kagi amplified a user who praised its "Frameless (focus mode)" and its lowest energy impact (https://x.com/KagiHQ/status/1906827610832900486, 2025-03-31).
- **SigmaOS:** I found no 2025–2026 design posts. Its last notable posts are from 2023–2024.

### 13. Recreating the Arc/Dia onboarding in SwiftUI + AppKit (George Cartridge)
- **Who / what:** George (@georgecartridge), indie developer.
- **Dates:** 2025-06-15 (demo) and 2025-06-26 (breakdown thread)
- **Links:**
  - Demo: https://x.com/georgecartridge/status/1934311696861954417 (32 likes)
  - Breakdown: https://x.com/georgecartridge/status/1938365312157544860 (40 likes)
- **Design moves (from the thread):**
  - The desktop fades to semi-transparent black. He builds this with a borderless, full-screen AppKit window whose alpha he animates.
  - A glassy orb grows and "reveals" the window. The orb is a Spline-made video with an alpha channel (PNG sequence → `.mov` via ffmpeg) played in an `AVPlayer` inside a transparent, titlebar-less, shadowless window. When the clip ends, the window gets its normal chrome back and cross-fades into a looping gradient video (simplex fractal noise).
  - The headline "Meet the internet again." animates per character. Each character rotates, blurs and fades in with a spring and a slight stagger (AnimateText package).
- **Idea for MBGA:** MBGA's new welcome/import sheet is the rarest, highest-delight moment, so it can afford this.
  1. Dim the desktop with a borderless window.
  2. Grow the welcome sheet out of a soft orb tinted with the first space's colour.
  3. Stagger the headline in.
  4. Never repeat it.

### 14. Dia's animation recreated in SwiftUI on iPadOS (BunnyLau)
- **Who / what:** BunnyLau (@BunnyxStudio), independent designer and developer.
- **Date:** 2026-08-14
- **Link:** https://x.com/BunnyxStudio/status/2088207251979059467 (615 likes, ~73K views)
- **Design move:** This is a SwiftUI recreation, not Dia itself. It has a favourites icon grid on top, a "Personal" space header, and folders drawn as softly tinted cards (Blog = warm yellow, Design = lavender) that contain their tabs. Hovering a tab shows a small preview card. The sidebar collapses so the page goes full-width inside a rounded frame. The author notes "SwiftUI has made quite a bit of progress over the past two years."
- **Idea for MBGA:**
  - Give each pinned folder an optional tint (derived from the space colour, or user-picked) and render it as a rounded card around its children instead of an indented list.
  - The recreation is evidence that this works well in plain SwiftUI.

### 15. "Liquid Glass on macOS should look like THIS" (concept)
- **Who / what:** @TheAppleDesign (fan account) sharing a Finder concept. The original designer is unknown (the account itself asked who made it), and a "byJWXN" item is visible in the concept's sidebar.
- **Date:** 2026-02-27
- **Link:** https://x.com/TheAppleDesign/status/2027394686332387520 (1,992 likes, ~133K views)
- **Design move:** The sidebar is a single frosted pane over a blurred wallpaper. The selected row is a raised glass pill with a bright edge highlight. Back/forward sits in one capsule, and the hover state on content is a faint glass tile.
- **Idea for MBGA:** For the selected sidebar row, consider a glass-like pill (a subtle top highlight plus inner stroke) instead of an accent fill. Keep it on the system sidebar material rather than stacking a second glass layer (see #16).

### 16. Liquid Glass do's and don'ts, from Apple's SwiftUI Lab (notes by Flo)
- **Who / what:** Flo writes Code (iOS developer), notes from a WWDC25 lab with Apple engineers.
- **Date:** 2025-06-12
- **Link:** https://x.com/FloWritesCode/status/1933207441543438390 (638 likes)
- **Design moves:**
  - Avoid glass overlapping glass.
  - Avoid glass in anything that scrolls.
  - Use glass to grab attention.
  - Group glass in `GlassEffectContainer`.
  - Move tinting into the content that scrolls behind the bar.
  - "System uses less colors now; avoid arbitrary tinting."
  - No current API for a fluidly draggable tab-bar-like component.
- **Idea for MBGA:** Glass belongs on the command bar and maybe a floating find bar, not on tab rows. Space colour should tint the content behind the sidebar, not the controls.

### 17. "Where work happens, the interface should feel instant" (shadcn)
- **Who / what:** shadcn (creator of shadcn/ui).
- **Dates:** 2026-09-06 and 2026-09-07
- **Links:**
  - https://x.com/shadcn/status/2096648867567608084 (2,962 likes, ~390K views): "To understand how little you should animate, open the app you use every day and count how many things are animated. Almost none."
  - https://x.com/shadcn/status/2096797264370950464 (1,681 likes): "Menus, alerts, dialogs. They open instantly … Where work happens, the interface should feel instant."
- **Idea for MBGA:** Do an "animation audit". Every animation on a daily path (tab switch, Cmd+T, sidebar list updates, menus) needs a reason, or it goes.

---

## Part 2: Design galleries

### 18. Brave vertical tabs concept (Layers.to)
- **Who / what:** Agustín Ruiz (DesignOps Lead at Brave, per his Layers profile), "Vertical tabs design update for Brave".
- **Date:** 2025-09-23
- **Link:** https://layers.to/layers/cmfwqrkim000gjo09msmmmieu (labelled "still work in progress"; not a shipped Brave design)
- **Design move:** One frame shows three states of the same window:
  1. Full sidebar. The address field and controls are merged into the top of the tab column, with a favourites grid, named groups marked by coloured left bars, and a footer of utility icons.
  2. A collapsed icon rail that keeps each group's coloured bar beside its favicons.
  3. Fully hidden.

  The description says the tab bar "unifies all the elements that were also available in the address bar".
- **Idea for MBGA:** Add a three-state sidebar (full → rail → hidden). In the rail, keep the space and folder colour as a thin vertical bar beside the favicons so orientation survives the collapse.

### 19. Other Layers finds (lower value)
- "Orbita – Browse Assistant" motion concept, barlydesign, 2025-03-26: https://layers.to/layers/cm8pb6d6x000kjp0bwhdwyziz
- "Eternal" AI-browser branding, inarastudio, 2025-12-14: https://layers.to/layers/cmj5o7v6j001yjr0e8tqt92gd. This is mostly brand, not UI.
- Command-menu explorations by Dmitry Sergushkin, 2025-11 to 2026-01, useful as ⌘K styling references, e.g. https://layers.to/layers/cmi46dliw0002l10e3x8utioq

---

## Part 3: Designer write-ups

### 20. Charlie Deets, "The strategy behind Dia's design" (Browser Company)
- **Date:** 2025-06-17. Announced at https://x.com/charliedeets/status/1935349747340165346
- **Link:** https://browsercompany.substack.com/p/the-strategy-behind-dias-design
- **Key moves:**
  - "Tuesday morning" familiarity: anyone can switch at 10 am on a Tuesday.
  - "Elevated" craft only on familiar features.
  - One obvious way to do each task.
  - A "novelty budget" spent mainly on chat.
  - The page's colour extends up into the active tab UI.
  - The address bar shows the page title plus domain, and hovering reveals the full, editable URL. The bookmark and site-settings buttons appear only on hover.
  - No update banners. Updates apply when the app is idle or backgrounded.
  - The profile selector appears only when profiles are used.

### 21. Dustin Senos (Head of Design, The Browser Company) on Dive Club, "Designing Dia"
- **Date:** 2025-06-20
- **Links:**
  - Episode summary and transcript: https://pod.wave.co/podcast/dive-club--556f9cbd-ac35-4833-98cc-6d19a1ee9091/dustin-senos-designing-dia-the-ai-native-web-browser-c89f532a
  - Newsletter: https://dive-club.beehiiv.com/p/apologies
  - Caveat: the details come from an auto-generated transcript summary.
- **Key moves:**
  - Dia's window is layered as a **scrim → tab wrapper → platter**, and the URL bar and tab take the web content's colour.
  - "The product should sit in the background, let the content come forward."
  - Theming is much subtler than Arc's.
  - A single smart input won over separate chat and URL bars.
  - The input changes colour and "poofs" when its mode changes.
  - The team designs mostly in motion prototypes (Swift, Origami), not static mocks.
  - "The most innovative things, once you see them, they just look obvious."

### 22. Rauno Freiberg, "Invisible Details of Interaction Design"
- **Date:** July 2023 (older, but foundational; Rauno previously worked on Arc)
- **Link:** https://rauno.me/craft/interaction-design
- **Key moves:**
  - High-frequency keyboard and mouse actions (command menus) should have little or no animation. Removing motion from a bookmarking tool made it feel faster.
  - macOS context menus appear instantly, fade out subtly, and flash the chosen item.
  - Destructive gestures commit on release, so users can change their mind.
  - Animations must be interruptible.
  - Scale deltas should apply immediately, not after a threshold.
  - Screen corners are "magic corners" (Fitts's law).

### 23. Emil Kowalski, animation essays
- **Dates:** the pages are undated.
- **Links:**
  - https://emilkowal.ski/ui/7-practical-animation-tips
  - https://emilkowal.ski/ui/you-dont-need-animations
  - https://emilkowal.ski/ui/great-animations
- **Key moves:**
  - Keep UI animations under 300 ms. A 180 ms select feels more responsive than a 400 ms one.
  - Use ease-out for things entering and leaving.
  - Pressed buttons scale to 0.97.
  - Never animate from `scale(0)`; start at 0.9 or higher (0.93 in the example).
  - Popovers scale from their trigger (origin-aware).
  - After the first tooltip, others open instantly.
  - A ~2 px blur can mask imperfect transitions.
  - Keyboard actions repeated "hundreds of times a day" should never animate. Raycast's menu has no open animation.
  - Animate only `transform` and `opacity`.

### 24. Jakub Krehel, "Details that make interfaces feel better"
- **Date:** undated
- **Link:** https://jakub.kr/writing/details-that-make-interfaces-feel-better
- **Key moves:**
  - **Concentric radius:** outer radius = inner radius + padding.
  - Icon swaps animate opacity, scale and blur.
  - Use interruptible transitions for interactions.
  - Exits are subtler than enters. For example, an exit can move only to −70% while fading and blurring 4 px (spring 0.45 s, bounce 0).
  - Enter text in staggered chunks: 8 px rise, 8 px blur, 80–100 ms stagger.
  - Use tabular numbers.
  - Align optically.
  - Use translucent layered shadows instead of borders: `0 0 0 1px rgba(0,0,0,.06)`, `0 1px 2px -1px rgba(0,0,0,.06)`, `0 2px 4px rgba(0,0,0,.04)`.
  - Give images a 1 px outline at 10% alpha.

### 25. Benji Taylor, "Family Values"
- **Date:** 2024-07-08
- **Link:** https://benji.org/family-values
- **Key moves:**
  - Three ordered pillars: simplicity (gradual revelation via dynamic trays), fluidity (motion shows where you're going), and delight (selective).
  - **Delight-Impact Curve:** the less often a feature is used, the more delight it can carry. Frequent features get only subtle touches.
  - Tab switches slide in the direction of the tab's position.
  - Text morphs ("Continue" → "Confirm").
  - A rare action (trashing tokens) gets a skeuomorphic bin with a sound effect.
  - Backup completion gets brief confetti.

### 26. Linear, design refreshes
- **Links:**
  - "Behind the latest design refresh" (Charlie Aufmann and Maxime Heckel), 2026-03-12: https://linear.app/now/behind-the-latest-design-refresh
  - "How we redesigned the Linear UI", 2024-03-28: https://linear.app/now/how-we-redesigned-the-linear-ui
- **Key moves:**
  - "Don't compete for attention you haven't earned."
  - "Structure should be felt not seen."
  - The navigation sidebar is "a few notches dimmer" than content.
  - Borders and dividers are softened or removed. Icons are fewer and smaller.
  - Palette shifted from cool blue-grey to a warmer, less saturated grey (too warm reads muddy).
  - 2024: themes are generated in LCH from just three inputs (base, accent, contrast) instead of 98 variables.

### 27. Apple, WWDC25 session 310 "Build an AppKit app with the new design", and haptics docs
- **Links:**
  - https://developer.apple.com/videos/play/wwdc2025/310/
  - Haptics: https://developer.apple.com/documentation/appkit/nsalignmentfeedbackfilter and https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager
- **Key moves:**
  - `NSSplitViewController` sidebar items get the glass material automatically. A custom `NSVisualEffectView` in the sidebar "will prevent the glass material from showing through".
  - Content can extend under the floating sidebar (`automaticallyAdjustsSafeAreaInsets` on the content item; `NSBackgroundExtensionView` mirrors and blurs artwork).
  - "Limit your use of Liquid Glass to the most important elements."
  - Put content inside `NSGlassEffectView.contentView`, never as a sibling. Group with `NSGlassEffectContainerView`.
  - Non-interactive toolbar items should avoid glass.
  - Don't hard-code control heights.
  - Scroll edge effects come in soft and hard variants.
  - Haptics: `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)` or `NSAlignmentFeedbackFilter`. Use them only for user-initiated actions, together with a visual cue, and sparingly.

---

## Principles of premium feel

1. **Speed is the luxury.** Daily, keyboard-driven actions get no animation, and tab open/close must feel instant.
   - Sources: Emil Kowalski, "You don't need animations"; Rauno, "Invisible Details"; Adam Stern (#2); shadcn (#17).
2. **Motion explains change, briefly.** Keep it under ~300 ms with ease-out. Start from 0.9 or higher (never `scale(0)`), scale from the trigger, keep it interruptible, and make exits softer than entrances.
   - Sources: Emil, "7 practical animation tips"; Jakub Krehel; Rauno.
3. **Put delight where usage is rare.** Onboarding, first-run automation and empty states can be expressive. Daily paths stay quiet.
   - Sources: Benji Taylor's Delight-Impact Curve; Dia tab clean-up's first-run-only animation (#5); George's onboarding (#13).
4. **Spend a novelty budget.** Be familiar by default ("Tuesday morning") and novel in one or two places.
   - Sources: Charlie Deets (#20); Dustin Senos (#21).
5. **Chrome recedes, content leads.** Page colour flows into the chrome, the sidebar is dimmer than content, and structure is felt, not seen.
   - Sources: Deets (#20); Senos (#21); Linear 2026 (#26).
6. **Native density.** Use macOS scale instead of an oversized custom scale, so more tabs and longer titles fit.
   - Source: Deets on Dia's sidebar (#1).
7. **Trustworthy automation.** Every action is visible the first time, reversible every time and predictable forever.
   - Source: Julia Roggatz (#5).
8. **Forgiving direct manipulation.** Dragged items stay centred under the cursor, morph when they leave their container, and commit on release.
   - Sources: Adam Stern (#2); Rauno.
9. **Stable, findable controls.** A toggle doesn't move between states, every layout toggle has a shortcut, and "collapsed" hides rather than shrinks.
   - Source: evowizz's Chrome teardown (#6).
10. **Materials with restraint.** System glass on the sidebar and top-level controls only. No glass on glass, no glass in scrolling content, and tint the content, not the controls.
    - Sources: WWDC25 session 310 (#27); Flo's SwiftUI Lab notes (#16).
11. **Precision micro-craft.** Concentric radii, tabular numbers, optical alignment, translucent hairline shadows instead of borders, and press scale 0.97.
    - Sources: Jakub Krehel (#24); Emil.
12. **Tactile and audio feedback, sparingly.** Haptic alignment ticks go only with a visual cue and only on user-initiated actions. Sound goes only on rare, meaningful actions (Family's trash sound).
    - Sources: Apple's NSAlignmentFeedbackFilter docs (#27); Benji Taylor (#25).
    - Caveat: none of the browser teams I found published anything on UI sound. Dia's "Sound on" refers to its launch video, so the sound evidence is thin.

---

## Top ideas for MBGA (ranked)

1. **Make daily actions instant and animation-free.**
   - ⌘T, ⌘W, Ctrl+Tab, space switching by shortcut, and command-bar open/close get no motion.
   - Mouse-driven row inserts or removals get at most a ~120 ms opacity/height change.
   - Do an animation audit against shadcn's "count the animations" test.
   - Sources: #2, #17, #23.
2. **Page-tinted chrome on a layered window.**
   - Treat the window as scrim → sidebar → content platter.
   - Sample the page's `theme-color` (or its top-edge colour via CEF) and tint the active tab card and URL field. The space colour becomes only a faint wash behind the sidebar.
   - Sources: #20, #21.
3. **Tab sleeping and archiving with Dia's trust rules.**
   - First time only, show a three-button card ("Not now ⎋ / Clean once / Clean daily ⏎") with favicons of the affected tabs.
   - On that first run, favicons fly into the Archived control and a "Slept 10 tabs" chip appears.
   - Always restorable, always opt-in.
   - Source: #5.
4. **A forgiving tab drag.**
   - The row centres under the cursor and neighbours make room with a spring.
   - Leaving the sidebar morphs the row into a live window thumbnail you can drop as a new window.
   - A trackpad haptic `.alignment` tick fires when crossing into Favorites, Pinned or a folder.
   - Sources: #2, #27.
5. **A favourites grid that lights up in brand colour.**
   - The active favourite's tile fills with its favicon's dominant or `theme-color`; others stay neutral.
   - Columns adapt to the count and never fall back to a single column.
   - Sources: #3, #6.
6. **A command bar that understands verbs.**
   - "split", "pin", "sleep", "new space", "move to…" resolve to actions above search results, with shortcut chips.
   - Open tabs show "Switch to Tab". The highlighted row uses the space colour.
   - Source: #9.
7. **Focus mode (⌘S) done carefully.**
   - Hide the sidebar and toolbar, and frame the page as one rounded platter.
   - The sidebar reveals on left-edge hover. It keeps tracking when the pointer slides past the window edge and never collapses while hovered.
   - Sources: #4, #8, #9.
8. **A three-state sidebar (full → rail → hidden) with fixed controls.**
   - The rail keeps each space's and folder's colour as a thin bar beside the favicons.
   - The toggle stays in one place and has a shortcut. Width and state persist per window.
   - Left/right placement is two clicks away in the sidebar's context menu.
   - Sources: #18, #6, #7.
9. **Liquid Glass the Apple way.**
   - Build the sidebar on `NSSplitViewController` so the system glass appears, and delete any custom `NSVisualEffectView` there.
   - Let the new-tab page and web content extend under the sidebar.
   - Use `NSGlassEffectView` only for the command bar and a few floating controls, grouped in a container.
   - Make the selected row a soft raised pill, not glass on glass.
   - Sources: #27, #16, #15.
10. **A native-density sidebar.**
    - Use macOS system font sizes and sidebar row metrics, a white selected card with a single soft shadow, and dividers that are barely there.
    - Make the sidebar slightly dimmer than content, and use warm, low-saturation neutrals.
    - Derive each space's whole palette from base + accent + contrast in LCH (OKLCH works too).
    - Sources: #1, #26.
11. **Spend the delight budget on the welcome/import sheet.**
    - Dim the desktop via a borderless window.
    - Grow the sheet out of an orb tinted with the first space's colour.
    - Stagger the headline in per character (spring plus blur), once only.
    - Sources: #13, #25.
12. **Micro-craft pass.**
    - Press scale 0.97 on sidebar buttons.
    - Popovers start at 0.95 and scale from their anchor, ≤200 ms ease-out.
    - Icon swaps (sleep/wake, mute) cross-fade with scale plus 2 px blur.
    - Concentric radii between the window, platter and cards.
    - Tabular numbers for tab and download counts.
    - Sources: #23, #24.

---

## Images

All files are in `docs/design-research/img/x-design/`. Video entries are frames I extracted from the posted videos.

| file | what it shows | source URL |
|---|---|---|
| `dia-sidebar-density-vs-arc.webp` | Arc vs Dia sidebar side by side: Dia's tighter, macOS-scale rows and white selected card | https://x.com/charliedeets/status/1942214876438421975 |
| `dia-pinned-grid-brand-color.webp` | Dia pinned-tab grid; the active tile (Spotify) fills with the brand colour | https://x.com/charliedeets/status/1986468332673937744 |
| `dia-tab-cleanup-prompt.webp` | First-run tab clean-up card with favicons and keyboard-hinted buttons (Esc / ⏎) | https://x.com/juliaroggatz/status/2052395823011397814 |
| `dia-tab-cleanup-icons-fly.webp` | Video frame: cleaned-up tabs' icons flying from the tab strip into their new home | https://x.com/juliaroggatz/status/2052395826534547631 |
| `dia-tab-drag-window-preview.webp` | Video frame: a dragged sidebar tab popping into a mini window preview outside the sidebar | https://x.com/adamstern_/status/1942215025956982885 |
| `evowizz-dia-sidebar-grid.webp` | Video frame: Dia sidebar with space tint, 4-column pinned grid and folder row (used to contrast with Chrome) | https://x.com/evowizz/status/2043631713490747537 |
| `helium-layout-switcher.webp` | Helium's Browser Layout submenu (Classic / Compact / Vertical) in the tab context menu | https://x.com/heliumbrowser/status/2023722252290662908 |
| `helium-zen-frameless-mode.webp` | Helium experimental zen/frameless mode: tab column plus a single rounded page frame, no toolbar | https://x.com/heliumbrowser/status/2042262823447769243 |
| `zen-space-tinted-sidebar.webp` | Video frame: Zen sidebar and frame tinted by the space's gradient theme | https://x.com/zen_browser/status/1970203987396960580 |
| `zen-command-bar-action.webp` | Video frame: Zen command bar resolving "split" to the New Split View action, with space-coloured highlight and shortcut chip | https://x.com/zen_browser/status/1970203987396960580 |
| `bunnylau-dia-swiftui-recreation.webp` | Video frame: SwiftUI recreation of Dia with favourites grid and tinted folder cards (not official Dia) | https://x.com/BunnyxStudio/status/2088207251979059467 |
| `georgecartridge-onboarding-blob.webp` | Video frame: Arc/Dia-style onboarding rebuilt in SwiftUI + AppKit, glassy orb growing over a dimmed desktop | https://x.com/georgecartridge/status/1934311696861954417 |
| `layers-brave-vertical-tabs-concept.webp` | Brave vertical-tabs concept (WIP): full sidebar, colour-barred icon rail and hidden states | https://layers.to/layers/cmfwqrkim000gjo09msmmmieu |
| `appledesign-glass-sidebar-concept.webp` | Fan concept of Liquid Glass on macOS (Finder): frosted sidebar pane, raised glass selection pill (designer unknown) | https://x.com/TheAppleDesign/status/2027394686332387520 |
