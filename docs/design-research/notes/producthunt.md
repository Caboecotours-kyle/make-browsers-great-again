# Product Hunt: browsers and browser-adjacent launches, late 2024 to Oct 2026

Researched 2026-10-21. Main sources: Product Hunt product and launch pages (read with a fetch tool; producthunt.com returns 403 to curl), hunted.space (a third-party PH launch tracker that keeps pages PH has taken down, and shows exact dates and comments), and makers' own sites linked from PH.

How to read the numbers:
- PH product pages show two unlabeled numbers per launch. In the PH launch list the comment count comes first and the upvote count second. I checked this against the Orion PH screenshot, which shows a speech bubble with 12 and an upvote arrow with 245. I've written them below as "N upvotes / M comments". Where a page shows only "points", that figure is the upvote count.
- "#N" is the PH daily rank unless marked otherwise.
- Some PH pages only give relative dates ("12d ago"). For those I worked the date back from 2026-10-21 and marked it "approx".
- Headless Chromium hung on every URL on this machine, even data: URLs, so I took no page screenshots. All images are gallery or maker-site assets.

Contents: 5 deep dives (Thravik, Dia, Horse, Raycast 2.0 and family, Pola), then 18 shorter entries, then the ranked ideas, then the image table.

---

## Deep dives

