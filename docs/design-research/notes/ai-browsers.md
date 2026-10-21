# The Arc lineage and the AI-browser wave: design research for MBGA

Researched 2026-10-21. Covers Arc, Dia, ChatGPT Atlas, Perplexity Comet, Opera Neon, Microsoft Edge (Copilot Mode, then Copilot in Edge), Gemini in Chrome, and newer entrants (Aside, Strawberry, BrowserOS, Genspark, Fellou, Donut). Every claim has a source link. "Observed" means I read it off a screenshot in `img/ai-browsers/`, not off text. Things I could not confirm are marked **unverified**. Pixel values read off screenshots are estimates and are labelled "eyeballed".

**Where things stand in October 2026**

| Browser | Engine / platform | Launched | Status on 2026-10-21 |
|---|---|---|---|
| Arc | Chromium, Swift UI on Mac; macOS, Windows | macOS public 2023-07-25 | Maintenance mode since May 2025. "Receives Chromium updates only" ([arc.net](https://arc.net/)) |
| Dia | Chromium; macOS (Apple silicon), Windows build exists | Public 2025-10-09 | Active, weekly releases. Mac 1.53.0 on 2026-10-15 ([changelog](https://www.diabrowser.com/changelog)) |
| ChatGPT Atlas | Chromium via OpenAI's "OWL" layer, SwiftUI/AppKit UI; macOS | 2025-10-21 | **Shut down 2026-08-09** ([9to5Mac](https://9to5mac.com/2026/07/09/openai-is-discontinuing-chatgpt-atlas-its-standalone-desktop-browser/)) |
| Perplexity Comet | Chromium; Mac, Windows, iOS, Android | 2025-07-09 | Active, free ([perplexity.ai/comet](https://www.perplexity.ai/comet)) |
| Opera Neon | Chromium; macOS, Windows | First users 2025-09-30 | Active. $19.90/month for agent features; free plan for outside agents since 2026-08 ([Opera blog](https://blogs.opera.com/news/2026/08/your-ai-agents-can-use-opera-neon-free-of-charge/)) |
| Edge Copilot Mode | Chromium; Windows, macOS | 2025-07-28 | **Retired 2026-05-13** and folded into Edge ([Edge blog](https://blogs.windows.com/msedgedev/2026/05/13/new-updates-to-edge-across-desktop-and-mobile/)) |
| Gemini in Chrome | Chrome; Mac, Windows, ChromeOS, iOS | US desktop 2025-09-18 | Active. Side panel and "auto browse" since 2026-01-28 ([9to5Google](https://9to5google.com/2026/01/28/gemini-chrome-side-panel-more/)) |

**The big picture.** AI browsers peaked in 2025, then started to consolidate. OpenAI killed Atlas after nine months and said the user base was small ([9to5Mac, 2026-07-10](https://9to5mac.com/2026/07/10/with-chatgpt-atlas-shutting-down-here-are-the-ai-browsers-people-actually-use/)). Microsoft retired Copilot Mode as a separate mode. The products still standing (Dia, Comet, Chrome with Gemini) keep core browsing familiar and add AI as one button, one panel and an `@`-mention. Meanwhile Dia spent most of 2026 shipping Arc's sidebar, pinned tabs, swipeable profiles and an Arc importer. So the Arc-style shell MBGA is building is the part of this category that lasted.

---

## 1. Arc (The Browser Company)

- **Platform / engine:** Chromium (Blink, V8). The Mac UI is written in Swift ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))).
- **Dates:** Announced 2022-04-19. Public on macOS 2023-07-25. Windows 11 version 2024-04-30. "Arc 2.0" put on hold in October 2024. Development stopped in May 2025 ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))). The homepage now says Arc "receives Chromium updates only" and calls Dia "the next evolution of Arc" ([arc.net](https://arc.net/)).

### Distinctive UI decisions
- **Everything in one left sidebar.** Address field, favorites, pinned tabs and open tabs all live in a left panel instead of a top tab strip ([Tom's Guide](https://www.tomsguide.com/news/the-arc-browser-is-here-to-replace-chrome-and-cure-your-tab-chaos)).
- **"Zero chrome" layout.** Observed in `arc-sidebar-zero-chrome.webp`:
  - Traffic lights, a sidebar toggle and back/forward/reload share one row at the top of the sidebar. There is no separate title bar or toolbar.
  - The URL is a rounded, filled pill showing only the domain (`photogallery.camera`), with copy-link and site-settings icons inside it.
  - Favorites are a 4-across grid of rounded square tiles holding favicons only.
  - Then a folder list, a hairline divider, "+ New Tab", and the open tabs. The active tab is a white raised pill with a soft shadow.
  - The bottom of the sidebar holds only an archive icon, page dots for spaces, and "+".
  - The web page sits in an inset card with rounded corners. A thin margin of sidebar color (eyeballed ~6–8 px) frames it, so the page looks like an object placed inside the window.
- **Spaces as color.** Observed in `arc-space-gradient.webp`: the whole window frame, sidebar included, is filled with the space's gradient (yellow to coral here). Sidebar text stays dark and bold, and the active tab's pill is tinted to match. Space dots at the bottom show which space you are in. A review found by search says each space gets a color, solid or gradient, plus noise/grain and an icon: "For every Space you create, you get the option of assigning it a colour, noise to the sidebar, and an icon". It is one of several Medium reviews (e.g. [this one](https://medium.com/@fundamentalised/arc-browser-review-love-browsing-the-internet-again-afa4ee182aad)). Medium blocked direct reading, so **which article it came from is unverified**. The theme picker screenshot below backs up the color/noise/grain controls. Arc's homepage pitches "Spaces and Profiles" and "Split View" together ([arc.net](https://arc.net/)).
- **Theme picker as a toy.** Observed in `arc-theme-picker.webp`: a floating rounded palette with a light/auto/dark switch at the top, a 2D canvas where you drag color dots (bigger dot means more weight), a row of swatches, a wavy "noise" slider and a grain dial. Users pick a color or gradient during install ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))), so personalising starts on day one.
- **Tabs clean themselves up.** Untouched tabs move to the Archive after 12 hours, and the timing is adjustable ([Arc release notes, 2021-12-16](https://resources.arc.net/hc/en-us/articles/20498463803799)).
- **Command bar.** Cmd+T searches tabs, history and actions at once ([Blake Crosley design study, search snippet](https://blakecrosley.com/blog/design-study-arc), **page 404 when fetched**). One guide says the command bar replaced the omnibox ([allthings.how](https://allthings.how/15-arc-browser-tips-tricks-to-make-web-browsing-effortless/)).
- **Little Arc and Peek.** Little Arc is a minimal window for quick lookups and for links opened from other apps. Peek previews a link without leaving the current tab ([allthings.how](https://allthings.how/15-arc-browser-tips-tricks-to-make-web-browsing-effortless/), [Latenode](https://latenode.com/de/blog/arc-browser-im-ueberblick-sollten-sie-ihn-nutzen)). Both are secondary sources.
- **Motion.** A developer reverse-engineered Arc's search-bar animation in SwiftUI: a brief color flash, a slight scale-down, then an expanding shadow ([Medium, Paul Bancarel](https://medium.com/@bancarel.paul/from-concept-to-code-reproducing-arc-browsers-search-bar-animation-in-swiftui-cd9fdb60e7a5)). This comes from a search snippet; Medium blocked direct reading, so exact timings are **unverified**.

### Why it felt premium (praise)
- Medium reviews found by search say Arc's Mac builds feel "fluid and native" because they are written in Swift, with "sleek animations and refined interface elements", and praise how smooth the onboarding animations are. Candidates: [criticalmynd](https://criticalmynd.medium.com/arc-browser-a-compelling-but-controversial-newcomer-871d0746b14c), [asifkalluru](https://medium.com/@asifkalluru/i-tried-the-arc-browser-for-a-week-here-are-my-thoughts-ca887c0f79ce). Medium blocked direct reading, so **attribution to a specific article is unverified**.
- The Verge's David Pierce called it "full of big new ideas" ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))). MacStories said Arc Search's animations are "lovely to see" and also fast ([MacStories](https://www.macstories.net/reviews/arc-search-for-iphone/)).

### Complaints
- **Hard to learn.** "almost nothing in Arc works the way you expect" ([Thurrott, Windows review](https://www.thurrott.com/software/browsers/296096/arc-browser-for-windows-review)).
- **Account required.** BGR objected to having to create an account before using the browser ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))).
- **Slows down over time.** A post found by search says that once Arc's cache bloats it "becomes a memory hog" and sidebar animations start stuttering. It is a Medium post, possibly [this one](https://medium.com/@devongnall/arc-browser-review-its-great-but-i-m-going-back-to-safari-cb4511e25532); **attribution unverified**.

### What happened
Josh Miller's letter of 2025-05-26 ([Substack](https://browsercompany.substack.com/p/letter-to-arc-members-2025)):
- "Arc was simply too different, with too many new things to learn, for too little reward." He calls this the **"novelty tax"**.
- "Arc lacked cohesion" and "We built too much, too quickly."
- Usage data: **"Only 5.52% of DAUs use more than one Space regularly"**, 4.17% use Live Folders, and 0.4% use Calendar Preview on Hover. For comparison, about 40% of Dia's DAUs chat with tabs.
- Arc can't be open-sourced without also open-sourcing ADK, the internal kit that Dia is built on too.

Atlassian then bought The Browser Company for $610M in cash, announced September 2025 ([BetaNews](https://betanews.com/2025/09/05/atlassian-moves-into-ai-browsers-with-610-million-purchase-of-the-browser-company/)).

### Ideas for MBGA
- **Copy the inset content card.** Keep a tinted sidebar background that also frames the page on the other three sides, and clip the CEF view to a rounded rect. In AppKit: a container `NSView` with `wantsLayer`, `layer.cornerRadius` and `masksToBounds`, plus a small inset, sitting on the window background. This one decision does most of the work of Arc's "object in a window" look.
- **Keep each space's color in a single token.** Drive the sidebar fill, the active-tab tint, the new-tab-page wash and the accent from one per-space color/gradient (plus grain). Arc's whole-window gradient is the most recognisable "premium" signal in the screenshots.
- **Make spaces optional.** Only 5.52% of Arc's DAUs used more than one space regularly. MBGA must feel complete with a single space, so hide the space dots until a second space exists.

---

## 2. Dia (The Browser Company, Atlassian)

- **Platform / engine:** Chromium. macOS 14+ on Apple silicon ([Wikipedia via search](https://en.wikipedia.org/wiki/Dia_(web_browser))). A Windows build was at 1.2.0 by 2026-10-15 ([changelog](https://www.diabrowser.com/changelog)); its launch date is **unverified**.
- **Dates:** Invite beta in mid-2025 (the design-strategy post is dated 2025-06-17). Open to everyone on Mac on 2025-10-09. Dia Pro at $20/month from 2025-08-06 ([Wikipedia via search](https://en.wikipedia.org/wiki/Dia_(web_browser))). Mac 1.53.0 shipped 2026-10-15 ([release notes](https://www.diabrowser.com/release-notes)).

### Design philosophy (primary source: ["The strategy behind Dia's design"](https://browsercompany.substack.com/p/the-strategy-behind-dias-design), Charlie Deets, 2025-06-17)
- **"Tuesday morning" test.** The goal is that anyone can switch to Dia "at 10am on a Tuesday morning". Core browsing stays where any browser user would expect it.
- **Novelty budget.** "In Dia we spend our novelty budget on our Chat features." Animation and color are saved for chat. The browser chrome stays conventional.
- **"Single obvious way"** to do each task, with no duplicate UI.
- **Minimal chrome by default:**
  - No update banners; updates install while the app is in the background or idle.
  - Bookmark and site-settings icons appear only when you hover the URL.
  - The profile picker appears only if you actually use profiles.
- **Title-first URL bar.** "we display the page title to help you recognize the page more clearly." The domain stays visible, and hovering shows the editable URL.
- **Page color flows into the tab.** "We extend the color of the page up into the active tab UI." Observed in `dia-active-tab-page-color.webp`: the active tab takes the page's dark slate color and merges into the toolbar and page, while inactive tabs sit on a light gray strip.
- **One routed input.** A custom ML model decides whether input is a URL, a Google search, an LLM-only answer, or an LLM answer that uses the web.
- **Visible context.** `@`-mention tabs, history or bookmarks. Several mentioned tabs form an animated "pile" that fans out on hover; the post calls it "mostly superfluous" but says it makes the value of context obvious. Opening the chat sidebar plays a brand animation that "swells into the view". Skill replies get their own styling.

### Distinctive UI (observed)
- **`dia-chat-mention-pile.webp`** (horizontal-tab mode):
  - The profile appears as a colored "Personal" pill at the far left of the tab strip, next to favicon-only pinned apps.
  - The chat is a page in a tab, with the address bar showing a breadcrumb: "Dia / Museums for Kids".
  - Mentioned tabs stack as tilted cards above the user's message bubble. "Read moma.org … and 28 more" is a collapsible sources line, and the composer floats at the bottom.
  - The window background is a warm gradient, and the overall chrome is very thin.
- **`dia-sidebar-2026.webp`** (sidebar mode, from a 2026 homepage video):
  - The sidebar is warm and translucent. Favorites are three wide rounded tiles (Gmail, Calendar, Slack).
  - Below them: tabs, tab groups with disclosure chevrons, "+ New Tab", and a "Chats" section pinned to the bottom of the sidebar.
  - The page is an inset rounded card, Arc-style. The toolbar shows a sidebar toggle, nav buttons and a "Made with Dia / The Tuesday Brief" breadcrumb, plus a single "Share" pill.
- **`dia-split-view-tab-bar.webp`:** two panes, each with its own nav bar and close button. The tab strip mixes a profile pill with pinned favicons, a colored tab group ("Italy Hotels" with a count), and a "Chat with Tabs" pill in the toolbar.

### The 2026 changelog: Dia sweating details (all from [diabrowser.com/changelog](https://www.diabrowser.com/changelog))
- **Window, toolbar and theming**
  - 1.15.0 (2026-01-23): the new tab page "uses your profile color" with "a gradient animation under the command bar". Corners refined for Tahoe Liquid Glass.
  - 1.28.0 (2026-04-23): the toolbar color now matches the page's sticky header, so the top of the window blends into the page.
- **Sidebar**
  - 1.28.0 (2026-04-23): tighter tab spacing, and tab groups are neutral-colored by default.
  - 1.29.0 (2026-04-30): the sidebar rubber-bands when dragged past its min or max width ("inspired by Things").
  - 1.52.0 (2026-10-08): Arc-style pinned tabs outside groups. An Active Tab Indicator keeps the active tab's favicon visible when the tab scrolls out of view. A one-click button closes all unpinned tabs.
  - 1.53.0 (2026-10-15): sidebar and split-view transitions smoothed to "reduce layout jumps and visual seams", and web content stays anchored in place.
- **Tab groups**
  - 1.10.1 (2025-12-18): new groups take their color from the site's favicon or theme color.
  - 1.20.0 (2026-02-26): a shimmer animation plays when Dia auto-names a group. Each split pane gets its own nav and bookmark bars.
  - 1.51.0 (2026-10-01): auto-generated group icons can drop the emoji for simpler icons.
- **Tabs and drag**
  - 1.4.0 (2025-11-06): haptic feedback when dragging tabs.
  - 1.7.0 (2025-12-01): hovering a tab offers Pin, Bookmark, Split with Tab and Open Chat.
  - 1.8.0 (2025-12-04): double-click a tab to rename it. Closing a tab no longer flashes the background page.
  - 1.14.0 (2026-01-15): custom per-tab emoji or icon.
- **Launch and rendering**
  - 1.13.1 (2026-01-08): favicons are pre-warmed so they appear instantly on launch. The side panel no longer flickers between tabs.
  - 1.10.1 (2025-12-18): fewer dark-mode white flashes when switching tabs.
- **Focus and cleanup**
  - 1.3.1 and 1.5.0 (late 2025): Focus Mode via Cmd+S, or by fully collapsing the sidebar.
  - 1.38.0 (2026-07-02): unused new tab pages close themselves when you switch apps or lock the screen.
- **Command bar**
  - 1.0.1 (2025-10-09): a shimmer plays when you `@`-mention items, and a toolbar offers mentions for actions and formats.
  - 1.51.0: the Ctrl+Tab switcher now shows 5 tabs instead of 10.
- **Profiles and import**
  - 1.43.1 (2026-08-06): swipe between profiles. Dia's own post says you can import Profiles/Spaces from Arc or Chrome ([AlternativeTo, 2026-08-04](https://alternativeto.net/news/2026/8/dia-browser-lets-you-swipe-between-profiles-and-import-from-arc-and-chrome/)).
  - Windows 1.2.0: importing from Arc switches Dia to sidebar tabs. Mac 1.53.0: Arc's GitHub Live Folders come over as Dia Live Groups ([release notes](https://www.diabrowser.com/release-notes)).

### Features
Chat with tabs, Skills (saved prompts run with `/`), Memory, Morning Brief, Live Groups (GitHub, Notion and Drive), Splits that remember recurring meeting layouts, and connected apps such as Slack, Notion, Gmail and Calendar ([diabrowser.com](https://www.diabrowser.com/), [TechCrunch, 2025-11-03](https://techcrunch.com/2025/11/03/dias-ai-browser-starts-adding-arcs-greatest-hits-to-its-feature-set)).

### Praise / complaints
- **Praise:**
  - A reviewer found by search says Arc's optional sidebar is in Dia "and more refined than ever". The candidate sources were [Viget](https://www.viget.com/articles/the-dia-ai-browser/) and [Efficient](https://efficient.app/compare/toby-vs-dia); **attribution unverified**.
  - Skills are called the cleanest "describe it, save it as a command" implementation ([SupaSidebar, competitor-run blog](https://supasidebar.com/blog/dia-browser-mac-review-2026)).
- **Complaints:**
  - Cmd+T opens a chat box, which breaks Arc muscle memory ("a chat box, not a search field").
  - $20/month for Pro.
  - Atlassian ownership worries some users.
  - Spaces were missing until the 2026 profile work.
  - (All [SupaSidebar](https://supasidebar.com/blog/dia-browser-mac-review-2026); the author sells a competing app.)
- **Arc fans' wishes:** Miller said Dia would be "snappier, smarter, simpler by default w/ Pro mode" ([TechCrunch](https://techcrunch.com/2025/11/03/dias-ai-browser-starts-adding-arcs-greatest-hits-to-its-feature-set)).

### Ideas for MBGA
- **Show the page title in the URL field.** Show title + domain at rest and the editable URL on hover or focus (Dia design post).
- **Tint the active tab and toolbar from the page.** Read `theme-color`, or sample the top rows of the CEF frame. Animate the toolbar background to match, and cross-fade on tab switch (Dia tab color; Dia 1.28 toolbar match).
- **Ship a "details" checklist straight from Dia's changelog:**
  - Haptics on tab drag (`NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)`).
  - Rubber-band sidebar resize with a spring.
  - Favicon cache warm on launch, so the sidebar paints from Rust-core state before CEF is up.
  - No white flash on tab close or switch (keep the last frame until the next one is ready, and set the CEF background color from the page).
  - Pin a mini favicon for the active tab when it scrolls out of the sidebar list.
  - Animate sidebar collapse without moving the web content.

---

## 3. ChatGPT Atlas (OpenAI), discontinued

- **Platform / engine:** macOS only. Chromium runs in a separate process through **OWL ("OpenAI's Web Layer")**, and the browser UI was rebuilt in **SwiftUI, AppKit and Metal** ([OpenAI engineering post, 2025-10-30](https://openai.com/index/building-chatgpt-atlas), read via [36Kr](https://eu.36kr.com/en/p/3532529113963648) because openai.com returned 403).
- **Dates:**
  - Launched 2025-10-21.
  - Vertical tabs in November 2025, in a resizable left sidebar with multi-select drag ([Wikipedia](https://en.wikipedia.org/wiki/ChatGPT_Atlas)).
  - Tab groups 2026-01-21/22 ([9to5Mac](https://9to5mac.com/2026/01/22/you-can-now-group-tabs-on-openais-chatgpt-atlas-browser/)).
  - Auto-organize into groups on 2026-02-18, and multiple ChatGPT accounts each with its own profile on 2026-03-10 (release notes via [search](https://help.openai.com/en/articles/12591856-chatgpt-atlas-release-notes); direct fetch 403).
  - Discontinuation announced 2026-07-09, shut down 2026-08-09. Its features moved into the ChatGPT desktop app and a Chrome extension ([9to5Mac](https://9to5mac.com/2026/07/09/openai-is-discontinuing-chatgpt-atlas-its-standalone-desktop-browser/)).

### Distinctive UI decisions
- **Window chrome.** Observed in `atlas-agent-mode.webp`:
  - Tabs sit in the title-bar row.
  - The toolbar has a sidebar toggle and back/forward/reload, then a **centered domain-only** address ("simonwillison.net").
  - On the right is a bordered "Ask ChatGPT" pill that opens a chat panel on the right.
- **Agent mode visuals:**
  - The page gets a blue-white gradient glow overlay with sparkles, which Simon Willison called a "weird sparkle overlay effect".
  - A black tooltip ("Opening the first result") follows a fake cursor.
  - A dark floating bottom bar shows the task name with **Take control** and a red **Stop**.
  - The side panel streams step headers ("Opening the first result >") above the reasoning text ([Simon Willison, 2025-10-21](https://simonwillison.net/2025/Oct/21/introducing-chatgpt-atlas/)).
- **Chat in the address field.** "The main interface isn't a combo search/location field, but rather a chat/location field" ([Daring Fireball](https://daringfireball.net/2025/10/thoughts_observations_and_links_regarding_chatgpt_atlas)). A January 2026 update switched search results to vertical stacked links and added an "Auto" engine choice between ChatGPT and Google ([9to5Mac](https://9to5mac.com/2026/01/22/you-can-now-group-tabs-on-openais-chatgpt-atlas-browser/)).
- **Native settings.** Atlas has System Settings–style preferences. Gruber: "certainly better than Chrome-style 'settings in a web page tab'" ([Daring Fireball](https://daringfireball.net/2025/10/thoughts_observations_and_links_regarding_chatgpt_atlas)).
- **Emoji in tab groups.** The release note reads: "Tab Groups (they're slick and you can use emojis)" ([9to5Mac](https://9to5mac.com/2026/01/22/you-can-now-group-tabs-on-openais-chatgpt-atlas-browser/)).

### Engineering choices that matter for polish ([via 36Kr](https://eu.36kr.com/en/p/3532529113963648))
- **Fast first window.** The goal was startup in about a second, so Chromium loads asynchronously while the native window appears almost at once.
- **Stays smooth.** The target was hundreds of tabs with no dropped frames. A Chromium hang or crash doesn't take the app UI down.
- **How web content is embedded.** Each web view is a `CALayer` from Chromium's compositor, embedded in an `NSView` through `CALayerHost`. Pop-ups such as `<select>` menus and color pickers use the same path.
- **Input.** The Swift client turns `NSEvent`s into Blink input events itself. Unhandled events bounce back so the app's own shortcuts still work.

### Praise / complaints
- **Praise:** Willison found browser memories "particularly notable".
- **Complaints:**
  - Gruber: it "isn't particularly Mac-like", has no AppleScript, makes poor use of Apple Passwords, and "feels like … Chrome with a chat button bolted on" ([Daring Fireball](https://daringfireball.net/2025/10/thoughts_observations_and_links_regarding_chatgpt_atlas)).
  - Willison: agent mode was "like watching a first-time computer user painstakingly learn to use a mouse"; prompt-injection risk "insurmountably high".

### Ideas for MBGA
- **Native chrome first, engine second.** Show the window and sidebar right away from persisted state, and attach CEF views when they're ready. Atlas made this a stated goal.
- **If MBGA ever automates pages** (even for import or form fill), reuse the **glow + floating "Take control / Stop" pill** pattern. It is the most legible "something is acting on this page" signal in the category.
- **Native preferences window.** Put settings in a real SwiftUI window, never in a web page.

---

## 4. Perplexity Comet

- **Platform / engine:** Chromium. Mac and Windows at launch; iOS and Android since ([Comet page, 2026-03-11](https://www.perplexity.ai/comet); iPhone in March 2026 per [AppleInsider](https://appleinsider.com/articles/26/02/19/perplexitys-comet-ai-browser-is-coming-to-iphone-soon)).
- **Dates:**
  - Launched 2025-07-09 for Max subscribers at $200/month ([TechCrunch](https://techcrunch.com/2025/07/09/perplexity-launches-comet-an-ai-powered-web-browser/), [Engadget](https://www.engadget.com/ai/perplexitys-comet-ai-browser-is-available-now-for-200-per-month-180955616.html)).
  - Free worldwide from 2025-10-02, with a "background assistant" for Max users ([TechCrunch](https://techcrunch.com/2025/10/02/perplexitys-comet-ai-browser-now-free-max-users-get-new-background-assistant/)).

### Distinctive UI decisions
- **New tab page.** Observed in `comet-new-tab.webp` (dark theme):
  - A conventional top tab strip, and a toolbar whose omnibox placeholder reads "Ask anything or navigate…".
  - An "Assistant" button sits at the far right of the toolbar.
  - The page has a thin left rail with the logo at top and Account/Upgrade at the bottom.
  - A centered composer reads "Ask anything or @mention a tab", with three icon mode toggles (labels not visible; probably Search / Research / Labs, **unverified**) and attach, voice and send buttons.
  - Below it, a 4×2 grid of quiet quick-link chips, and at the bottom a single "Try Comet Assistant" pill.
- **Sidecar assistant.** A side panel sees the current page, so no copy-pasting is needed. While the AI is driving, a **blue border** surrounds the page and you can interrupt at any time ([PCWorld, 2025-09-30](https://www.pcworld.com/article/2922627/i-switched-from-chrome-to-an-ai-browser-and-got-an-imperfect-glimpse-of-the-future.html)).
- **Task inbox.** Observed in `comet-background-assistants.webp`:
  - A "Background Assistants" page with a "Launch a new task…" box and an "Unread (3)" toggle.
  - Each task is a card with a status glyph (orange "!" means **Action required**, teal check means done).
  - Draft output appears inline (an email with Send / Refine email / Skip) with "2m ago" and "Open full thread". TechCrunch says Perplexity calls it "mission control" ([TechCrunch](https://techcrunch.com/2025/10/02/perplexitys-comet-ai-browser-now-free-max-users-get-new-background-assistant/)).

### Praise / complaints
- **Praise:**
  - "Stripped down" Chromium that "doesn't get in your way".
  - A new tab page with a chat box instead of Edge's, which is "cluttered with viral junk" ([PCWorld](https://www.pcworld.com/article/2922627/i-switched-from-chrome-to-an-ai-browser-and-got-an-imperfect-glimpse-of-the-future.html)).
- **Complaints:**
  - Agents are "surprisingly slow"; the browser is "more of a flashy demo"; no sync at the time (PCWorld).
  - No vertical tabs or named workspaces beyond Chromium defaults ([SuperchargeBrowser, vendor blog](https://www.superchargebrowser.com/library/perplexity-comet-vs-chrome-extensions/)).
  - Prompt-injection research by Brave targeted Comet (cited in Willison's screenshot text).

### Ideas for MBGA
- **Calm new tab page:** one centered field, at most 8 quiet favicon chips, one optional hint pill, nothing else.
- **"Action required" pattern for background work.** Use one status glyph per long job (imports, downloads, tab-sleep reclaim reports) and collect them in a single panel instead of toasts.

---

## 5. Opera Neon

- **Platform / engine:** Chromium. Windows and macOS ([Opera blog, 2026-08](https://blogs.opera.com/news/2026/08/your-ai-agents-can-use-opera-neon-free-of-charge/)).
- **Dates:**
  - Shipped to first users 2025-09-30 ("Opera Neon ships" release notes on [operaneon.com](https://www.operaneon.com/); [TechCrunch](https://techcrunch.com/2025/09/30/opera-launches-its-ai-centric-neon-browser/)). A press image is dated May 2025 in its file metadata, so it was first shown in spring 2025 (**exact date unverified**).
  - No invite needed by 2025-12-11 ([TechRadar](https://www.techradar.com/ai-platforms-assistants/opera-neon-is-now-available-and-i-think-its-an-ai-subscription-worth-paying-for)).
  - MCP Connector 2026-03-31 ([Opera press](https://press.opera.com/2026/03/31/opera-neon-adds-mcp-connector/)), `opera-browser-cli` 2026-05-13 ([Opera blog](https://blogs.opera.com/news/2026/05/opera-browser-cli/)), and a free plan for connecting outside agents 2026-08 ([Opera blog](https://blogs.opera.com/news/2026/08/your-ai-agents-can-use-opera-neon-free-of-charge/)).

### Distinctive UI decisions
- **Three verbs.** The interface "revolves around three core ideas: Chat, Do, and Make" ([TechRadar](https://www.techradar.com/ai-platforms-assistants/opera-neon-is-now-available-and-i-think-its-an-ai-subscription-worth-paying-for)).
- **Tasks and Cards.** You get "Tasks" instead of tab groups and "Cards" instead of bookmarks (TechRadar).
  - Tasks are "contained workspaces of AI chats and tabs", which TechCrunch likens to tab groups plus Arc Spaces.
  - Cards are reusable, combinable prompts with a community store ([TechCrunch](https://techcrunch.com/2025/09/30/opera-launches-its-ai-centric-neon-browser/)).
- **Agent panel.** Observed in `neon-make-agent-panel.webp` (TechRadar screenshot):
  - Dark UI. The left column is the Make conversation, with a vertical timeline of step chips ("Searching", "Navigating to url") and "Thinking…".
  - The right is a floating rounded panel, **"Neon's Computer"**, showing a live, shrunken view of the page the agent is on, with "Neon is using Browser", the current URL, and a red-outlined **Stop Task**.
  - Below the live view is a numbered plan (0/4) with a spinner on the current step.
- **Visual language.** Official marketing uses film grain, blurred photographic gradients and a monospace label face (seen in Opera's press renders; not saved because they are illustrations).

### Praise / complaints
- **Praise:** "Neon does not just add an AI button to your toolbar and call it innovation"; it pushes "creation" over consumption (TechRadar).
- **Complaints:**
  - Slow, and lags Comet.
  - Tasks die if the Mac sleeps.
  - "The Make interface can be confusing."
  - $20/month makes success unlikely (TechRadar).

### Ideas for MBGA
- **Live mini-preview + plan list** for any multi-step job MBGA runs, such as "Import from Arc": show the current item and a checklist with a spinner on the current step. That beats an indeterminate progress bar.

---

## 6. Microsoft Edge: Copilot Mode (2025) → Copilot in Edge (2026)

- **Platform / engine:** Chromium. Windows and macOS.
- **Dates:**
  - Copilot Mode launched 2025-07-28 as an opt-in experimental mode ([How-To Geek via Yahoo](https://tech.yahoo.com/ai/articles/microsoft-edges-cursed-copilot-mode-170019222.html)). Its new tab was "a single input box that brings together chat, search and web navigation" ([TechRepublic](https://www.techrepublic.com/article/news-microsoft-edge-copilot-mode/)).
  - **Retired 2026-05-13.** Its features moved into regular Edge; Copilot Actions became "Browse with Copilot", limited to US Microsoft 365 Premium ([Edge blog](https://blogs.windows.com/msedgedev/2026/05/13/new-updates-to-edge-across-desktop-and-mobile/)).
  - The Copilot side pane was rebuilt on OneJS and live in Edge Stable on desktop by October 2026 ([PiunikaWeb, 2026-10-21](https://piunikaweb.com/2026/10/21/microsoft-is-rolling-out-a-redesigned-copilot-side-pane-inside-edge/)).

### Distinctive UI decisions
- **New tab page.** Observed in `edge-copilot-new-tab.webp`:
  - A greeting headline ("Hi Emily, ask me anything or let's find it online") over a large white rounded composer with "+", a "Smart" mode menu and a voice glyph.
  - A row of circular quick links, and a single "Recent browsing" Journeys card with "Hop back in".
  - Decorative flower art bleeds off both edges.
  - A slim icon rail on the left, and a "Chat" pill at the right of the toolbar.
- **Status inside the conversation.** Observed in `edge-copilot-pane-status.webp`:
  - The right pane has a warm peach tint. The user bubble has a soft gradient.
  - A bordered status chip reads "Searching your history", with an animated dot, before the answer streams in.
- **Indicators.** "When Copilot is active, you'll always see clear visual cues so you know when it's taking an action" ([Edge blog](https://blogs.windows.com/msedgedev/2026/05/13/new-updates-to-edge-across-desktop-and-mobile/)).
- **Journeys.** "grouping your browsing history into helpful topic cards on your new tab page" (opt-in).
- **The October 2026 pane** copies the new tab page layout, with prompt suggestions, a model selector and recent chats ([PiunikaWeb](https://piunikaweb.com/2026/10/21/microsoft-is-rolling-out-a-redesigned-copilot-side-pane-inside-edge/)).

### Praise / complaints
- How-To Geek compared Copilot Mode to an always-on Clippy, "an omnipresent assistant that will be present at all times during your browser experience", and flagged privacy concerns (Yahoo link above).
- PCWorld used Edge's new tab page as its example of clutter (see Comet).

### Ideas for MBGA
- **Resurface past work on the new tab page,** but only as **one** card, not a feed. Something like "Pick up where you left off" from the most recent sleeping tab cluster in the space. Edge shows it can be calm when there's just one card.
- **Inline status chips.** For long operations, use a single bordered chip with a moving dot and a verb ("Waking 12 tabs…").

---

## 7. Gemini in Chrome (Google)

- **Platform:** Chrome on Mac, Windows and ChromeOS, plus iOS.
- **Dates:**
  - Rolled out to US desktop users on 2025-09-18, announced at I/O 2025 ([Thurrott](https://www.thurrott.com/?p=326840), [BetaNews](https://betanews.com/2025/09/19/google-is-turning-chrome-into-an-ai-web-browser-powered-by-gemini/)).
  - Side panel, Gmail compose, Nano Banana image editing and **auto browse** (Pro/Ultra, US) on 2026-01-28 ([9to5Google](https://9to5google.com/2026/01/28/gemini-chrome-side-panel-more/), [MacRumors](https://www.macrumors.com/2026/01/29/google-chrome-gemini-side-panel-ai-features/)).
  - Android agentic features reported 2026-08 ([ProPakistani](https://propakistani.pk/2026/08/19/google-chrome-on-android-gets-agentic-browsing-image-generation-and-more/), **secondary**).

### Distinctive UI decisions
- **The entry point** is an "Ask Gemini" sparkle button at the top of the window, in the tab-strip row ([google.com/chrome/ai-innovations](https://www.google.com/chrome/ai-innovations/)).
- **Side panel.** Observed in `gemini-chrome-side-panel.webp`:
  - The panel sits on the right with only three small icons at the top (more, pop-out to floating window, close).
  - A two-tone greeting (blue name, gray question) sits low in the panel, with suggestion chips.
  - A **"Sharing 'New Tab'"** context chip appears above an input reading "Type @ to ask about a tab", with a model menu ("Pro").
  - The panel is **per tab**, and you can switch between floating and docked from the top-right ([9to5Google](https://9to5google.com/2026/01/28/gemini-chrome-side-panel-more/)).
- **AI Mode in the omnibox,** for follow-up questions straight from the address bar ([BetaNews](https://betanews.com/2025/09/19/google-is-turning-chrome-into-an-ai-web-browser-powered-by-gemini/)). The new tab page search box has an "AI Mode" chip (observed in the same screenshot).
- **Auto browse.** An auto-browse icon appears on the tab Gemini is using. **Take over task / Give back task** hands control back and forth. It pauses for confirmation before purchases, posting or other irreversible actions ([Google support](https://support.google.com/chrome/answer/16821166)).
- **Skills.** Save and reuse prompts in one click ([google.com/chrome/ai-innovations](https://www.google.com/chrome/ai-innovations/)), the same idea as Dia Skills and Neon Cards.

### Complaints
- The Register framed the January launch as Google wanting "to foist Gemini pane on Chrome users" ([The Register](https://www.theregister.com/2026/01/29/chrome_gemini_pane/)).
- A docked side panel "inevitably shrinks the browsing window" ([via search summary of 9to5Google/MobileSyrup](https://mobilesyrup.com/2026/01/28/new-gemini-in-chrome-brings-auto-browse-and-side-panel/)).

### Ideas for MBGA
- **Show context as a removable chip.** Any time MBGA uses the current page as context (for example "Save to folder…" or "Share"), show a small removable chip naming the tab, as in "Sharing 'New Tab'". It is honest and clear.
- **Per-tab side panels** that remember their open/closed state per tab, so the panel never jumps around when you switch tabs. Dia also fixed side-panel flicker in 1.13.1.

---

## 8. Newer and smaller entrants

- **Aside** (Y Combinator F25; Chromium):
  - Viral launch in June 2026 with 20K+ users in two weeks, a company-reported figure ([YC company page mirror](https://amanydv2112-suggest-orgs.hf.space/company/yc/aside)). Windows private beta from 2026-09 ([PiunikaWeb](https://piunikaweb.com/2026/09/07/aside-windows-beta-rolling-out/)).
  - The site's mockup shows:
    - A left sidebar with Bookmarks, Chats and Tabs, including an **"Agent tabs"** count.
    - An "Ask AI a task" box with `@` mentions and Search/Ask/Local/Guard modes.
    - A "Recent tasks" list with elapsed time ("Working for 3m 46s").
    - Scheduled tasks, and approval before payments, posts or messages ([aside.com](https://aside.com/)).
  - **Aside Vault** password manager: agents sign in by autofill, credentials are protected by the Secure Enclave, and every use is logged.
  - The founders say they "refused to ship AI slop" and even tried Liquid Glass inside Chromium ([founders' post, mirrored](https://youmind.com/ar/landing/x-viral-articles/aside-ai-browser-pivot-story)). 9to5Mac called it "a light alternative to Chrome or Comet" ([9to5Mac](https://9to5mac.com/2026/07/10/with-chatgpt-atlas-shutting-down-here-are-the-ai-browsers-people-actually-use/)). **No UI screenshot saved:** the site's mockup is HTML, and headless Chromium screenshots failed in this environment.
- **Strawberry** (Stockholm):
  - "Companions" are agents with names like "Sales Sally" that click, fill forms and extract data, with approval at irreversible steps.
  - Free tier of 500 credits/month; paid from $20/month ([Make Tech Easier](https://maketecheasier.com/strawberry-best-ai-browser-i-used/), [Luca Berton](https://lucaberton.com/blog/strawberry-browser-agentic-ai-2026/), [Toolradar](https://toolradar.com/tools/strawberry)). Open beta reported by [Computerwoche](https://www.computerwoche.de/article/4133687/strawberry-ki-browser-aus-schweden-geht-in-die-open-beta.html) (date **unverified**).
- **BrowserOS:** an open-source (AGPL-3.0) Chromium fork from YC. Bring your own model, including local Ollama/LM Studio. v0.44 in March 2026 ([browseros.com](https://www.browseros.com), [YC launch](https://www.ycombinator.com/launches/ORU-browseros-the-open-source-agentic-browser)).
- **Genspark AI Browser:** launched June 2025 as a "full-agentic browser" with ad blocking and a "Super Agent" on every page ([MainFunc blog](https://mainfunc.ai/blog/genspark_ai_browser)). No independent UI review found.
- **Fellou:** a persistent side-panel assistant that shows a step-by-step plan you can edit **before** it acts. Reviews are mixed: it works on simple forms, but loops on complex layouts ([The Tool Nerd](https://www.thetoolnerd.com/p/fellou-review-agentic-browser-thetoolnerd)).
- **Donut:** an "agentic crypto browser" for trading. $7M pre-seed in May 2025 ([Cointelegraph](https://cointelegraph.com/news/donut-7m-for-first-agentic-crypto-browser)) and $22M total later ([Decrypt via search](https://decrypt.co/?p=347204)). Not relevant to MBGA's audience.

---

## Patterns across the category

1. **One input, many destinations.** Dia routes input with ML, Atlas uses a chat/location field, Comet says "Ask anything or navigate…", Edge says "Type a link or ask anything", and Chrome has AI Mode in the omnibox. The pushback is real: Gruber didn't want chat answers in place of search results, and Arc users missed a pure search Cmd+T in Dia.
2. **`@`-mention a tab** is now standard (Dia, Comet, Edge, Gemini). So is a visible **context chip** naming what is shared (Gemini "Sharing 'New Tab'", Dia's tab pile).
3. **The AI lives in a right-hand panel; tabs stay on the left or top.** Every product keeps navigation and AI on separate edges.
4. **"Something is acting" signals:** a glow or border on the page (Atlas, Comet), a badge on the tab (Gemini), a floating Take control/Stop bar (Atlas), a live mini-view plus plan (Neon).
5. **Saved prompts:** Dia Skills, Neon Cards, Gemini Skills.
6. **Survivors cut their novelty.** Dia's "novelty budget", Arc's "novelty tax" and Atlas's shutdown all point the same way. Polish now comes from many small details (Dia's 2026 changelog) rather than new concepts.

---

## Top ideas for MBGA (ranked)

1. **Inset rounded web-content card on a tinted, full-window space color.** One color/gradient token per space drives the sidebar, the frame around the page, the active-tab pill and the new-tab wash. In AppKit: a layer-backed container with a corner radius and a few points of inset around the CEF view. *Source: Arc `arc-sidebar-zero-chrome.webp`, `arc-space-gradient.webp`; Dia `dia-sidebar-2026.webp`.*
2. **Page-aware chrome.** Read `<meta name="theme-color">` or sample the page's top edge. Tint the toolbar and active tab to match, and cross-fade on tab switch. Never flash white on switch or close: keep the last frame and set the CEF background from the page. *Source: Dia design post (tab color), Dia 1.28.0 (toolbar matches sticky header), 1.8.0 (no background flash), 1.10.1 (fewer dark-mode flashes).*
3. **Title-first address field.** At rest, show the page title and a muted domain. Reveal the full editable URL on hover or Cmd+L. Hide bookmark and site-settings icons until hover. *Source: Dia design post.*
4. **A playful space theme picker.** A floating panel with a 2D color canvas, swatches, a light/auto/dark switch and a grain slider, rendered as a SwiftUI `MeshGradient` plus a noise overlay. Show it during onboarding so people personalise on day one. *Source: Arc `arc-theme-picker.webp`; Arc install flow ([Wikipedia](https://en.wikipedia.org/wiki/Arc_(web_browser))); Dia 1.15.0 profile-color new tab page.*
5. **Swipe between spaces as an interactive, finger-tracked transition.** Use `scrollWheel` phase tracking with a spring settle, cross-fading the sidebar color. Keep it optional and invisible with one space: only 5.52% of Arc's DAUs used several spaces. *Source: Arc `space-swiping` image and letter; Dia 1.43.1 swipe between profiles.*
6. **A "micro-polish" backlog taken from Dia's 2026 changelog:**
   - Haptic tick on tab drag.
   - Rubber-band sidebar resize.
   - Favicon pre-warm on launch.
   - Active-tab favicon pinned when the tab scrolls out of view.
   - Sidebar collapse that doesn't move web content.
   - A shimmer when a folder is auto-named.
   *Source: [Dia changelog](https://www.diabrowser.com/changelog) 1.4.0, 1.29.0, 1.13.1, 1.52.0, 1.53.0, 1.20.0.*
7. **The browser tidies itself.** Archive untouched "Today" tabs after N hours, sleep them before that, and quietly discard unused new tabs when the app loses focus or the screen locks. It fits MBGA's Today section and tab sleeping. *Source: Arc 12-hour archive; Dia 1.38.0.*
8. **Calm new tab page.** One centered field in the space color, at most 8 favicon chips, and at most one "pick up where you left off" card. *Source: Comet `comet-new-tab.webp`, Edge `edge-copilot-new-tab.webp`, PCWorld's "cluttered with viral junk" criticism of Edge.*
9. **Native chrome paints before the engine.** Show the window, sidebar and favicons from Rust-core state immediately, then attach CEF views asynchronously. Make sure a hung renderer never blocks the AppKit main thread. *Source: Atlas OWL ([36Kr summary](https://eu.36kr.com/en/p/3532529113963648)).*
10. **Focus mode = fully collapsed sidebar** (Cmd+S, or drag it shut), with hover-at-edge to peek. *Source: Dia 1.3.1/1.5.0; Arc's hidden-sidebar "zero chrome".*
11. **Visible progress for multi-step jobs.** MBGA's new "import from other browsers" sheet is the first candidate: a plan checklist with a spinner on the current item and a live count ("Importing 3 spaces · 41 pinned tabs"), plus "Action required" if a profile is locked. *Source: Neon `neon-make-agent-panel.webp`, Comet `comet-background-assistants.webp`, Edge status chip.*
12. **Arc-faithful import mapping.** Arc Spaces become MBGA spaces with their emoji, color and pinned tabs/folders, and the importer switches to sidebar layout. *Source: Dia Windows 1.2.0 (Arc import switches to sidebar tabs), Mac 1.53.0 (Live Folders → Live Groups), Dia's own post about importing Profiles/Spaces.*
13. **Native settings window.** A SwiftUI `Settings` scene in System Settings style, never a web page. *Source: Gruber on Atlas.*
14. **If AI ever arrives, follow the survivors' layout:** AI in a right-hand per-tab panel, `@`-mention chips, a removable "Sharing <tab>" context chip, a glow plus Take control/Stop while anything automates the page, and AI as the single place novelty is spent. *Source: Dia "novelty budget", Gemini side panel, Atlas agent mode.*

---

## Images

All in `docs/design-research/img/ai-browsers/`. Converted to WebP at q78, max 1600 px wide.

| File | What it shows | Source URL |
|---|---|---|
| `arc-sidebar-zero-chrome.webp` | Arc's "zero chrome" layout: controls in the sidebar, URL pill, 4-up favorites grid, folders, active-tab pill, inset rounded page card | https://arc.net/ (image `/zero-chrome.png`) |
| `arc-space-gradient.webp` | A space with a full-window yellow-to-coral gradient frame, tinted active tab and space dots | https://arc.net/ (image `/space-swiping.png`) |
| `arc-theme-picker.webp` | Arc's theme picker (2D color dots, swatches, noise slider, grain dial) over a pink space with an Easel and split view | https://arc.net/ (image `/theme-picker.png`) |
| `dia-sidebar-2026.webp` | Dia in sidebar mode (2026): warm translucent sidebar, favorite tiles, tab groups, "Chats" at bottom, breadcrumb toolbar, inset page | https://www.diabrowser.com/ (Mux video poster `AfVIo00zNCeCXbiFeHQ7RuHZUfzl3agTCOno01XBF01lRs`) |
| `dia-split-view-tab-bar.webp` | Dia with tabs on top: profile pill + pinned favicons, colored tab group, split view with per-pane nav, "Chat with Tabs" pill | https://www.diabrowser.com/ (Mux video poster `zqOwkkAS9zCeLJq016siCak1olCG0202BGJXtLq2xxNEHI`) |
| `dia-chat-mention-pile.webp` | Dia chat in a tab: `@`-mentioned tabs as a stacked card pile, sources line, floating composer, "Personal" profile pill | https://techcrunch.com/2025/11/03/dias-ai-browser-starts-adding-arcs-greatest-hits-to-its-feature-set (image `wp-content/uploads/2025/06/@Mention-Tabs.jpeg`, credit The Browser Company) |
| `dia-active-tab-page-color.webp` | Dia's active tab taking the page's color and merging into toolbar and page; title-first tab and URL | https://browsercompany.substack.com/p/the-strategy-behind-dias-design |
| `atlas-agent-mode.webp` | ChatGPT Atlas agent mode: glow overlay, cursor tooltip, floating Take control/Stop bar, Ask ChatGPT side panel, centered domain | https://simonwillison.net/2025/Oct/21/introducing-chatgpt-atlas/ |
| `comet-new-tab.webp` | Comet's dark new tab page: "Ask anything or @mention a tab" composer, mode toggles, 4×2 link chips, left rail, Assistant button | https://techcrunch.com/2025/07/09/perplexity-launches-comet-an-ai-powered-web-browser/ |
| `comet-background-assistants.webp` | Comet's Background Assistants dashboard: task cards, "Action required" state, inline email draft with Send/Refine/Skip | https://techcrunch.com/2025/10/02/perplexitys-comet-ai-browser-now-free-max-users-get-new-background-assistant/ |
| `edge-copilot-new-tab.webp` | Edge's 2026 new tab page: greeting, unified "link or ask anything" composer with Smart mode, round quick links, one Journeys card | https://blogs.windows.com/msedgedev/2026/05/13/new-updates-to-edge-across-desktop-and-mobile/ |
| `edge-copilot-pane-status.webp` | Edge Copilot side pane with a "Searching your history" status chip and warm tint | https://blogs.windows.com/msedgedev/2026/05/13/new-updates-to-edge-across-desktop-and-mobile/ |
| `gemini-chrome-side-panel.webp` | Gemini in Chrome docked side panel: sparkle button in the tab strip, greeting, chips, "Sharing 'New Tab'" context chip, AI Mode chip on the new tab page | https://9to5google.com/2026/01/28/gemini-chrome-side-panel-more/ |
| `neon-make-agent-panel.webp` | Opera Neon Make mode: step-chip timeline and the "Neon's Computer" live-view panel with a plan checklist and Stop Task | https://www.techradar.com/ai-platforms-assistants/opera-neon-is-now-available-and-i-think-its-an-ai-subscription-worth-paying-for |

**Not saved (and why):**
- Comet, Atlas and Neon hero art: logos or illustrations.
- Neon's operaneon.com "pillar" images: marketing composites.
- Aside: its UI is an HTML mockup, and headless Chromium screenshots hung in this environment, both on aside.com and on example.com.
- YouTube thumbnails for Dia and Neon: no UI visible.
