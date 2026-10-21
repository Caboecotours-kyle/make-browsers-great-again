# Reddit: what browser enthusiasts call premium or cheap (research done 2026-10-21)

The question: what are people excited about in browsers right now, and which UI details do they call clean and premium versus cluttered and cheap? Each finding ends with a concrete idea for MBGA (SwiftUI/AppKit shell, CEF, Rust core).

## How this was gathered (and what to trust)

- `www.reddit.com` and `old.reddit.com` `.json` returned **HTTP 403** to a descriptive User-Agent. I found threads through Reddit's public **RSS** endpoints (`/r/<sub>/top/.rss?t=year`, `/r/<sub>/search.rss?...&sort=top&t=year`). I read post bodies, comment trees and scores from the **Arctic Shift** Reddit archive API (`arctic-shift.photon-reddit.com`). In total I made about 45 requests to reddit.com (several were 429 retries), about 190 to Arctic Shift, and 24 image downloads from i.redd.it and imgur.
- **Scores** below are written `[score | comments]` and come from Arctic Shift. They can lag live Reddit, and a few low numbers (0–1) on busy threads look like values captured at ingest time. Read them as rough magnitudes. Comment scores are written `(+N)`.
- Dates are post dates (UTC). Quotes are trimmed but not reworded. Every claim links to its thread.
- Subreddits mined: r/browsers, r/ArcBrowser, r/diabrowser, r/zen_browser, r/FirefoxCSS, r/vivaldibrowser, r/macapps, r/MacOS, r/SideProject, r/swift, plus searches. **r/HeliumBrowser does not exist** (404); Helium is discussed in r/browsers. r/SideProject and r/swift had almost nothing on browsers (see "Indie Arc successors"). r/MacOS "browser" searches were dominated by non-browser apps.

---

## Landscape in one paragraph (as of Oct 2026)

**Zen** is the enthusiast default. It won r/browsers' 24-round "Best Browser" bracket (2486 vs 2064 votes over Firefox) ([thread](https://www.reddit.com/r/browsers/comments/1rhj6qx/best_browser_day_24_zen_wins/) [2118|381c] 2026-03-01) and shipped Sync in September 2026 ([thread](https://www.reddit.com/r/zen_browser/comments/1w89fsx/zen_sync_is_here/) [1044|122c]). **Arc** is loved but seen as abandoned: "Arc is breaking, and Dia isn't the solution" ([thread](https://www.reddit.com/r/ArcBrowser/comments/1uthhyj/arc_is_breaking_and_dia_isnt_the_solution/) [134|89c] 2026-07-11), and TBC is emailing Arc users to move ([thread](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/) [230|189c] 2026-10-11). **Dia** won back some Arc users with Spaces (July 2026) and Arc import, but is criticised for half-done UX and paywalls. **Helium** (an ungoogled-Chromium fork) is the 2026 hype for being "just a browser": fast, uBlock Origin built in. **Vivaldi** won people over with auto-hide UI and an 8.0 redesign. Ad-blocking is the big background anxiety, because Manifest V2 / uBlock Origin is disappearing from Chromium browsers. A wave of indie "Arc clones" (Crest, Emerald, Mori, Viola, Firn, Stedding, Tangent) gets a mixed-to-hostile reception, especially when they look "vibe-coded".

---

## Per browser

### Arc (The Browser Company, maintenance mode)