### 1. Thravik: "The native Mac browser that remembers"
- **Launch:** approx 2026-10-09 (PH shows "Launched 12d ago" and "Launched in 2026"). #35 of the day, 67 upvotes, 34 followers, no reviews yet. Maker: Ahmed Yacoub. [PH](https://www.producthunt.com/products/thravik)
- **Platform/engine:** Swift/SwiftUI on the system WebKit. Requires macOS 26+. Bridges WebKit to Chrome DevTools through an adapted open-source project, inspect-webkit (maker reply on PH). [PH](https://www.producthunt.com/products/thravik), [site](https://thravik.app/)
- **Why it matters for MBGA:** it is the closest analog on PH. It's a native Mac shell with Arc-style Spaces (each with its own colour, cookies and logins), a ⌘K bar, split view and tab hibernation, and it launched two weeks ago.
- **Distinctive UI decisions** (all from [thravik.app](https://thravik.app/) unless noted):
  - **Layout.** Tabs live in a vertical sidebar, with an optional horizontal top strip (the Tab layout setting offers "Sidebar" or "Top bar"). Spaces sit in a **dock at the foot of the sidebar** as round coloured tokens, with the active one ringed and a "+" at the end. ⌘B collapses the sidebar. Focus Mode (⌘⇧F) removes all chrome. See `thravik-sidebar-space-dock.webp`.
  - **Empty pinned area.** It's drawn as a dashed rounded rectangle with a pin glyph and the text "Drag tabs here to pin". The PH gallery shows the same element. See `thravik-sidebar-space-dock.webp`.
  - **Four starter Spaces** ship with the app: Work, Personal, Research and Travel.
  - **Per-Space look.** Each Space has its own colour, icon, **vividness** and **grain** ("Make each Space yours"). Settings → Appearance has seven themes (Thravik, Space, Calm, Paper, Midnight, Vivid, Sunset), Light/Dark/Automatic/**Scheduled** mode, and a **window colour source: Page / Space / Custom / Neutral**. Page takes "the brand color of the site in front". Private windows keep their own colour. There's a **Color intensity** slider and a toggle to use the macOS accent colour. See `thravik-appearance-settings.webp`.
  - **⌘K Command Bar.** Results come in sections: **Tabs, Websites, Spaces, Actions, Archived tabs, Memory**. Each row has a rounded icon tile, a title with a secondary line ("Command", or URL · Space), and a right-aligned shortcut hint (⌘2, ⌘3…). The selected row shows a ↩ chip. The panel is a tinted glass sheet over the page. See `thravik-command-bar.webp`.
  - **Memory.** You type "Remember…" in ⌘K and describe the page in your own words. Answers come with numbered sources, and one tap returns you to the page. Text is stored "only what you actually read", encrypted with AES-256-GCM using a device-only Keychain key. It's off by default. Private tabs and banking, health, webmail and password-manager sites are excluded. Retention defaults to 90 days, and the settings pane has "View & delete memory" and "Delete all". See `thravik-memory-recall.webp`. [PH maker comment](https://www.producthunt.com/products/thravik), [site](https://thravik.app/)
  - **Tab hibernation.** Idle background tabs release their web view and content process. On return they restore history and scroll position "**behind a fading snapshot**". Under memory pressure the oldest tabs go first.
  - **Link Preview.** ⇧-click opens the link in a floating glass panel over the current page.
  - **Split View.** Up to four resizable panes. ⌘⇧D pairs the page with its neighbouring tab.
  - **Ask Page.** On-device answers through Apple Intelligence.
- **PH comments:** few so far. One user asked for a no-login option and other desktop OSes. The maker said login is for usage analytics and that a no-login option "could consider for the future". In one reply the maker calls the product "Redent", which looks like a naming slip. [PH](https://www.producthunt.com/products/thravik)
- **Ideas for MBGA:**
  - Wake slept tabs behind their last snapshot and cross-fade to live content (details in the top ideas below).
  - Add sections and an **Archived tabs** section to the ⌘T/⌘L bar. MBGA's "Clear" already archives Today tabs, so they just need to be searchable.
  - Add "Vividness" and "Grain" controls to each space's colour editor.
  - Draw the empty pinned area as a dashed "Drag tabs here to pin" drop target.

### 2. Dia: "The AI browser where you can chat with your tabs"
- **Launch:** 2025-06-12, #2 of the day, 624 upvotes. Rated 4.8 from 8 reviews, 867 followers. Team listed: Chris Messina, Josh Miller, dustin senos. [PH](https://www.producthunt.com/products/dia-browser)
- **Platform:** Mac, Chromium-based (The Browser Company, which Atlassian has acquired according to a PH forum post by Messina on the same page).
- **Distinctive UI decisions:**
  - **Horizontal tabs on top**, a step back from Arc's sidebar. Pinned sites appear as icon-only tabs at the left of the strip, and a "Chats" tab is pinned beside them. Under the strip, a breadcrumb reads "Dia / <chat title>". The chat itself is a page in a tab: the prompt is a pill on the right, sources show as a 2×2 grid of document cards, and the composer floats at the bottom with a round accent send button. The window is tinted warm beige. See `dia-chat-in-tab.webp`. [diabrowser.com](https://www.diabrowser.com/)
  - **Generated documents as designed pages.** "The Friday Brief" uses a serif headline over a painting, the date and time set vertically in the margins, and a "Let's do it →" sticker. "Sarah's Week Recap" is a Swiss-style report. Both carry Share / Chat buttons in the toolbar. See `dia-morning-brief.webp`. [diabrowser.com](https://www.diabrowser.com/)
  - The privacy panel uses plain On/Off rows: Block trackers, Personalize new chats, Memory, Block ads, Share content data. [diabrowser.com](https://www.diabrowser.com/)
  - Pricing, from a Messina forum post on the PH page dated "2 months ago" (≈Aug 2026, approx): free "Better browser" with no AI, $20/mo "Better answers", $100/mo "Better day". [PH](https://www.producthunt.com/products/dia-browser)
- **What commenters said** ([PH reviews and comments](https://www.producthunt.com/products/dia-browser)):
  - Praise: "Saving your prompts as Skills is great!". "Dia has been the fastest and most stable AI browser I've tried." "context is super useful".
  - Criticism, nearly all about tabs: "tab implementation, which feels like a significant downgrade". "Only thing I don't like is tab switching, Arc had perfected that why change". The top comment (Michael Tigas, 18 upvotes) asks for Arc's left-sidebar tabs back, and another user asks for Arc's sidebar and profile management.
- **Ideas for MBGA:**
  - The loudest PH feedback on Dia is that users miss Arc's sidebar. That backs MBGA's sidebar-first choice, so don't trade it for a top strip.
  - Borrow Dia's typography instead: give MBGA-generated pages (new tab, an empty space, the "Clear"/archive summary) an editorial treatment, with a big date set in a serif or New York face and a calm layout. Don't use a default system list.

### 3. Horse: "The Organised Browser" (late-2024 launch)
- **Launch:** 2024-10-29, #3 of the day, 716 upvotes / 83 comments, hunted by Gabe Perez. [hunted.space](https://hunted.space/product/horse/launches/horse-browser) PH's own page shows 700 points and lists Chromium under "Built with". [PH](https://www.producthunt.com/products/horse)
- **Platform:** Chromium per PH "Built with". The site doesn't state OS or engine. Two-person team: Pascal Pixel (design and engineering) and Elly McKeown. [hunted.space](https://hunted.space/product/horse) / search results
- **Distinctive UI decisions** ([browser.horse](https://browser.horse/)):
  - **Trails replace tabs, bookmarks and history.** "Open a link and Horse puts the new page directly beneath it." Trails grow downward in visit order, can be named, and can carry emoji. The sidebar is an indented tree of favicon + title + greyed site name. See `horse-trails-sidebar.webp`.
  - **Keyboard tree navigation:** ⌘⇧↑/↓ selects the Trail above or below, ⌘⇧← collapses or moves to the parent, ⌘⇧→ expands, ⌥L collapses everything except the current Trail, ⌘⇧⌥↑/↓ moves a Trail, ⌘⌥T makes a subtrail, ⌘⌥⇧T a sidetrail.
  - Each window has its own expand/collapse state, but Trails are shared across windows.
  - **Export:** dragging a Trailhead out produces Markdown, with pages in order and links still clickable.
  - **Onboarding** is four steps: "Start with a question", "Open what looks useful", "Follow your curiosity", "Jump anywhere". The site adds: "There are no folders to prepare and no tab housekeeping before you begin."
  - Pricing: the site says "14-day free trial, then $70 a year". Other listings disagree: SourceForge says $40/yr and a 2024 PH commenter mentions $20, so the price has changed over time.
- **What commenters said:**
  - Praise: "The 'trails' concept works great for me, I love the interface." "Organizing pages by project feels way more natural than the usual browser setup". [PH](https://www.producthunt.com/products/horse), [hunted.space](https://hunted.space/product/horse/launches/horse-browser)
  - Criticism: "Horse is kind of a one-trick pony (sorry)". "on it's own I think it still leaves a lot of things to be solved". "Can't find the download - is there really no way to try it before dropping $20". One commenter pointed out that NetCaptor had the "trails" idea 25 years earlier.
  - The maker confirmed that nested pages aren't cached, trading reload speed for memory. [PH](https://www.producthunt.com/products/horse)
- **Idea for MBGA:** add opener-based nesting to **Today** only, so pinned tabs and folders stay hand-organised.
  - A tab opened from a link sits one indent under its opener, with a disclosure chevron.
  - Copy the ⌘⇧←/→ collapse/expand shortcuts and ⌥L "collapse others".
  - "Copy as Markdown" on a parent row exports the trail.
  - Collapsed children are natural candidates for sleeping, which fits MBGA's memory goal.

### 4. Raycast 2.0 and family (command-palette reference)
- **PH launches** ([PH launches list](https://www.producthunt.com/products/raycast/launches)):

  | Launch | Date | Result | Upvotes / comments |
  |---|---|---|---|
  | Raycast 2.0, "The next generation of Raycast is here" | 2026-09-11 | #4 | 336 / 16 |
  | Raycast for Windows | 2025-11-21 | #1 | 460 / 41 |
  | Raycast for iOS | 2025-05-01 | #1 day, #2 week | 845 / 53 |
  | Raycast Focus, "block distracting apps and websites" | 2025-01-17 | #1 day, #2 week | 971 / 91 |
  | Raycast Notes | 2024-11-07 | #2 day, 2024 Golden Kitty | 1,046 / 93 |

  The PH launch pages themselves didn't expose comment text.
- **Design decisions in 2.0** (["The New Raycast"](https://raycast.com/blog/the-new-raycast), Thomas Paul Mann, 2026-05-14, beta for macOS Tahoe and Apple Silicon):
  - "every pixel is new".
  - Liquid Glass is used "in tasteful ways to enhance the functional nature of a launcher", so the app can "sit naturally inside macOS Tahoe while preserving the professional feel".
  - Root search now mixes files, folders and contacts with commands, so "The thing you're looking for is usually just one or two letters away". It runs on a custom indexer.
  - Quick AI and AI Chat share one composer.
- **Visual anatomy of the root search** (`raycast2-root-search.webp`):
  - A large borderless search field with a placeholder and a right-aligned "Quick AI ⇥" hint.
  - Section headers ("Favorites", "Suggestions") in small grey type.
  - Rows show a coloured icon, title, grey subtitle and a right-aligned type label ("Command", "Application"). The selected row is a soft filled capsule with inline shortcut keycaps.
  - A footer bar holds "Open Command ↩ | Actions ⌘K".
  - The window is dark smoked glass over a soft monochrome background.
- **Earlier design principles** (["A fresh look and feel"](https://raycast.com/blog/a-fresh-look-and-feel), 2022-07-19):
  - "The search bar is at the center of Raycast. Almost every interaction goes through it."
  - A bottom action bar "consolidated actions, toasts, and navigation titles".
  - Outline icons with a bolder stroke.
  - An optional Compact Mode.
- **Ideas for MBGA:**
  - Rebuild the command bar's anatomy on this pattern: section headers, a type label on the right of each row, and a **footer action bar** (left: context or toast; right: "Open ↩ · Actions ⌘K").
  - ⌘K inside the bar opens per-result actions: copy link, open in other space, pin, close.
  - Take the principle "glass only where it serves the function": transient floating surfaces get glass, and lists stay legible.

### 5. Pola Browser: "Organized browser", then "Productivity, your way"
- **Launches:**
  - 2025-09-20, #3, 308 upvotes / 42 comments.
  - 2026-01-25, #4, 228 upvotes / 20 comments.
  - 509 followers, no reviews. Maker: Matteo Ricupero. [PH](https://www.producthunt.com/products/pola-browser), [PH forum](https://www.producthunt.com/p/pola-browser/pola-browser-2)
- **Platform:** macOS 15.4+, Mac App Store, 22.3 MB. Engine not stated anywhere I found (I'm unsure). Price €19.99/yr or €49.99 lifetime. [App Store](https://apps.apple.com/app/pola-browser/id6749057114), [polabrowser.com](https://polabrowser.com)
- **Distinctive UI decisions:**
  - **Start page as a feature tutor.** The new tab shows a large faint "Pola" wordmark over a 2×4 grid of bordered cards, each with an icon, a title and a one-line how-to: "Pin tabs and folders: Right-click any tab…", "Profile Management", "Research Mode: Toggle it in the bottom of the sidebar…", "Floating Tabs: Click the PiP icon…", "Sidebar Browser (AI or any URL): Press Cmd+L…", "Web Actions", "Extensions (experimental)", "Settings". A right-hand **sidebar webview** holds ChatGPT or any URL. See `pola-start-page-tips.webp`. [PH gallery](https://www.producthunt.com/posts/pola-browser)
  - **Floating Tabs:** always-on-top, resizable tabs. Since v0.45.0 they open in their own native window. [App Store](https://apps.apple.com/app/pola-browser/id6749057114)
  - **Research Mode:** "automatically creates a visual tree of your browsing". [App Store](https://apps.apple.com/app/pola-browser/id6749057114)
  - Version history gives the UI timeline: site-themed background (0.26.13, 2025-12-08), site-based colours (0.28.3), "fluid animations for tabs, sidebar, and window interactions" plus a hover sidebar and swipe gestures (0.33.0), toolbar moved into the sidebar (0.43.x), and a new rounded look with a loading bar (0.45.0). [App Store](https://apps.apple.com/app/pola-browser/id6749057114)
- **What commenters said** ([PH forum thread](https://www.producthunt.com/p/pola-browser/pola-browser-2), paraphrased by the fetch tool):
  - Praise: floating tabs and multi-window use, Bitwarden/Proton Pass support, EU-hosted analytics, Keychain integration.
  - Criticism: one user said the UI "felt rough and not like a polished modern macOS app". The same user questioned **Google Drive sync instead of CloudKit** and said the password manager was basic. Others found the extension list limited and asked whether a paid browser is justified.
- **Ideas for MBGA:**
  - **Floating tab:** move a tab's CEF view into an `NSPanel` (`.floating` level, non-activating, resizable), exempt it from sleeping, and add a "Return to sidebar" button.
  - **A one-time feature-tip grid** on the first empty Today/new tab. Each card should name its real shortcut (⌘T, Ctrl+1…9, two-finger swipe, ⌘S), and the grid should disappear once the user has used those features.
  - Pola's criticism is a warning: PH users quickly spot non-native polish and odd platform choices, such as Drive instead of CloudKit.

---

## Breadth: other launches

### OMEGA Ω: "3.6MB browser that never tracks, profiles, or sells data"
- **Launch:** 2026-01-18, **#1 of the day**, 412 upvotes, 545 followers. Maker: Michel Valenzuela. [PH](https://www.producthunt.com/products/omega-fastest-lightest-browser-ever)
- **Platform:** native Swift + WebKit on macOS. Amnesia Mode uses `WKWebsiteDataStore.nonPersistent()`.
- **UI:**
  - The new tab is a large thin clock with the date under it and a "Where to?" field, all over a dark aurora gradient.
  - The toolbar's ⋮ opens a **glass control panel**. It contains: a "Security Shield" segmented control (Standard / Fortress), a "Page View" zoom slider with −/+ and "Reset Zoom", an Amnesia Mode row, and then Favorites, History, Settings, Shortcuts and Quit. See `omega-glass-control-menu.webp`.
  - The maker says the toggles and slider are hand-built "glass" elements, because Liquid Glass was easier to use on iOS than on macOS.
- **⚠️ Name collision:** OMEGA's first PH gallery image (`https://ph-files.imgix.net/43dac6d0-2b8d-42d2-b9f9-da2c90bf64eb.jpeg`) has the headline "**MAKE BROWSERS GREAT AGAIN**", which is this project's name. The owner should know about this before any public launch. I saw it in the gallery image myself.
- **Comments:**
  - Praise: "3.6MB is tiny." "Clean philosophy…"
  - Criticism: "This is vibe coded, right?" "Funny but sloppy" (a leftover AI system message was found on the website). "neat concept but I'm not touching this with a 10 foot pole". Messina asked about extensions and passkeys. Users asked about older macOS, since it fails on 13.2.1.
- **Idea:** a site-controls popover from the address/command bar. Use a segmented control for per-site sleep policy ("Auto / Keep awake"), a zoom slider with Reset, and permission toggles, all in one glass panel.

### Orion 1.0 (Kagi): "WebKit. Extensions. Privacy. Pick all three."
- **Launch:** 2025-11-26, #4, 245 upvotes / 12 comments, hunted by Chris Messina. The first Orion launch was 2022-06-06 (142 upvotes). [PH](https://www.producthunt.com/products/orion-2), [hunted.space](https://hunted.space/product/orion-2/launches/orion-1-0)
- **Platform:** native macOS on WebKit, with Chrome and Firefox extension support.
- **UI (PH gallery):** vertical tabs appear as a **translucent overlay panel** floating over the page. The page stays full-width and blurs underneath. The panel has a segmented row of tab-type icons and a "1 Tab" count. See `orion-translucent-sidebar.webp`.
- **Comments:**
  - Praise: "Fast, privacy-first, and supporting extensions across Safari, Chrome, and Firefox is a huge win".
  - Scepticism: "Does Orion handle Figma/design tools well…?" "'Zero telemetry' is a bold claim…" "How is the paid version special?" [hunted.space](https://hunted.space/product/orion-2/launches/orion-1-0)
- **Idea:** when MBGA's sidebar is hidden (⌘S) and revealed by hovering the edge, make it a floating glass overlay with a shadow and no page reflow, as in this screenshot.

### Zen Browser: "Beautifully designed, privacy-focused" (Aug 2024; context only)
- **Launch:** 2024-08-25, #4, 253 upvotes. Rated 4.8 from 9 reviews. [PH](https://www.producthunt.com/products/zen-browser)
- **Platform:** Firefox (Gecko), open source.
- **UI:**
  - The window is frosted and lets the desktop show through.
  - An **Essentials** grid of 3×2 rounded favicon tiles sits above the tab list.
  - Workspace emoji dots sit at the sidebar foot.
  - An empty tab shows only blurred glass. See `zen-glass-sidebar.webp`.
  - Reviewers praise "Zen Glance" (page previews), split view, workspaces and hiding the tab and favourites bars.
- **Criticism:** multi-window sync bugs, an occasional crash while video plays in the background, and an unsigned macOS build that shows a "damaged" error.
- **Idea:** let empty space be calm glass that shows the desktop, rather than a white page. Notarize from day one: PH users notice "damaged app" warnings.

### Nook: "Fast, focused, and open, a new WebKit browser for Mac"
- **Launch:** 2025 (exact date not shown), 86 upvotes, #9, not featured. [PH](https://www.producthunt.com/products/nook-an-open-source-arc-alternative), [hunted.space](https://www.hunted.space/product/nook-an-open-source-arc-alternative/launches/nook)
- **Platform:** open source (GPL-3.0 per AlternativeTo), WebKit, macOS.
- **UI (PH gallery):** a deep-blue glass sidebar with a URL field, a 3-up favourites row, spaces ("Personal", "Active Issues") and an empty-state box glyph.
- **Comments:** "It already runs better!" and glad to have "Safari animations back". "neat UI!" Others asked about macOS 13 support and whether it will be an AI browser.
- **Idea:** commenters notice system-native animation curves ("Safari animations"). Use default SwiftUI springs and AppKit animations, not custom easing.

### Web (nuance-dev): "A free macOS AI browser"
- **Launch:** 2025 (exact date not shown), #10, 140 upvotes. [PH](https://www.producthunt.com/products/web-macos-ai-browser-free)
- **Platform:** open-source native SwiftUI browser with local MLX models.
- **UI:** an AI side panel with a status header ("AI Ready · Local AI · Private & Secure", or a "Preparing AI… Loading MLX model (66s)" progress card), plus a "Page context available · 18 words" chip.
- **Comments:** "love how fast and native it feels." "I'd love the glazing style UI."
- **Idea:** whenever MBGA does slow background work (an import, waking a heavy tab), show an honest inline status card with a real number.

### Deta Surf: "A browser, file manager, and AI assistant in one clean app"
- **Launches:** 2024-12-12, #3, 338 upvotes / 32 comments. Open-source beta on 2025-10-22, 156 upvotes. Rated 4.3 from 9 reviews. [PH](https://www.producthunt.com/products/deta)
- **UI (PH gallery):** notebooks drawn as **coloured books on a desk**, "Surflets" (small generated apps), vertical tabs, dark mode, and a command input with "@ to mention tabs, notebooks or sources". See `deta-surf-features.webp`.
- **Review praise:** "With separate contexts for my personal projects vs work, I'm able to focus in on one area."
- **Idea:** in the command bar, let "@" scope a search to a space or folder, for example "@Work figma".

### Strawberry: "The self-driving browser"
- **Launches:** Strawberry 2 on 2025-04-22, **#1 day and #1 week**, 840 upvotes / 235 comments. Strawberry 3 on 2025-10-14, #3, 347 upvotes / 45 comments. Rated 4.8 from 13 reviews. [PH](https://www.producthunt.com/products/strawberry)
- **Reviews:**
  - Praise for a visible agent you can "watch, guide, pause, and replay".
  - Criticism tags: "slow performance (3)" and "not as smooth as traditional browsers (2)".
- **Idea:** if MBGA ever automates anything, keep it visible and interruptible. Otherwise not relevant to the visual design.

### Opera Neon: "A browser for the agentic web"
- **Launch:** 2025, 47 upvotes on PH (hunted.space: 51 upvotes, #34). [PH](https://www.producthunt.com/products/opera-neon), [hunted.space](https://www.hunted.space/product/opera/launches/opera-neon)
- Announced 2025-05-28 [Opera press](https://press.opera.com/2025/05/28/opera-neon-the-first-ai-agentic-browser). Rolled out in Oct 2025 at $19.99/mo [AlternativeTo](https://alternativeto.net/news/2025/10/opera-s-new-ai-agentic-browser-neon-is-now-rolling-out-with-a-subscription-model/).
- **UI (PH gallery):**
  - A near-black window over a grainy iridescent glow.
  - A tiny three-item mode rail on the left (Chat / Do / Make).
  - The empty state is one line, "What can Neon make for you?", above a single composer. See `opera-neon-empty-state.webp`.
- **Idea:** a space with no Today tabs could show a single centred "Where to?" field over the space's colour, with a subtle grain. No tiles, no news.

### Comet (Perplexity): "A browser for agentic search by Perplexity"
- **Launch:** 2025-06-15, **#1 of the day**, 368 upvotes / 14 comments. The PH listing was later taken down. [hunted.space](https://www.hunted.space/product/comet-browser-by-perplexity), [TechCrunch](https://techcrunch.com/2025/07/09/perplexity-launches-comet-an-ai-powered-web-browser/)
- **Comments:** mostly about waitlist access and a privacy question: "How do you address user concerns about privacy, given that Comet collects and analyzes personal data".
- Little UI material to take from it.

### BrowserOS: "The Open Source Agentic Browser"
- **Launch:** 2025-10-26, #3, 203 upvotes / 6 comments. Listing later taken down. [hunted.space](https://www.hunted.space/product/browseros-2)
- Chromium fork with local or BYO-key models. The comments are about bringing your own LLM. No UI insight.

### Oasis Browser for Mac (Kahana)
- **Launch:** 2026-05-27, #4, 278 upvotes / 84 comments. [PH](https://www.producthunt.com/products/kahana)
- **UI:** an Edge-like icon rail on the right edge and an AI panel. The new tab has a photo background and favicon tiles.
- A review praises a "split window" for a PDF next to notes.

### Reframe: "Surf like it's 1999"
- **Launch:** 2026-06-20, #2, 246 upvotes. [PH](https://www.producthunt.com/products/reframe-7)
- **Platform:** Electron/Chromium.
- **UI:** reskins the browser as Safari 1.0, Netscape 4.8, Firefox 1.0 or IE5, including a spinning throbber. A Wayback Mode is in the Help menu.
- **Comments:** "LOVE the retro vibe" and "Memory unlocked". One commenter asked why not make it a daily-driver theme.
- **Idea:** probably skip. It does show that PH rewards a single strong visual idea.

### Pickle Browser: "Browser for your agent. Runs local in a window you can see"
- **Launch:** approx Aug 2026 ("2mo ago"), #26, 86 upvotes. Real Chromium, MCP-driven. [PH](https://www.producthunt.com/products/pickle-browser)
- No UI lessons.

### Side Space: "#1 AI Assistant for Your Tabs" (Chrome side-panel tab manager)
- **Launches:** 2024-11-16, #2, 357 upvotes / 39 comments. Side Space 2.0 on 2025-11-22, #3, 260 upvotes / 34 comments. [PH](https://www.producthunt.com/products/side-space)
- **UI:** tab groups as **coloured capsule rows with a count badge** (YouTube 3, AI/Tech 16…) that expand in place. Sort and search sit at the top.
- **Review:** "it would be even better with a simpler layout… clearer controls".
- **Idea:** show a muted tab-count badge on collapsed MBGA folders.

### Arcmark: "Your bookmarks, attached to any browser as a sidebar"
- **Launch:** 2026-02-20, #5, 220 upvotes. Native Swift/AppKit, open source, follows the browser window through the Accessibility APIs. [PH](https://www.producthunt.com/products/arcmark), [GitHub](https://github.com/Geek-1001/arcmark)
- **UI:** workspace pills across the top of the sidebar ("Settings · Katalog · Work"). The **whole sidebar is tinted in the workspace colour** (cyan, lavender). Favourites form a 4-up tile row above the folder tree. See `arcmark-workspace-sidebar.webp`.
- **Comments:**
  - "genuinely clever".
  - Messina suggested an **auto-hide mode that pops over when the cursor reaches the screen edge** (MBGA already does this).
  - "what if I have too many bookmarks?" The maker answered: split them into workspaces.
- **Idea:** confirms the Arc pattern of a fully tinted sidebar per space. MBGA should keep tint intensity adjustable (see Thravik).

### Peek: "Live website previews in your Mac menu bar"
- **Launch:** 2025-12-16, #12, 100 upvotes / 13 comments. [hunted.space](https://hunted.space/product/peek-16/launches/peek-1082)
- **What it does:** hover the menu bar to see a live site preview. The "Killer feature: Scroll position memory", so each clip always shows the same region, such as a chart.
- **Comments:** questions about memory growth over time, and a request for a desktop widget instead.
- **Idea:** hovering a favourite tile for about 600 ms could show a live or last-snapshot preview popover. Pinned tabs could optionally remember a scroll anchor when they reset.

### Small new-tab launches (low traction, for completeness)
- TabQuest: new-tab dashboard (bookmarks, tasks, notes). Launched 2025-01-23 and relaunched 2026-03-16, with single-digit votes. [PH](https://www.producthunt.com/products/tabquest)
- CalmTab for Firefox: clocks, sticky notes, quotes, and Workspaces that open tab groups in containers. Launched 2025-11-27, 8 upvotes. [PH](https://www.producthunt.com/products/calmtab-for-firefox/launches/calmtab)

These suggest PH users don't reward busy new-tab dashboards. The browsers that rank (Thravik, OMEGA, Neon) ship sparse start pages.

---

## Top ideas for MBGA (ranked)

1. **Wake slept tabs behind a fading snapshot.** Before MBGA unloads a tab (10-minute idle or the 8-tab cap), grab a bitmap of the CEF view and store it with the scroll position in the Rust core. When the tab is selected, show the snapshot in an `NSImageView` at once, reload underneath, and cross-fade (about 150 ms) on first paint. This hides the cost of MBGA's main memory feature. Source: Thravik ("restore history and scroll position behind a fading snapshot"), [thravik.app](https://thravik.app/).
2. **Rebuild the ⌘T/⌘L bar with sections, type labels and a footer action bar.**
   - Sections: Tabs, Pinned, Favorites, Spaces, Actions, **Archived** (the Today tabs that "Clear" put away).
   - Each row: a rounded icon tile, title, grey subtitle (URL · Space) and a right-aligned shortcut hint.
   - Footer: "Open ↩ · Actions ⌘K". ⌘K opens per-result actions (copy link, move to space, pin).
   - Sources: Thravik ⌘K (`thravik-command-bar.webp`), Raycast 2.0 root search (`raycast2-root-search.webp`), [Raycast 2022 action bar](https://raycast.com/blog/a-fresh-look-and-feel).
3. **⇧-click Link Preview as a floating glass panel.** Load the link into a transient CEF browser inside a rounded `NSVisualEffectView` card over the current page. ⌘↩ (or a "Open as tab" button) promotes it to Today, Esc dismisses it, and it uses the current space's profile. Sources: Thravik Link Preview ([site](https://thravik.app/)), Zen Glance (praised in [PH reviews](https://www.producthunt.com/products/zen-browser)).
4. **Per-space "Vividness" and "Grain", plus a window-colour source.**
   - Add two sliders to the space editor: tint saturation, and a noise overlay (a tiled noise image at 2–4% opacity over the sidebar material).
   - Add a global setting "Window colour: Space / Page / Neutral" with an intensity slider. Page takes the site's theme-color.
   - Sources: Thravik appearance settings (`thravik-appearance-settings.webp`), Pola's site-based colours ([App Store](https://apps.apple.com/app/pola-browser/id6749057114)).
5. **Glass only on transient surfaces.** Use glass for the command bar, link preview, hover-revealed sidebar and site popover. Keep the pinned list, Today list and settings opaque or barely translucent for legibility. Ship a site-controls glass popover with a segmented control (sleep: Auto / Keep awake), a zoom slider with Reset, and permission toggles. Sources: [Raycast 2.0](https://raycast.com/blog/the-new-raycast) ("Liquid Glass… in tasteful ways"), OMEGA panel (`omega-glass-control-menu.webp`).
6. **Opener nesting in Today (optional).**
   - A child tab sits one indent under the tab that opened it.
   - ⌘⇧←/→ collapses or expands, ⌥L collapses the others.
   - "Copy trail as Markdown" exports a branch.
   - Collapsed children are first in line to sleep.
   - Source: Horse Trails ([browser.horse](https://browser.horse/), `horse-trails-sidebar.webp`). Caveat from PH: "one-trick pony", so keep it opt-in.
7. **Designed empty states.**
   - Empty pinned area: a dashed rounded "Drag tabs here to pin" target ([Thravik](https://thravik.app/)).
   - First empty Today/new tab: a one-time 2×3 grid of feature cards, each naming its real shortcut ([Pola](https://www.producthunt.com/posts/pola-browser)).
   - Space with no tabs: a single centred "Where to?" field over the space tint with grain (OMEGA new tab, Opera Neon `opera-neon-empty-state.webp`).
8. **Floating tab.** Add "Float" to the tab context menu. It moves the CEF view into a non-activating, always-on-top, resizable `NSPanel`, exempt from sleep, with a "Return to sidebar" button. It's useful for video and calls. Source: Pola Floating Tabs ([App Store](https://apps.apple.com/app/pola-browser/id6749057114)).
9. **Opt-in local "Remember…" search.**
   - Store readable text only for pages the user stayed on (a dwell threshold). Keep it in an SQLite FTS5 table in the Rust core, encrypted with a key held in the Keychain.
   - Off by default. Excludes banking, health, webmail and password-manager sites by category, plus private spaces. 90-day retention, with "View & delete".
   - Surface results as a "Memory" section in the command bar.
   - Source: Thravik Memory ([PH maker comment](https://www.producthunt.com/products/thravik), `thravik-memory-recall.webp`).
10. **Hover peek on favourites, and scroll-anchor memory for pinned tabs.**
    - Hovering a favourite tile for about 600 ms shows a popover with the last snapshot (live if the tab is awake).
    - Pinned tabs that reset to their URL can optionally return to a saved scroll anchor.
    - Source: Peek ([hunted.space](https://hunted.space/product/peek-16/launches/peek-1082)).
11. **Keep the sidebar.** The loudest Dia feedback on PH is about losing Arc's left-sidebar tabs ("Arc had perfected that why change"). Spend design effort on the sidebar rather than on alternatives. Source: [PH Dia reviews](https://www.producthunt.com/products/dia-browser).
12. **Launch hygiene that PH commenters check:**
    - A notarized build (Zen "damaged" error).
    - Clear minimum macOS (asked of Nook, OMEGA and Thravik).
    - Native animations (Nook: "Safari animations back").
    - Apple-native sync choices, CloudKit not Drive (Pola criticism).
    - No AI leftovers on the website (OMEGA "vibe coded" pile-on).
    - Check the **"Make Browsers Great Again" overlap with OMEGA's PH hero image** before launching.

---

## Images

All files are in `docs/design-research/img/producthunt/`. WebP, max 1600 px wide.

| file | what it shows | source URL |
|---|---|---|
| thravik-command-bar.webp | Thravik ⌘K bar: tinted glass sheet, "Tabs" and "Actions" sections, icon tiles, subtitles, right-aligned ⌘2/⌘3 hints, ↩ chip on the selected row | https://thravik.app/assets/detail-command.jpg |
| thravik-sidebar-space-dock.webp | Thravik sidebar: Space title, dashed "Drag tabs here to pin" target, a tab group, the space dock of round coloured tokens at the foot | https://thravik.app/assets/detail-sidebar.jpg |
| thravik-appearance-settings.webp | Thravik Settings → Appearance: 7 theme swatches, Automatic/Light/Dark/Scheduled, window colour Page/Space/Custom/Neutral, intensity slider, Sidebar vs Top bar layout | https://thravik.app/assets/appearance-settings-01.jpg |
| thravik-memory-recall.webp | Thravik "Remember…" query in ⌘K returning numbered source pages (PH gallery) | https://ph-files.imgix.net/21806ee9-ee43-4a37-9759-c50ec73b840a.png |
| pola-start-page-tips.webp | Pola new tab: feature-tip card grid under a faint wordmark, sidebar with folders, right sidebar webview (ChatGPT) | https://ph-files.imgix.net/dba2e5b5-8927-4ac7-a775-341b516a7221.png |
| omega-glass-control-menu.webp | OMEGA: glass control panel (Standard/Fortress segmented control, zoom slider, Amnesia Mode) and a clock + "Where to?" new tab | https://ph-files.imgix.net/12a79172-459a-42e6-a477-411486a1aa9c.jpeg |
| orion-translucent-sidebar.webp | Orion 1.0: vertical tabs as a translucent panel floating over a full-width page | https://ph-files.imgix.net/a8121f2d-ecf5-483f-956d-ea3a6a2f4e28.jpeg |
| zen-glass-sidebar.webp | Zen: frosted window, Essentials favicon grid, workspace emoji at the foot, blurred empty content | https://ph-files.imgix.net/58376184-142e-4dde-bb3c-6ae6302f8fb0.webp |
| horse-trails-sidebar.webp | Horse: Trails sidebar, an indented tree of pages grouped by search/task | https://ph-files.imgix.net/75a54b57-57d4-42bd-b1ec-c519d7be0b64.png |
| dia-chat-in-tab.webp | Dia: top tab strip with icon-pinned sites and a "Chats" tab, breadcrumb, chat-as-page with source cards and floating composer, warm window tint | https://www.diabrowser.com/_next/image?url=%2F_next%2Fstatic%2Fmedia%2Fdia-reads-03.aff7fb54.png&w=3840&q=80 |
| dia-morning-brief.webp | Dia "The Friday Brief": editorial generated page with serif headline, vertical date and time in the margins | https://www.diabrowser.com/_next/image?url=%2F_next%2Fstatic%2Fmedia%2Fdia-reads-01.47a110ff.png&w=3840&q=80 |
| raycast2-root-search.webp | Raycast 2.0 root search: smoked-glass window, section headers, type labels, keycap hints, "Open Command ↩ / Actions ⌘K" footer | https://raycast.com/uploads/blog-new-raycast/app.png |
| opera-neon-empty-state.webp | Opera Neon: black window, Chat/Do/Make mode rail, single-prompt empty state over a grainy glow | https://ph-files.imgix.net/ae2692a6-7249-48f4-8545-a75f4b7ecef6.png |
| deta-surf-features.webp | Deta Surf feature grid: vertical tabs, Surflets, dark mode, "@ mention tabs/notebooks" command input | https://ph-files.imgix.net/441a5aee-5c44-4332-a2ef-114d04662dce.png |
| arcmark-workspace-sidebar.webp | Arcmark: workspace pills on top, sidebar fully tinted in the workspace colour, favourites tile row, folder tree, docked to Chrome | https://ph-files.imgix.net/eaebff52-44b3-4166-98e6-69ddf9d6680c.png |