**Praised**
- Workflow: spaces as profiles. "Nothing has come even remotely close to Arc's productivity boost" ([thread](https://www.reddit.com/r/ArcBrowser/comments/1tjiihh/nothing_has_come_even_remotely_close_to_arcs/) [356|61c] 2026-05-21). Top reply: "I can't main a browser without folders and spaces now" (+97). Another: "I have something like 30 spaces … no other browser lets me switch between them so easily with the side scroll button on my mx mouse" (+10).
- Polish: "Arc's UI feels way more polished and intentional. Everything flows better. Plus, stuff like Netflix and Spotify just works" ([thread](https://www.reddit.com/r/ArcBrowser/comments/1qw987p/ive_decided_to_stick_with_arc/) [175|47c] 2026-02-05).
- Space themes as cognition: "the themes in Arc are a major productivity tool. It's how I visualize separate different projects with as little cognitive overhead as possible… instantly swipe from Client 1 to Client 2 without breaking the flow" (+32). Also "I'm missing Arc's whimsical design and themes in Dia" (+62) ([thread](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/)).
- Delight details: the sidebar music-equaliser animation ([thread](https://www.reddit.com/r/ArcBrowser/comments/1qi4yuc/its_those_little_things_that_make_me_fall_in_love/) [149|30c] 2026-01-20); "This little player across spaces deserves more appreciation" ([thread](https://www.reddit.com/r/ArcBrowser/comments/1tb54fw/this_little_player_across_spaces_deserves_more/) [196|7c] 2026-05-12); subtle cues: "how well it handled the subtle visual cues to show that you had downloaded or copy/pasted something, or opened a tab in the background" ([thread](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/)).
- Must-have features named again and again: **Air Traffic Control** ("Traffic control is also one of my top features", +14), **Little Arc** mini window (+60), **Peek**, **nested folders** ("Nested folders is keeping me from making the switch", +29), **Cmd+T as one search for everything** ([thread](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/) [207|283c] 2026-10-12; [Little Arc alternatives](https://www.reddit.com/r/browsers/comments/1rtli12/little_arc_alternatives/)).
- "Chrome with vertical pinned tabs is basically Arc?" was mocked: "Arc is a lot more than putting tabs in a column… Arc Spaces, and the ability to have different spaces be different Arc profiles" (+61) ([thread](https://www.reddit.com/r/ArcBrowser/comments/1qfugz7/chrome_with_vertical_pinned_tabs_is_basically_arc/) [167|47c] 2026-01-18).

**Complaints**
- Rot: YouTube fullscreen bug, downloads hanging, crashes ([1uthhyj](https://www.reddit.com/r/ArcBrowser/comments/1uthhyj/arc_is_breaking_and_dia_isnt_the_solution/), [1toiv7c](https://www.reddit.com/r/browsers/comments/1toiv7c/arc_browsers_new_bugs_and_issues_everyday/)).
- Hard-coded old favicons on favourites ([thread](https://www.reddit.com/r/ArcBrowser/comments/1u24x4a/kind_of_annoying_how_arc_has_these_hardcoded_old/) [173|39c] 2026-06-10).
- Auto-archive surprises: "I hate the fact that tabs would archive once I forget about once in a while and then going back and its not there" (+7, [1qw987p](https://www.reddit.com/r/ArcBrowser/comments/1qw987p/ive_decided_to_stick_with_arc/)).
- Windows build: "all of the text and buttons and UI are scaled too big on windows" (+7).

**Ideas for MBGA**
- Keep spaces = profiles. Make switching spaces a trackpad swipe and a mouse side-scroll, with the space's colour washing across the whole window chrome as you swipe. That turns colour into "where am I" without reading anything.
- Ship an Arc-style mini player (see Themes → Delight).
- Tab sleeping should never feel like loss. Show sleeping tabs dimmed but always findable, and never silently delete. If MBGA ever auto-archives, show a "Recently archived" row with undo.

### Dia (TBC)

**Praised**
- After a year, "Most of what kept me on Arc is now there: Spaces / Profiles, Vertical tabs + sidebar, Pinned tabs & Favorites, Tab Groups, Split View… you can now import your Arc setup directly into Dia" ([thread](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/) [207|283c] 2026-10-12).
- Profile switching in one window: "This profile switch is incredible! Arc moment right here!" ([thread](https://www.reddit.com/r/diabrowser/comments/1vckcnn/this_is_so_so_good/) [103|16c] 2026-08-01).
- Pinned tabs redesign: favourite tiles fill with the site's brand colour when active ([thread](https://www.reddit.com/r/diabrowser/comments/1oq3wbp/pinned_tabs_get_a_refreshed_design_in_dia_to/) [166|26c] 2025-11-06; image `dia-pinned-tiles-brand-color.webp`).
- "Atlas showed me why I still use Dia: User experience… Atlas clearly feels like something built by an engineer-heavy team" ([thread](https://www.reddit.com/r/diabrowser/comments/1ocle3o/atlas_showed_me_why_i_still_use_dia/) [88|35c] 2025-10-21). Also "I like Dia, not for the AI features but because it looks nice on macOS" ([thread](https://www.reddit.com/r/diabrowser/comments/1vro9k9/what_is_the_browser_company_even_doing/) [75|61c] 2026-08-18).

**Complaints**
- **Active-tab legibility**: "I dare you to identify the active tab" ([thread](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/) [68|19c] 2026-04-18). "Having the background behind tabs be transparent is an absolutely horrific decision if there isn't going to be any sort of indicator more visible than a 3% brightness increase" (+15). "They went from Arc being a leader in ux, to this?" (+9). Image: `dia-active-tab-indistinct.webp`.
- Spaces: "Spaces in Dia don't even come close to how Arc does it. Also, no traffic control. Pass" (+157). Trust: "It's about the betrayal" (+101) ([1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/)).
- Folders: "Put the damn folders back in, Josh." (+42) on the window-tinting teaser ([thread](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/) [113|65c] 2025-11-07).
- A wishlist from that thread (+9) that reads like a spec: "swipeable spaces/profiles; tab key to search directly in websites; ⌘+⏎ to direct google search; little Dia (like little Arc); ⇧ key to peek websites; move the tab-bar/address bar to the left when sidebar is enabled; icons for Favourite tabs; tab folders; Pressing ⌘+T creates only one new tab; Clear All tabs; Tidy Tabs".
- Window chrome: a request to align with macOS Tahoe's new window corners/traffic lights ([thread](https://www.reddit.com/r/diabrowser/comments/1ozuyrx/a_redesign_of_the_dia_window_to_finally_comply/) [113|24c] 2025-11-17). The top reply was "Give me literally any of the other missing core features before this please" (+38). Image: `dia-tahoe-window-corner-concept.webp`.
- Account required to use it; Windows 11 only ([thread](https://www.reddit.com/r/browsers/comments/1x2lspb/dia_browser_on_windows_now_has_a_collapsible/) 2026-10-10).
- URL bar placement: "would love to have the address bar moved to the left as well" (+23); "or let it hide like Zen and only pop out when hovered over or with a shortcut" (+10) ([1oq3wbp](https://www.reddit.com/r/diabrowser/comments/1oq3wbp/pinned_tabs_get_a_refreshed_design_in_dia_to/)).

**Ideas for MBGA**
- The active tab must be obvious at a glance: a solid, opaque pill (not +3% brightness) plus a bolder title. Check it on light, dark and tinted space backgrounds.
- Favourites grid: when a pinned app is active, fill its tile with a tint sampled from the favicon (Dia-style). Keep favicons live, never cached forever.
- Use the Dia wishlist above as a Cmd+T/Cmd+L acceptance checklist.

### Zen (Firefox-based, open source)

**Praised**
- Feel: "This browser looks and feels so minimalistic and premium" ([thread](https://www.reddit.com/r/zen_browser/comments/1uxbvda/zen_looks_so_premium/) [417|96c] 2026-07-15). Another post: "a browser that doesn't feel like enterprise middleware wearing a hoodie" ([thread](https://www.reddit.com/r/zen_browser/comments/1tf8o36/browser_market_been_stale_for_years_and_then_zen/) [387|44c]). A user who switched to Chromium: "TRIED ARC I AM NOT GETTING THAT CALMER FEEL LIKE ZEN. ESPECIALLY THE BETTER UNLOAD TABS, ESSENTIALS" ([thread](https://www.reddit.com/r/browsers/comments/1wx9w66/i_need_chromium_alternative_to_zen/) 2026-10-04).
- "Most aesthetically pleasing… removes everything distracting from web browsing around the window borders, displaying only the webpage itself" ([thread](https://www.reddit.com/r/browsers/comments/1op3k0s/the_most_aesthetically_pleasing_browser_in_my/) [296|73c] 2025-11-05).
- Features that drew big upvotes in 2026:
  - **Smart Routing** (domain → space rules) ([thread](https://www.reddit.com/r/zen_browser/comments/1tw1kvw/wip_i_think_prior_arc_users_are_gonna_love_this/) [700|85c] 2026-06-03; image `zen-smart-routing-settings.webp`)
  - **split by dragging one tab onto another** ([thread](https://www.reddit.com/r/zen_browser/comments/1rkizow/making_split_views_more_intuitive/) [458|46c] 2026-03-04)
  - **Live Folders** (RSS/GitHub PRs as auto-filled folders) ([thread](https://www.reddit.com/r/zen_browser/comments/1rhv2r8/introducing_live_folders/) [537|65c])
  - **Boosts** (per-site restyling) ([thread](https://www.reddit.com/r/zen_browser/comments/1tml02g/120b_boosts_have_been_released/) [850|124c])
  - **Library** (downloads, screenshots, spaces in one place) ([thread](https://www.reddit.com/r/zen_browser/comments/1wwwsqe/organise_your_browsing_library_is_here/) [641|105c] 2026-10-03)
- Compact mode refinement: the sidebar "stays open while your cursor lingers near the window's edge and only tucks away once you move further out" ([thread](https://www.reddit.com/r/zen_browser/comments/1vhdlrg/looking_for_feedback_for_the_latest_release/) [521|90c] 2026-08-06).
- Community mods show where the stock UI falls short:
  - **ZenLeap**, a command palette with vim-style tab navigation ("This kind of stuff should be built in", +10) ([thread](https://www.reddit.com/r/zen_browser/comments/1rdw35v/i_built_vimstyle_tab_navigation_and_a_command_bar/) [352|74c])
  - **Folder tree connectors** ("We need this merged into stock Zen ASAP", +8) ([thread](https://www.reddit.com/r/zen_browser/comments/1tohb8h/zen_folder_tree_connectors_v20_sine_mod/) [340|26c])
  - **Gmail unread preview on hovering a pinned tab** ([thread](https://www.reddit.com/r/zen_browser/comments/1wtlht7/arcstyle_gmail_preview_when_you_hover_your_pinned/) [258|17c] 2026-09-29)
  - **Zia**, a Dia-style finish ([thread](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/) [524|128c] 2026-10-01). Its feature list: "Toolbar takes the colour of whatever site you're on; Cleaner address bar (top or bottom); coloured folders, 5,000+ icons, smooth dragging, hover cards; Hold ⌘/Ctrl to see tab numbers and jump to any tab; Glance gets a little preview that pops out of the tab; Frosted glass on the compact sidebar, hover cards and address bar; Drop a tab on the page to split it". The OP added: "⌘/Ctrl+Z undo: brings back what you just closed for 10 seconds, including whole folders and splits; Downloads: a progress ring right by your space name; Copy link: paperclip in the address bar" (+11).

**Complaints**
- Transparency backlash (see Themes → Glass): "it feels and looks very cheap with transparency and more like a gimmick" (+30) ([1uxbvda](https://www.reddit.com/r/zen_browser/comments/1uxbvda/zen_looks_so_premium/)).
- Performance: "it turns my mac into hot pan and sometimes had memory leaks" ([thread](https://www.reddit.com/r/browsers/comments/1u36dn3/zenarc_alternatives_with_ublock_origin/) 2026-06-11); "it's just soooo slow for every single webpage loading, YouTube videos exceptionally so" (+28, [1uthhyj](https://www.reddit.com/r/ArcBrowser/comments/1uthhyj/arc_is_breaking_and_dia_isnt_the_solution/)); "annoyed by Zen's memory usage on my 16GB machine… but I just can't get over the sleek UI" ([thread](https://www.reddit.com/r/browsers/comments/1ufwcm3/im_annoyed_by_zens_memory_usage_on_my_16gb/) [90|46c]).
- No DRM (Widevine), so no Netflix/Spotify ([1tjc2yk](https://www.reddit.com/r/ArcBrowser/comments/1tjc2yk/ive_made_a_100_arc_zen_migration_tool/), [1omlvfi](https://www.reddit.com/r/browsers/comments/1omlvfi/arc_vs_zen/)).
- "Zen is not as polished as Arc" (+22) ([1x3kpcw](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/)); "just isn't the same level of polish" ([1s2bbzk](https://www.reddit.com/r/ArcBrowser/comments/1s2bbzk/arc_had_everything/)).
- Edge behaviour: "When I put the cursor near the edge… Zen opens the sidebar. But when I put it on the edge, it makes the sidebar hidden again. In Arc, they both make the sidebar stay open… it makes Zen feels clunky" ([thread](https://www.reddit.com/r/zen_browser/comments/1vda1k6/how_to_make_sidebar_stays_open_when_the_cursor_on/) [142|25c] 2026-08-02).
- Inconsistent secondary UI: "Zen's UI for the cntrl tab menu is both ugly and does not match other aspects of the UI" ([thread](https://www.reddit.com/r/zen_browser/comments/1qzoc4q/cntrl_tab_ui_in_zen/) [86|14c]).
- Library hijacked shortcuts and is "too narrow": "taking over Firefox's History and Downloads shortcuts (ctrl+shift+h and ctrl+j) is a dealbreaker for me" (+19); "bring back the old download popup?… showed more files at once, with the full filenames visible" (+15) ([1wwwsqe](https://www.reddit.com/r/zen_browser/comments/1wwwsqe/organise_your_browsing_library_is_here/)).
- Accidental splits with no undo: "i have split tabs by accident when trying to rearrange. Unfortunately undo (ctrl Z) doesn't work" (+8) ([1rkizow](https://www.reddit.com/r/zen_browser/comments/1rkizow/making_split_views_more_intuitive/)).

**Ideas for MBGA**
- Compact mode with hysteresis and edge rules (see Top ideas #2).
- Hold ⌘ to show numbered badges on tabs (⌘1–9 jump).
- Universal Cmd+Z for sidebar actions.
- A downloads progress ring next to the space name.
- A copy-link button in the URL field with a little confirmation toast.

### Helium (ungoogled-Chromium fork by imput)

**Praised**
- "basically a fork of ungoogled chromium with some thoughtful tweaks like auto-updates, built-in uBlock Origin, a cleaner UI, and better defaults for privacy. Unlike Brave which has piled on a ton of bloat" (+393). "It's the cleanest and tidiest browser I used so far. It's just a browser" (+60) ([thread](https://www.reddit.com/r/browsers/comments/1sldzxc/why_is_everyone_talking_about_helium/) [739|281c] 2026-04-14).
- "Ultra fast, ultra snappy." Vertical tabs plus a hidden address bar ("Zen mode") "made me uninstall Zen" ([thread](https://www.reddit.com/r/browsers/comments/1t0aths/finally_helium_is_now_looking_like_arc/) [335|92c] 2026-04-30; image `helium-zen-mode-vertical-tabs.webp`).
- "DEAR GOD it looks clean, side tabs? it's a small space… frameless mode… the auto hide works… perfectly, I don't even find myself accidentally poppin the hidden panels nearly as often like in other browsers" ([thread](https://www.reddit.com/r/browsers/comments/1x820gb/helium_probably_the_only_browser_ive_went_to/) [105|37c] 2026-10-17).
- "It launches fast as hell" ([thread](https://www.reddit.com/r/browsers/comments/1ter7mk/helium_fucking_rocks/) [140|70c]). "Helium now has oneline" (tabs and URL in one row) ([thread](https://www.reddit.com/r/browsers/comments/1qqpcgo/helium_now_has_oneline_which_means_i_can_now/) [266|121c]).
- People see the missing features as features: "all of the cons seem like pros to me" (+73); "in what world is lack of AI a con?" ([thread](https://www.reddit.com/r/browsers/comments/1svli5p/is_helium_the_best_minimalist_browser_right_now/) [163|202c]).

**Complaints**
- **"We need url bar in sidebar"** (+19, [1ter7mk](https://www.reddit.com/r/browsers/comments/1ter7mk/helium_fucking_rocks/)). "If they have an option to move the URL to the sidebar, I might switch" (+29). "Arc shows the address bar though, on the sidebar" (+44) ([1t0aths](https://www.reddit.com/r/browsers/comments/1t0aths/finally_helium_is_now_looking_like_arc/)).
- No sync, no DRM, unsure the project will last ("judging by the way the dev team acts, it's not a sure thing", +28). "God how choppy the animations can be" (+13) ([thread](https://www.reddit.com/r/browsers/comments/1ugtovk/damn_helium_is_slick_af/) [259|51c]).
- Minimalism taken further: a "Clean Helium" new-tab page with a clock and shortcuts drew "Looks bloated to me" (+50) and "my new tab only show wallpaper" ([thread](https://www.reddit.com/r/browsers/comments/1ukf1mq/clean_helium_browser/) [136|34c]).

**Ideas for MBGA**
- MBGA's stack is closest to Helium's (Chromium), so it needs to match Helium's baseline: fast cold launch, a built-in blocker, no bloat.
- Then beat it on what people ask Helium for: the URL in the sidebar, spaces, folders and smooth animation.

### Vivaldi

**Praised**
- Auto-hide UI: "With the UI autohide it's not only the most functional and stable but also the best looking browser" ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1q6pzcw/the_new_vivaldi_snapshot_is_the_dream_browser/) [251|78c] 2026-01-07; image `vivaldi-autohide-ui.webp`). In 7.9: "The auto hide UI is soooo f***g good… being able to use its 100% is incredible" ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1rxudf4/vivaldi_79_immerse_yourself_in_the_web_with_every/) [202|81c] 2026-03-19).
- Zen-style setups built in Vivaldi: "Looks a lot like zen. Which is a good thing" ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1s942b8/beauty_of_vivaldi/) [279|49c]; image `vivaldi-zen-style-setup.webp`). "Vivaldi's features with Zen Browser's UI? Now we're talking" (+10, [1q6pzcw](https://www.reddit.com/r/vivaldibrowser/comments/1q6pzcw/the_new_vivaldi_snapshot_is_the_dream_browser/)).
- No-AI stance: "Vivaldi 7.8: No AI Slop. Just Powerful Features" ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1qq2m2x/vivaldi_78_no_ai_slop_just_powerful_features/) [383|89c]). Drag-and-drop tab tiling ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1qsecpt/the_new_tab_tilling_is_awesome_thanks_vivaldi/) [183|26c]).

**Complaints**
- The 8.0 redesign: "I hate the border around the window… takes up way too much space from all sides just to look like Safari" (+25); "What's with the top border above the tabs? I hate it" (+20); "There was no problem with the design. There are still multiple problems with how it functions" (+17) ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1tjctdo/vivaldi_80_is_out_with_biggest_design_overhaul/) [276|142c] 2026-05-21).
- Accessibility: "making UI elements harder to select is never a good idea". Autocomplete: "when I start typing 'r' - it shows me 'redis', although the most frequently visited website for me on 'r' is reddit.com" (+6) ([official 8.0 post](https://www.reddit.com/r/vivaldibrowser/comments/1tjcutb/vivaldi_80_our_biggest_design_overhaul_ever/) [186|70c]).
- Hover zones fire by accident: "How do I prevent this panels from opening when I hover on the left side?" (+7, [1rxudf4](https://www.reddit.com/r/vivaldibrowser/comments/1rxudf4/vivaldi_79_immerse_yourself_in_the_web_with_every/)).
- Weak built-in ad blocker, no element picker, unreliable sync ([thread](https://www.reddit.com/r/vivaldibrowser/comments/1ufzywu/team_vivaldi_we_need_to_talk/) [269|92c]; "They made a mistake using AdBlock Plus engine… an element picker is a must" +30).

**Ideas for MBGA**
- The content inset ("border around the page") must be thin and earn its space. Offer edge-to-edge when the sidebar is hidden.
- Rank Cmd+L autocomplete by frecency, with inline completion of the most-visited host.

### Firefox and r/FirefoxCSS (riced setups)

- One-row chrome: **FoxOne** "collapses the tab bar and URL bar into a single row. Non-essential icons are hidden by default and slide in on hover with transitions" ([thread](https://www.reddit.com/r/FirefoxCSS/comments/1t2hr8f/foxone_a_minimalistic_oneline_theme/) [100|16c] 2026-05-03; image `firefox-foxone-one-line.webp`). The same move is popular in Helium ("oneline").
- **Quieter system UI**: a minimal pill-style fullscreen warning instead of the old bulky banner ([thread](https://www.reddit.com/r/FirefoxCSS/comments/1ufvm5u/minimal_pillstyle_fullscreen_warning/) [98|9c]; "This should've been updated officially. The current design has been used for at least 10 years" +6). Image: `firefox-pill-fullscreen-warning.webp`.
- **Loading progress drawn on the tab itself** came up repeatedly: on the tab ([1taxnfs](https://www.reddit.com/r/FirefoxCSS/comments/1taxnfs/add_a_loading_progress_bar_to_the_tabs/) [43|14c]), in the address bar ([1tq0k01](https://www.reddit.com/r/FirefoxCSS/comments/1tq0k01/add_a_loading_progress_bar_to_the_address_bar/) [38|13c]), along the tab bar/vertical tabs ([1tyemls](https://www.reddit.com/r/FirefoxCSS/comments/1tyemls/add_a_loading_progress_bar_to_the_tab_bar/)), and adapted for Nova ([1ugy75a](https://www.reddit.com/r/FirefoxCSS/comments/1ugy75a/displays_a_loading_progress_bar_on_the_tab/) [42|7c]).
- **Rounded-corner fatigue**: a commenter says Firefox 145 moved the default radius from 4px to 8px (+6; not independently verified). "Rounded corners especially are quickly becoming a pet peeve of mine for how unprofessional they look" ([thread](https://www.reddit.com/r/FirefoxCSS/comments/1ov0806/does_anyone_know_how_we_can_unround_our_tabs/) [51|9c] 2025-11-12). On Nova (the 2026 redesign): "I want less rounded corners, not more" (+18); "Whats with the purple color?… Why not use neutral colors?" (+32); "They need more 'modular' design which allows for personalization, as well as auto-hide" (+26) ([thread](https://www.reddit.com/r/FirefoxCSS/comments/1rn8m9h/new_redesign_coming_to_firefox_prepare_for_major_theme_breakage/) [178|68c] 2026-03-07). A follow-up exists just to tone Nova's radius down ([1whkjin](https://www.reddit.com/r/FirefoxCSS/comments/1whkjin/nova_rounding_borderradius_adjustment_variables/)).
- Smaller craft posts: two-line labels in vertical tabs ([1or6cz9](https://www.reddit.com/r/FirefoxCSS/comments/1or6cz9/vertical_tabs_with_2line_labels_ff_144/)); making the Ctrl-Tab panel match the theme ([1rtbpaj](https://www.reddit.com/r/FirefoxCSS/comments/1rtbpaj/finally_got_rid_of_the_ugly_ctrltab_menu_and_made/)); a custom tab animation for Nova ([1wwjb1r](https://www.reddit.com/r/FirefoxCSS/comments/1wwjb1r/i_made_a_custom_tab_animation_effect_for_nova/) [43|10c]).

**Ideas for MBGA**
- Show page loading as a 2px progress line along the bottom of the active sidebar row (and of the URL field when it's visible), not as a spinner that replaces the favicon.
- Make the fullscreen notice a small pill that fades out.
- Keep radii modest and consistent (see Themes).

### Safari and Orion (the Mac-native crowd)

- In r/macapps, Safari is valued because "it's way lighter than the rest… memory, bandwidth, battery" and "simple. no endless ai features" ([thread](https://www.reddit.com/r/macapps/comments/1sjg0iy/safari_vs_the_rest_is_it_actually_the_best/) [221|290c] 2026-04-12). Replies: "Safari + uBlock Origin Lite is the best configuration for me" (+79); "'No integrated AI' should be in pros" (+28); "Kagi's Orion browser is my new favorite now" (+25). Counterpoint: "safari on my m4 Mac mini renders pages noticeably slower than chromium" (+35).
- Orion's Windows preview was praised for "commitment to native design" (+20) ([thread](https://www.reddit.com/r/browsers/comments/1rw59sr/images_of_the_windows_version_of_the_orion/) [141|36c] 2026-03-17). A Mac user in the same thread: "very buggy, switched to Vivaldi" (+6).
- r/OrionBrowser is small; scores are low.
  - Praise: Orion for macOS 1.0 shipped ([thread](https://www.reddit.com/r/OrionBrowser/comments/1p6kpc4/orion_for_macos_10_is_here/) [127|25c] 2025-11-25); "beautiful and liquid-glass-native… the tab bar is more native to macOS's liquid glass" ([thread](https://www.reddit.com/r/OrionBrowser/comments/1ogg3km/the_latest_version_of_orion_099137beta_is/) [22|14c]); "UI is gorgeous, speed is unreal, and RAM usage is way lower" ([thread](https://www.reddit.com/r/OrionBrowser/comments/1pnpg29/anyone_else_daily_driving_orion_on_macos_lately/) [20|10c]).
  - Complaints, recurring: "a webkit browser that follows macos and linux themes natively! Oh shi it is so buggy" ([thread](https://www.reddit.com/r/OrionBrowser/comments/1vy1d3x/nice_a_webkit_browser_that_follows_macos_and/) [36|8c]); "1Password integration is a nightmare" ([thread](https://www.reddit.com/r/OrionBrowser/comments/1qwnoh5/sorry_orion_but_1password_integration_is_a/) [22|15c]).
  - People notice tiny geometry glitches: "The window corner radius changes in Focus Mode" ([thread](https://www.reddit.com/r/OrionBrowser/comments/1p8pmfx/the_window_corner_radius_changes_in_focus_mode/) [18|0c]).
- A third-party "Arc-like sidebar for all browsers" app sells to Safari users who want just the sidebar ([SupaSidebar](https://www.reddit.com/r/macapps/comments/1p88fqk/supasidebar_arclike_sidebar_for_all_browsers/) [158|309c]; [Arc sidebar link organiser](https://www.reddit.com/r/ArcBrowser/comments/1r4uwun/i_built_a_macos_app_that_brings_arcs_sidebar_link/) [255|38c]).

**Idea for MBGA**: Mac users judge against Safari on battery and idle cost. Publish a visible "energy" story (tab sleeping, idle CPU) and use system materials and fonts so it feels as native as Safari.

### Indie "Arc successors" (makers posting 2025–2026)

Each entry gives stack, then reception.

- **Crest** (SwiftUI + WebKit; Mac, iPad, iPhone). Quick Windows (Little Arc), Peek, spaces with isolated cookies, sidebar "banner" theme per space ([thread](https://www.reddit.com/r/browsers/comments/1vjef6c/crest_browser_inspired_by_arc_testflight_open/) [39|49c] 2026-08-09). Comments: "Amazing, installed, lovely ui ux", plus privacy questions and requests for extensions and password managers. Later Arc threads recommend it: "Crest is amazing. It gives me the same delight as Arc once did" (+14) and "try Crest browser! It's awesome!" (+135) ([1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/), [1x3kpcw](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/)).
- **Emerald** (SwiftUI + WebKit; Mac + iOS). Beta with iCloud sync, Today Tabs, Split, Arc import, "uBlock Origin works fully", Peek ([thread](https://www.reddit.com/r/ArcBrowser/comments/1sbo321/ive_been_building_a_browser_inspired_by_arc/) [302|87c] 2026-04-03). "This shockingly polished already" (+10, [Dec 2025 thread](https://www.reddit.com/r/ArcBrowser/comments/1pf7lfj/i_built_a_browser_inspired_by_arc_for_mac_ios/) [150|47c]). "It's a non starter without 1Password" (+8).
- **Mori** (Chromium + a C++→SwiftUI/AppKit bridge with native Liquid Glass; the architecture closest to MBGA). Built-in ad blocker, Chrome extensions, passkeys ([thread](https://www.reddit.com/r/ArcBrowser/comments/1u94qnt/made_a_chromiumbased_arc_alternative_free/) [33|111c] 2026-06-18; image `mori-liquid-glass-sidebar.webp`). Reception was hostile: "Definitely not using a vibe coded browser. Security nightmare" (+188).
- **Viola** (Chromium; Mac, Windows, Linux, Android). Workspaces, isolated profiles, E2E sync, a mini player that follows you between workspaces ([thread](https://www.reddit.com/r/ArcBrowser/comments/1vb2efy/i_build_a_spiritual_successor_to_arc/) [170|123c] 2026-07-30; image `viola-sidebar-attention-player.webp`). Trust problems: "OP seems to have launched like 4 different alternative apps in the last three months" (+66); "You didn't address the key question about open source" (+40).
- **Firn** (Electron/Chromium). Sells itself as "calm… sensible defaults, short menus, and nothing to set up", with Basecamp favourite tiles, Lookout preview and drag-to-split ([thread](https://www.reddit.com/r/browsers/comments/1x50fky/firn_a_calm_free_opensource_chromium_browser_with/) [144|195c] 2026-10-13). Replies: "Vibe-coded Arc clone number 349504093287" (+203); "Vibe coded and no uBlockOrigin support. I'll pass" (+73); "On Electron even. Bonkers" (+61).
- Others: **Stedding** ("the UI is just slightly off in a way that's hard to explain", [1xaeimq](https://www.reddit.com/r/browsers/comments/1xaeimq/this_might_be_the_best_alternative_for_windows/)); **Tangent** waitlist ([1wmhdtf](https://www.reddit.com/r/browsers/comments/1wmhdtf/tangent_browser_looks_promising_finally_an/)); **Hilal** (Firefox) ([1tyusjt](https://www.reddit.com/r/browsers/comments/1tyusjt/im_building_hilal_browser_an_opensource/)); **Sharp Tabs / "Arc Reborn"** Vivaldi mod ([1qyp0e6](https://www.reddit.com/r/browsers/comments/1qyp0e6/thinking_of_making_an_opensource_arc_reborn_mod/)); **Arc Peek for Vivaldi** ([1sims9p](https://www.reddit.com/r/vivaldibrowser/comments/1sims9p/arc_peek_for_vivaldi_link_preview_with_arcnative/) [85|18c]).

- **r/SideProject and r/swift**: searching for "browser" (top, past year) turned up no notable Arc-style browser launches. Indie browser launches happen in r/ArcBrowser and r/browsers. The only browser-ish projects were a canvas "spider browser" for research, where pages sit on an infinite canvas with connection lines ([r/SideProject](https://www.reddit.com/r/SideProject/comments/1pfbxni/i_got_sick_of_tabs_so_here_is_what_i_built_a/) [21|4c] 2025-12-06), and "Sliver", a tiny floating browser ([r/SideProject](https://www.reddit.com/r/SideProject/comments/1ub1lsz/first_post_i_made_a_tiny_floating_browser_for/) [8|2c]). r/swift had nothing browser-shell related.

**Lessons for MBGA**
- These subs punish Electron, unclear authorship ("vibe-coded"), missing uBO and missing password-manager support right away.
- They reward polish ("shockingly polished") and a credible maintainer.
- "Slightly off" UI is noticed even when people can't say why. Spacing, timing and typography need to match the platform exactly.

---

## Themes: premium vs cheap, detail by detail

### Glass and transparency (polarizing)
- **Cheap when applied to everything**: "transparency on everything… feels and looks very cheap" (+30); "Whatever you have here, definitely doesn't look premium" (+18) ([1uxbvda](https://www.reddit.com/r/zen_browser/comments/1uxbvda/zen_looks_so_premium/)). "Websites have backgrounds for a reason" (+23); "It makes website illegible" (+6) ([1rmnuho](https://www.reddit.com/r/zen_browser/comments/1rmnuho/this_browser_is_literally_so_aesthetic/)). Dia's transparent tab background kills active-state legibility ([1sp3isz](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/)).
- **Liked when confined to chrome**: Zia uses "frosted glass on the compact sidebar, hover cards and address bar" ([1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/)). Transparent Zen on Tahoe has fans ([1rmnuho](https://www.reddit.com/r/zen_browser/comments/1rmnuho/this_browser_is_literally_so_aesthetic/) [367|30c]; [r/browsers cross-post](https://www.reddit.com/r/browsers/comments/1rmn0x2/this_browser_is_literally_so_aesthetic/) [208|69c]).
- **MBGA rule**: use a material (NSVisualEffectView / Liquid Glass) for the sidebar, command bar, popovers and the floating sidebar in compact mode. **Never put glass behind web content.** Respect "Reduce transparency". Keep tab rows on an opaque-enough layer so text contrast stays at or above 4.5:1.

### Corners, borders and the content inset
- Firefox users push back on bigger radii ([1ov0806](https://www.reddit.com/r/FirefoxCSS/comments/1ov0806/does_anyone_know_how_we_can_unround_our_tabs/); [1rn8m9h](https://www.reddit.com/r/FirefoxCSS/comments/1rn8m9h/new_redesign_coming_to_firefox_prepare_for_major_theme_breakage/), +18). Vivaldi 8.0's window border is called wasted space (+25, +20, [1tjctdo](https://www.reddit.com/r/vivaldibrowser/comments/1tjctdo/vivaldi_80_is_out_with_biggest_design_overhaul/)). One poster says "Rounded frames are overused… I love seeing my browser squared!" ([1s5dprs](https://www.reddit.com/r/browsers/comments/1s5dprs/rounded_frames_are_overused_i_love_seeing_my/), low score).
- A product designer's suggested radius hierarchy for Peek/Glance: "8px radius for the background tab. 16px radius for the glanced tab", with the toolbar going transparent in glance mode (+10, [1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/)).
- Dia was asked to adopt Tahoe's window corner/traffic-light geometry ([1ozuyrx](https://www.reddit.com/r/diabrowser/comments/1ozuyrx/a_redesign_of_the_dia_window_to_finally_comply/)).
- **MBGA rule**:
  - Make corners concentric: content-card radius = window corner radius − inset.
  - Keep the inset small (about 6–8 pt). Drop it to 0 when the sidebar is hidden or in fullscreen.
  - Don't stack borders. Use one hairline or one shadow, not both.

### Hover-reveal / compact / auto-hide
- The most-praised layout change of the year: Vivaldi's auto-hide ([1q6pzcw](https://www.reddit.com/r/vivaldibrowser/comments/1q6pzcw/the_new_vivaldi_snapshot_is_the_dream_browser/), [1rxudf4](https://www.reddit.com/r/vivaldibrowser/comments/1rxudf4/vivaldi_79_immerse_yourself_in_the_web_with_every/)) and Helium's Zen mode / frameless mode ([1t0aths](https://www.reddit.com/r/browsers/comments/1t0aths/finally_helium_is_now_looking_like_arc/), [1x820gb](https://www.reddit.com/r/browsers/comments/1x820gb/helium_probably_the_only_browser_ive_went_to/)).
- What makes it feel premium versus clunky:
  - **Hysteresis**: stay open while the cursor lingers just outside ([1vhdlrg](https://www.reddit.com/r/zen_browser/comments/1vhdlrg/looking_for_feedback_for_the_latest_release/)).
  - **The literal screen edge counts as "inside"** (Arc does this, Zen didn't: [1vda1k6](https://www.reddit.com/r/zen_browser/comments/1vda1k6/how_to_make_sidebar_stays_open_when_the_cursor_on/)).
  - **No accidental reveals** ([1x820gb](https://www.reddit.com/r/browsers/comments/1x820gb/helium_probably_the_only_browser_ive_went_to/) vs Vivaldi's complaint in [1rxudf4](https://www.reddit.com/r/vivaldibrowser/comments/1rxudf4/vivaldi_79_immerse_yourself_in_the_web_with_every/)).
  - **A way to drag the window** when the toolbar is hidden (Zen added a hover bar for it: [1pz3to1](https://www.reddit.com/r/zen_browser/comments/1pz3to1/did_i_just_miss_this_feature_before/)).
- **MBGA spec idea** (sketch):

  ```text
  reveal   after cursor rests ≤ 6 pt from the left edge for 120 ms
           OR a fast flick into the edge
  stay     open while cursor is within sidebarWidth + 24 pt
           (including outside the window and the screen edge)
  hide     after 300 ms outside that zone
  shortcut Cmd+S pins / unpins the sidebar
  overlay  revealed sidebar floats over the page with a shadow (no reflow)
  drag     invisible 8 pt drag strip at top; traffic lights fade in on hover
  ```

### URL bar placement and the command bar
- People want the URL **in the sidebar**, as in Arc:
  - "Arc shows the address bar though, on the sidebar" (+44) and "If they have an option to move the URL to the sidebar, I might switch" (+29) ([1t0aths](https://www.reddit.com/r/browsers/comments/1t0aths/finally_helium_is_now_looking_like_arc/))
  - "We need url bar in sidebar" (+19) ([1ter7mk](https://www.reddit.com/r/browsers/comments/1ter7mk/helium_fucking_rocks/))
  - "address bar moved to the left" (+23) ([1oq3wbp](https://www.reddit.com/r/diabrowser/comments/1oq3wbp/pinned_tabs_get_a_refreshed_design_in_dia_to/))
- Cmd+T should open a command bar, not a new-tab page:
  - "I also miss the command bar instead of opening a new tab every time I CTRL+T" ([1ufwcm3](https://www.reddit.com/r/browsers/comments/1ufwcm3/im_annoyed_by_zens_memory_usage_on_my_16gb/))
  - "Why there is no Cmd+T option to work as in Arc" (+35) ([1x3kpcw](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/))
  - "I just want Cmd+T to let me global search + operate my browser" (+8) ([1ocle3o](https://www.reddit.com/r/diabrowser/comments/1ocle3o/atlas_showed_me_why_i_still_use_dia/))
- Command-bar details people ask for:
  - Tab-to-search inside a site
  - ⌘⏎ to force a web search
  - Only one new tab per Cmd+T
  - Frecency ranking ([1oqxwdx](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/), [1tjcutb](https://www.reddit.com/r/vivaldibrowser/comments/1tjcutb/vivaldi_80_our_biggest_design_overhaul_ever/))
- Ctrl-Tab MRU switcher that matches the rest of the UI ([1qzoc4q](https://www.reddit.com/r/zen_browser/comments/1qzoc4q/cntrl_tab_ui_in_zen/)).
- New-tab minimalism: a clock and shortcuts on the NTP read as "bloated" (+50, [1ukf1mq](https://www.reddit.com/r/browsers/comments/1ukf1mq/clean_helium_browser/)).

### Colour, tinting and theming
- Per-space colour as identity (Arc, [1x3kpcw](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/) +32, +62).
- Chrome adopting the site's colour:
  - Dia's window tinting ([1oqxwdx](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/) [113|65c])
  - Zen Page Tint ([1u7e2ew](https://www.reddit.com/r/zen_browser/comments/1u7e2ew/zen_page_tint_chrome_that_adapts_its_color_to_the/) [299|16c])
  - Zia ([1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/))
  - Wallpaper-following themes ([zen-wabi](https://www.reddit.com/r/zen_browser/comments/1tyllfb/zenwabi_a_matugen_driven_zen_browser_theme_that/) [265|32c])
- How to keep tinting fast: Zen Page Tint's author with 1,000+ tabs: "Samples once per tab switch, with a cache… Never animates color across the tab strip (this tanks performance)". Two comments push back: "Hope this can be turned on and off" (+7, [1oqxwdx](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/)) and "Whats with the purple color?… Why not use neutral colors?" (+32, Firefox Nova).
- Whimsy has an audience ([macaron theme](https://www.reddit.com/r/zen_browser/comments/1sz78cr/this_browser_theme_looks_edible/) [686|49c] "Your browser deserved more whimsy"), but most of it lives in themes rather than defaults.
- **MBGA rule**:
  - The space colour drives the sidebar and window tint, with a neutral default.
  - Page-derived tint is optional, sampled once per navigation and cached.
  - Animate only the single background layer, never every row.

### Delight and micro-feedback (what "premium" means in practice)
- Arc's equaliser animation on the playing tab ([1qi4yuc](https://www.reddit.com/r/ArcBrowser/comments/1qi4yuc/its_those_little_things_that_make_me_fall_in_love/)).
- The mini player across spaces ([1tb54fw](https://www.reddit.com/r/ArcBrowser/comments/1tb54fw/this_little_player_across_spaces_deserves_more/), image `arc-mini-player.webp`).
- Subtle cues for downloads, copy and background-opened tabs ([1sp3isz](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/), +3).
- Zia's downloads ring, paperclip copy and 10-second undo ([1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/)).
- "Would love to see more smooth animations added to different UI elements" (+13, [1vhdlrg](https://www.reddit.com/r/zen_browser/comments/1vhdlrg/looking_for_feedback_for_the_latest_release/)).
- Choppy animations are noticed (+13, [1ugtovk](https://www.reddit.com/r/browsers/comments/1ugtovk/damn_helium_is_slick_af/)).

### Organisation features (beyond vertical tabs)
- Nested folders (+29, [1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/)). Air Traffic Control / Smart Routing: "no traffic control. Pass" (+157, same thread); Zen's Smart Routing post [700](https://www.reddit.com/r/zen_browser/comments/1tw1kvw/wip_i_think_prior_arc_users_are_gonna_love_this/).
- Live Folders ([537](https://www.reddit.com/r/zen_browser/comments/1rhv2r8/introducing_live_folders/)), Arc's Pull Requests smart folder (+60, [1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/)).
- Folder tree connectors ([340](https://www.reddit.com/r/zen_browser/comments/1tohb8h/zen_folder_tree_connectors_v20_sine_mod/)).
- Split by dragging a tab onto the page, plus "stick one tab on one side and browse through multiple tabs on the other side" (+17, [1rkizow](https://www.reddit.com/r/zen_browser/comments/1rkizow/making_split_views_more_intuitive/)).
- Arc-style hover previews on pinned apps ([gmail-peek](https://www.reddit.com/r/zen_browser/comments/1wtlht7/arcstyle_gmail_preview_when_you_hover_your_pinned/)).
- An overview of all spaces side by side (image `arc-spaces-overview.webp`, [1tjiihh](https://www.reddit.com/r/ArcBrowser/comments/1tjiihh/nothing_has_come_even_remotely_close_to_arcs/)).

---

## Dealbreakers (why people abandon a new browser)

1. **No serious ad-blocking / no uBlock Origin.** It is the year's biggest anxiety, because Manifest V2 is ending in Chromium browsers. "Vibe coded and no uBlockOrigin support. I'll pass" (+73, [Firn](https://www.reddit.com/r/browsers/comments/1x50fky/firn_a_calm_free_opensource_chromium_browser_with/)). Helium's appeal is "Zero bloatware + ubo" (+47, [1sldzxc](https://www.reddit.com/r/browsers/comments/1sldzxc/why_is_everyone_talking_about_helium/)). Recent losses: Edge dropped uBO ([1wuehfj](https://www.reddit.com/r/browsers/comments/1wuehfj/it_was_good_while_it_lasted/) [799|542c] 2026-09-30), Vivaldi users said "Good bye uBlock Origin" ([1urieed](https://www.reddit.com/r/vivaldibrowser/comments/1urieed/good_bye_ublock_origin/) [356|551c]), Chrome is killing bypasses ([1u1o27d](https://www.reddit.com/r/browsers/comments/1u1o27d/google_chrome_is_killing_all_ublock_origin/) [429|208c]). Commenters say Brave (selected MV2 extensions) and Vivaldi ("re-enable and extend Manifest V2… for the time being", +39) still hold on ([1vo7q9e](https://www.reddit.com/r/browsers/comments/1vo7q9e/now_firefox_left_the_only_major_browser_still/)). People also want an element picker ([1ufzywu](https://www.reddit.com/r/vivaldibrowser/comments/1ufzywu/team_vivaldi_we_need_to_talk/)).
2. **Performance: RAM, heat, battery, launch speed.** Zen "turns my mac into hot pan" ([1u36dn3](https://www.reddit.com/r/browsers/comments/1u36dn3/zenarc_alternatives_with_ublock_origin/)) and has memory leaks (+18, [1tf8o36](https://www.reddit.com/r/zen_browser/comments/1tf8o36/browser_market_been_stale_for_years_and_then_zen/)). Safari wins on battery ([1sjg0iy](https://www.reddit.com/r/macapps/comments/1sjg0iy/safari_vs_the_rest_is_it_actually_the_best/)). Helium wins on snappiness ([1ter7mk](https://www.reddit.com/r/browsers/comments/1ter7mk/helium_fucking_rocks/)).
3. **No DRM (Widevine)**, so no Netflix, Spotify or Disney+. It recurs for Zen and Helium ([1omlvfi](https://www.reddit.com/r/browsers/comments/1omlvfi/arc_vs_zen/), [1tjc2yk](https://www.reddit.com/r/ArcBrowser/comments/1tjc2yk/ive_made_a_100_arc_zen_migration_tool/), [1svli5p](https://www.reddit.com/r/browsers/comments/1svli5p/is_helium_the_best_minimalist_browser_right_now/) +40). One stay-on-Arc reason was "Netflix and Spotify just works" ([1qw987p](https://www.reddit.com/r/ArcBrowser/comments/1qw987p/ive_decided_to_stick_with_arc/)). *Relevant to CEF: stock CEF builds need Widevine work; worth verifying.*
4. **No sync.** "Zen's (Mozilla's) sync is shit. That alone makes it unusable for multi-device people" (+14, [1qw987p](https://www.reddit.com/r/ArcBrowser/comments/1qw987p/ive_decided_to_stick_with_arc/)). Also [1tq5brt](https://www.reddit.com/r/zen_browser/comments/1tq5brt/i_dont_understand_zens_current_feature_priorities/), Helium ([1x820gb](https://www.reddit.com/r/browsers/comments/1x820gb/helium_probably_the_only_browser_ive_went_to/) +8) and Vivaldi ("Great idea, never fully finished", +15).
5. **Password managers and extensions.** "It's a non starter without 1Password" ([Emerald](https://www.reddit.com/r/ArcBrowser/comments/1sbo321/ive_been_building_a_browser_inspired_by_arc/)). Bitwarden, Todoist and others come up for [Crest](https://www.reddit.com/r/browsers/comments/1vjef6c/crest_browser_inspired_by_arc_testflight_open/). People choose Chromium over Gecko for extensions ([1wx9w66](https://www.reddit.com/r/browsers/comments/1wx9w66/i_need_chromium_alternative_to_zen/)).
6. **Trust and longevity.** "Vibe-coded" or Electron gets dismissed ([Firn](https://www.reddit.com/r/browsers/comments/1x50fky/firn_a_calm_free_opensource_chromium_browser_with/) +203; [Mori](https://www.reddit.com/r/ArcBrowser/comments/1u94qnt/made_a_chromiumbased_arc_alternative_free/) +188). So do serial launchers ([Viola](https://www.reddit.com/r/ArcBrowser/comments/1vb2efy/i_build_a_spiritual_successor_to_arc/) +66). People fear abandonment: Arc's fate; "hope this doesn't vanish like all other apps" ([1wtlht7](https://www.reddit.com/r/zen_browser/comments/1wtlht7/arcstyle_gmail_preview_when_you_hover_your_pinned/) +12); doubts about Helium's devs (+28). Corporate betrayal also counts (+101, Dia).
7. **Missing Arc primitives**: spaces as real profiles, nested folders, traffic control, Peek, Little Arc ([1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/), [1qfugz7](https://www.reddit.com/r/ArcBrowser/comments/1qfugz7/chrome_with_vertical_pinned_tabs_is_basically_arc/), [1oqxwdx](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/)).
8. **Import.** Moving off Arc is easier with a full import; people liked Dia's Arc import and a tool that migrates "workspaces, tabs, pins, favicons and even workspace icons and background colors" ([1tjc2yk](https://www.reddit.com/r/ArcBrowser/comments/1tjc2yk/ive_made_a_100_arc_zen_migration_tool/) [153|38c]).
9. **Regressions and hijacked habits**: new features taking over familiar shortcuts (Zen Library, +19); site breakage and bugs ("Arc is breaking"); an account wall (Dia).
10. **Unwanted AI.** A pro-simplicity crowd counts "no AI" as a feature (Vivaldi's pledge [1uazrj7](https://www.reddit.com/r/vivaldibrowser/comments/1uazrj7/vivaldis_leader_has_a_bold_pledge_no_ai_in_your/) [436|38c]; Helium [1svli5p](https://www.reddit.com/r/browsers/comments/1svli5p/is_helium_the_best_minimalist_browser_right_now/) +33/+30; Safari [1sjg0iy](https://www.reddit.com/r/macapps/comments/1sjg0iy/safari_vs_the_rest_is_it_actually_the_best/) +28).

---

## Top ideas for MBGA (ranked)

1. **An active tab you can't miss, plus Arc-grade micro-feedback.** Give the selected row an opaque pill with a subtle shadow and semibold title. Add three cues:
   - copying the URL shows a "Copied" toast that springs out of the URL field
   - a tab opened in the background flies into the sidebar
   - a download shows a progress ring by the space name

   Sources: [1sp3isz](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/), [1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/), [1qi4yuc](https://www.reddit.com/r/ArcBrowser/comments/1qi4yuc/its_those_little_things_that_make_me_fall_in_love/).
2. **Compact mode that never feels clunky.** Use the hover-reveal spec above:
   - 120 ms intent delay
   - hysteresis zone outside the window
   - the screen edge counts as inside
   - the sidebar floats over the page with no reflow
   - a hidden drag strip and Cmd+S to pin

   Sources: [1vhdlrg](https://www.reddit.com/r/zen_browser/comments/1vhdlrg/looking_for_feedback_for_the_latest_release/), [1vda1k6](https://www.reddit.com/r/zen_browser/comments/1vda1k6/how_to_make_sidebar_stays_open_when_the_cursor_on/), [1x820gb](https://www.reddit.com/r/browsers/comments/1x820gb/helium_probably_the_only_browser_ive_went_to/), [1rxudf4](https://www.reddit.com/r/vivaldibrowser/comments/1rxudf4/vivaldi_79_immerse_yourself_in_the_web_with_every/), [1pz3to1](https://www.reddit.com/r/zen_browser/comments/1pz3to1/did_i_just_miss_this_feature_before/).
3. **URL in the sidebar, Cmd+T/Cmd+L as one command bar.**
   - The URL is a compact field at the top of the sidebar showing just the host.
   - Cmd+T opens the bar over the current page (no new-tab page) and creates exactly one tab.
   - Rank results by frecency with inline host completion; press Tab to search inside a site and ⌘⏎ to force a web search.

   Sources: [1t0aths](https://www.reddit.com/r/browsers/comments/1t0aths/finally_helium_is_now_looking_like_arc/), [1ter7mk](https://www.reddit.com/r/browsers/comments/1ter7mk/helium_fucking_rocks/), [1oqxwdx](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/), [1tjcutb](https://www.reddit.com/r/vivaldibrowser/comments/1tjcutb/vivaldi_80_our_biggest_design_overhaul_ever/), [1ufwcm3](https://www.reddit.com/r/browsers/comments/1ufwcm3/im_annoyed_by_zens_memory_usage_on_my_16gb/).
4. **Space colour as identity, with swipe.**
   - Each space's colour or gradient tints the sidebar and window background.
   - A two-finger horizontal swipe (or mouse side-scroll) slides between spaces; animate the tint crossfade on one layer only.
   - The emoji appears in the space bar and in routing pickers.

   Sources: [1x3kpcw](https://www.reddit.com/r/ArcBrowser/comments/1x3kpcw/browser_company_pushing_arc_users_to_make_the/), [1tjiihh](https://www.reddit.com/r/ArcBrowser/comments/1tjiihh/nothing_has_come_even_remotely_close_to_arcs/), [1oqxwdx](https://www.reddit.com/r/diabrowser/comments/1oqxwdx/soon_your_tabs_will_feel_like_apps_in_diabrowser/).
5. **Built-in uBO-class blocking in the Rust core.** Brave's `adblock-rust` engine is Rust and reads uBO/EasyList filter syntax. Add cosmetic filtering and an element picker, and use it as a launch headline. This answers the year's #1 dealbreaker without depending on MV2. Sources: dealbreaker #1 threads.
6. **Glass only on chrome.** Use materials on the sidebar, command bar, popovers and the compact floating sidebar; never on page content. Keep an opaque-enough row layer and honour Reduce Transparency. Sources: [1uxbvda](https://www.reddit.com/r/zen_browser/comments/1uxbvda/zen_looks_so_premium/), [1rmnuho](https://www.reddit.com/r/zen_browser/comments/1rmnuho/this_browser_is_literally_so_aesthetic/), [1sp3isz](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/).
7. **Traffic-control routing.** Rules map a domain to a space (Contains / Is / RegEx), with a default route for links from other apps ("Most recent space"). Offer "Always open github.com in 💼 Work?" the first time it's relevant. Sources: [1tw1kvw](https://www.reddit.com/r/zen_browser/comments/1tw1kvw/wip_i_think_prior_arc_users_are_gonna_love_this/) (700), [1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/) (+157 "no traffic control. Pass").
8. **Universal undo in the sidebar.** Cmd+Z restores the last close, folder delete, split or archive for at least 10 seconds, with an "Undo" pill. Dragging a tab onto the page splits; dragging onto a tab reorders, with clear drop targets. Sources: [1rkizow](https://www.reddit.com/r/zen_browser/comments/1rkizow/making_split_views_more_intuitive/), [1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/).
9. **Mini player card and a "now playing" equaliser.**
   - The card sits pinned at the sidebar bottom and follows you across spaces.
   - Controls: play/pause, skip, PiP; clicking jumps back to the tab.
   - A tiny animated equaliser replaces the speaker icon on the playing tab.

   Sources: [1tb54fw](https://www.reddit.com/r/ArcBrowser/comments/1tb54fw/this_little_player_across_spaces_deserves_more/), [1qi4yuc](https://www.reddit.com/r/ArcBrowser/comments/1qi4yuc/its_those_little_things_that_make_me_fall_in_love/), [Viola](https://www.reddit.com/r/ArcBrowser/comments/1vb2efy/i_build_a_spiritual_successor_to_arc/), [Vivaldi setup](https://www.reddit.com/r/vivaldibrowser/comments/1s942b8/beauty_of_vivaldi/).
10. **Concentric, modest geometry.**
    - Content-card radius = window radius − inset; inset about 6–8 pt, or 0 when the sidebar is hidden.
    - One hairline or one shadow, never a thick frame. Peek uses 16 pt over an 8 pt background.

    Sources: [1tjctdo](https://www.reddit.com/r/vivaldibrowser/comments/1tjctdo/vivaldi_80_is_out_with_biggest_design_overhaul/), [1ov0806](https://www.reddit.com/r/FirefoxCSS/comments/1ov0806/does_anyone_know_how_we_can_unround_our_tabs/), [1rn8m9h](https://www.reddit.com/r/FirefoxCSS/comments/1rn8m9h/new_redesign_coming_to_firefox_prepare_for_major_theme_breakage/), [1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/).
11. **Peek (Shift-click / link from a pinned app).** Show a floating card over a dimmed page, with buttons to "open as tab" or "split". Sources: Arc must-haves ([1x45mpk](https://www.reddit.com/r/ArcBrowser/comments/1x45mpk/i_finally_left_arc_for_dia_zero_regrets_arc/)), Firn's Lookout, Emerald/Crest Peek, [Arc Peek for Vivaldi](https://www.reddit.com/r/vivaldibrowser/comments/1sims9p/arc_peek_for_vivaldi_link_preview_with_arcnative/).
12. **A favourites grid that feels alive.**
    - Active tiles fill with a tint sampled from the favicon.
    - Favicons are always fresh.
    - Unread badges and an optional hover preview for mail.

    Sources: [1oq3wbp](https://www.reddit.com/r/diabrowser/comments/1oq3wbp/pinned_tabs_get_a_refreshed_design_in_dia_to/), [1u24x4a](https://www.reddit.com/r/ArcBrowser/comments/1u24x4a/kind_of_annoying_how_arc_has_these_hardcoded_old/), [1wtlht7](https://www.reddit.com/r/zen_browser/comments/1wtlht7/arcstyle_gmail_preview_when_you_hover_your_pinned/).
13. **Loading as a hairline, not a spinner.** Draw a 2 px progress line on the active row and the URL field, and keep the favicon visible. Sources: FirefoxCSS loading-bar posts ([1taxnfs](https://www.reddit.com/r/FirefoxCSS/comments/1taxnfs/add_a_loading_progress_bar_to_the_tabs/) etc.).
14. **Hold ⌘ for numbered tabs, and a native Ctrl-Tab MRU switcher** styled like the command bar. Sources: [1wva442](https://www.reddit.com/r/zen_browser/comments/1wva442/zia_a_diainspired_finish_for_zen_now_in_beta/), [1qzoc4q](https://www.reddit.com/r/zen_browser/comments/1qzoc4q/cntrl_tab_ui_in_zen/).
15. **Quiet system surfaces.** The fullscreen notice is a small pill; the downloads popover shows full filenames; no new-tab clutter. Sources: [1ufvm5u](https://www.reddit.com/r/FirefoxCSS/comments/1ufvm5u/minimal_pillstyle_fullscreen_warning/), [1wwwsqe](https://www.reddit.com/r/zen_browser/comments/1wwwsqe/organise_your_browsing_library_is_here/), [1ukf1mq](https://www.reddit.com/r/browsers/comments/1ukf1mq/clean_helium_browser/).
16. **Trust surface.**
    - An About pane showing the CEF/Chromium version and when it was last updated.
    - A public changelog and a clear statement of who builds it.
    - Never hijack standard macOS/Chrome shortcuts.

    Sources: [Firn](https://www.reddit.com/r/browsers/comments/1x50fky/firn_a_calm_free_opensource_chromium_browser_with/), [Mori](https://www.reddit.com/r/ArcBrowser/comments/1u94qnt/made_a_chromiumbased_arc_alternative_free/), [Viola](https://www.reddit.com/r/ArcBrowser/comments/1vb2efy/i_build_a_spiritual_successor_to_arc/), [1wwwsqe](https://www.reddit.com/r/zen_browser/comments/1wwwsqe/organise_your_browsing_library_is_here/).

---

## Images

All files are in `docs/design-research/img/reddit/`, converted to WebP (≤1600 px wide). Scores come from Arctic Shift.

| file | what it shows | source (thread) |
|---|---|---|
| `arc-spaces-overview.webp` | Arc's overview of all spaces as coloured columns side by side (Library → Spaces) | [r/ArcBrowser 1tjiihh](https://www.reddit.com/r/ArcBrowser/comments/1tjiihh/nothing_has_come_even_remotely_close_to_arcs/) [356] 2026-05-21 |
| `arc-mini-player.webp` | Arc's mini media player card at the sidebar bottom, above the space switcher | [r/ArcBrowser 1tb54fw](https://www.reddit.com/r/ArcBrowser/comments/1tb54fw/this_little_player_across_spaces_deserves_more/) [196] 2026-05-12 |
| `dia-active-tab-indistinct.webp` | Negative example: Dia sidebar where the active tab is nearly invisible | [r/diabrowser 1sp3isz](https://www.reddit.com/r/diabrowser/comments/1sp3isz/i_dare_you_to_identify_the_active_tab/) [68] 2026-04-18 |
| `dia-pinned-tiles-brand-color.webp` | Dia pinned/favourite tiles; the active one fills with the site's brand colour (Spotify green) | [r/diabrowser 1oq3wbp](https://www.reddit.com/r/diabrowser/comments/1oq3wbp/pinned_tabs_get_a_refreshed_design_in_dia_to/) [166] 2025-11-06 |
| `dia-tahoe-window-corner-concept.webp` | Concept comparing Dia's window corner/traffic lights with the macOS Tahoe component | [r/diabrowser 1ozuyrx](https://www.reddit.com/r/diabrowser/comments/1ozuyrx/a_redesign_of_the_dia_window_to_finally_comply/) [113] 2025-11-17 |
| `zen-transparency-everywhere.webp` | Contested example: Zen with transparency over web content (Gmail); comments call it cheap or illegible | [r/zen_browser 1uxbvda](https://www.reddit.com/r/zen_browser/comments/1uxbvda/zen_looks_so_premium/) [417] 2026-07-15 |
| `zen-split-view-blur.webp` | Zen split view with frosted sidebar and dark theme ("Most beautiful browser") | [r/browsers 1rn8u5j](https://www.reddit.com/r/browsers/comments/1rn8u5j/most_beautiful_browser_zen/) [190] 2026-03-07 |
| `zen-smart-routing-settings.webp` | Zen Smart Routing dialog: URL rules → emoji spaces, default route for external links | [r/zen_browser 1tw1kvw](https://www.reddit.com/r/zen_browser/comments/1tw1kvw/wip_i_think_prior_arc_users_are_gonna_love_this/) [700] 2026-06-03 |
| `helium-zen-mode-vertical-tabs.webp` | Helium with vertical tabs, favourites grid and hidden address bar ("Zen mode") | [r/browsers 1t0aths](https://www.reddit.com/r/browsers/comments/1t0aths/finally_helium_is_now_looking_like_arc/) [335] 2026-04-30 |
| `vivaldi-autohide-ui.webp` | Vivaldi snapshot with auto-hidden toolbars: a slim title strip, sidebar and full-bleed page | [r/vivaldibrowser 1q6pzcw](https://www.reddit.com/r/vivaldibrowser/comments/1q6pzcw/the_new_vivaldi_snapshot_is_the_dream_browser/) [251] 2026-01-07 |
| `vivaldi-zen-style-setup.webp` | Vivaldi riced to look like Zen: inset page, favourites grid, media card in the sidebar | [r/vivaldibrowser 1s942b8](https://www.reddit.com/r/vivaldibrowser/comments/1s942b8/beauty_of_vivaldi/) [279] 2026-03-31 |
| `firefox-foxone-one-line.webp` | FoxOne userChrome theme: tabs and URL bar in one slim row | [r/FirefoxCSS 1t2hr8f](https://www.reddit.com/r/FirefoxCSS/comments/1t2hr8f/foxone_a_minimalistic_oneline_theme/) [100] 2026-05-03 |
| `firefox-pill-fullscreen-warning.webp` | Before/after: bulky fullscreen banner → minimal pill notice | [r/FirefoxCSS 1ufvm5u](https://www.reddit.com/r/FirefoxCSS/comments/1ufvm5u/minimal_pillstyle_fullscreen_warning/) [98] 2026-06-26 |
| `mori-liquid-glass-sidebar.webp` | Mori (Chromium + SwiftUI/AppKit bridge): Liquid Glass sidebar, favourites, quiet start page | [r/ArcBrowser 1u94qnt](https://www.reddit.com/r/ArcBrowser/comments/1u94qnt/made_a_chromiumbased_arc_alternative_free/) [33] 2026-06-18 |
| `viola-sidebar-attention-player.webp` | Viola: sectioned workspaces sidebar, "Attention" download card, mini player | [r/ArcBrowser 1vb2efy](https://www.reddit.com/r/ArcBrowser/comments/1vb2efy/i_build_a_spiritual_successor_to_arc/) [170] 2026-07-30 |
