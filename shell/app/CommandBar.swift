import SwiftUI

/// Arc-style command bar: type a URL or search, jump to an open tab or a
/// space, run a command, or reopen something closed. Results come in
/// sections, each row shows its shortcut, and ⌘↩ always searches the web.
struct CommandBar: View {
    @EnvironmentObject private var store: BrowserStore
    let mode: CommandBarMode

    @State private var text = ""
    @State private var selection = 0
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private enum Item: Hashable {
        case go(String)
        case search(String)
        case page(HistoryItem)
        case tab(TabInfo, spaceID: UInt64)
        case space(SpaceInfo, index: Int)
        case action(String)
        case closed(TabInfo)
    }

    private struct Section: Identifiable {
        let id: String
        let title: String?
        let items: [Item]
    }

    private var query: String { text.trimmingCharacters(in: .whitespaces) }

    /// MBGA_DEBUG_COMMAND opens the bar at launch with this text, for
    /// screenshots of the results.
    static let debugPreset = ProcessInfo.processInfo.environment["MBGA_DEBUG_COMMAND"].flatMap { $0.isEmpty ? nil : $0 }

    private func sections(_ actions: [CommandAction]) -> [Section] {
        let query = query
        guard !query.isEmpty else { return [] }
        let resolved = store.core.resolveInput(text: query)
        let isAddress = resolved != store.core.searchUrl(text: query)
        let history = store.core.suggestHistory(query: query, limit: 8)

        var tabs: [Item] = []
        var openTabs: [String: Item] = [:]
        var seen = Set<UInt64>()
        let spaces = [store.activeSpace] + store.snapshot.spaces.filter { $0.id != store.activeSpace.id }
        for space in spaces {
            for tab in space.favorites + space.pinned.compactMap(\.tab) + space.today where !seen.contains(tab.id) {
                seen.insert(tab.id)
                let item = Item.tab(tab, spaceID: space.id)
                if openTabs[tab.url] == nil { openTabs[tab.url] = item }
                if tabs.count < 5, matches(query, tab.title, tab.url) { tabs.append(item) }
            }
        }

        // A site the query starts ("git" for github.com) is the likeliest
        // destination, so it comes first (as its open tab, if there is one),
        // then the literal address or search.
        var top: [Item] = []
        if !isAddress, let best = history.first, best.sitePrefix {
            if let open = openTabs[best.url] {
                top.append(open)
                tabs.removeAll { $0 == open }
            } else {
                top.append(.page(best))
            }
        }
        top.append(isAddress ? .go(resolved) : .search(query))

        let spaceItems: [Item] = store.snapshot.spaces.enumerated()
            .filter { store.snapshot.spaces.count > 1 && matches(query, $0.element.name) }
            .prefix(3)
            .map { .space($0.element, index: $0.offset) }

        let actionItems: [Item] = query.count < 2 ? [] : actions
            .filter { $0.matches(query) }
            .prefix(5)
            .map { .action($0.id) }

        let pages: [Item] = history
            .filter { page in
                openTabs[page.url] == nil && !top.contains(.page(page))
            }
            .prefix(5)
            .map { .page($0) }

        let closed: [Item] = store.canReopen
            ? store.core.closedTabs(limit: 25).filter { matches(query, $0.title, $0.url) }.prefix(3).map { .closed($0) }
            : []

        return [
            Section(id: "top", title: nil, items: top),
            Section(id: "tabs", title: "Tabs", items: tabs),
            Section(id: "spaces", title: "Spaces", items: spaceItems),
            Section(id: "actions", title: "Actions", items: actionItems),
            Section(id: "history", title: "History", items: pages),
            Section(id: "closed", title: "Recently Closed", items: closed),
        ].filter { !$0.items.isEmpty }
    }

    private func matches(_ query: String, _ fields: String...) -> Bool {
        let words = query.lowercased().split(separator: " ")
        return words.allSatisfy { word in fields.contains { $0.localizedCaseInsensitiveContains(word) } }
    }

    var body: some View {
        let actions = CommandAction.all(for: store)
        let sections = sections(actions)
        let items = sections.flatMap(\.items)
        let dark = colorScheme == .dark
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(mode == .newTab ? "Search, enter a URL or type a command…" : "Enter URL…", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onSubmit { commit(items, actions) }
                        .onKeyPress(.return, phases: .down) { press in
                            guard press.modifiers.contains(.command), !query.isEmpty else { return .ignored }
                            store.search(query, mode: mode)
                            return .handled
                        }
                }
                .padding(.horizontal, 16)
                .frame(height: 54)

                if !items.isEmpty {
                    Divider().opacity(0.6)
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(sections) { section in
                                if let title = section.title {
                                    Text(title)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, 8)
                                        .padding(.bottom, 2)
                                }
                                ForEach(section.items, id: \.self) { item in
                                    let index = items.firstIndex(of: item) ?? 0
                                    row(item, actions: actions, selected: index == selection)
                                        .onTapGesture {
                                            selection = index
                                            commit(items, actions)
                                        }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 420)
                    .fixedSize(horizontal: false, vertical: true)
                    Divider().opacity(0.6)
                    footer
                }
            }
            .frame(width: 620)
            // A solid card: glass behind text this size hurts legibility.
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(dark ? Color(white: 0.16) : Color(white: 0.99)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(dark ? 0.14 : 0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 32, y: 14)
            .padding(.top, 110)
        }
        .onAppear {
            if mode == .editCurrent { text = store.visibleTab?.url ?? "" }
            if mode == .newTab, let preset = Self.debugPreset { text = preset }
            focused = true
        }
        .onChange(of: text) { selection = 0 }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(items.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onExitCommand { close() }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Spacer()
            hint("↩", "Open")
            hint("⌘↩", "Search the web")
            hint("esc", "Close")
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.system(size: 11, weight: .medium))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ item: Item, actions: [CommandAction], selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .go(let url):
                symbol("globe")
                Text(url).lineLimit(1)
                Spacer(minLength: 8)
                chip("Go")
            case .search(let query):
                symbol("magnifyingglass")
                Text("Search for “\(query)”").lineLimit(1)
                Spacer(minLength: 8)
                chip("Search")
            case .page(let page):
                symbol("clock")
                Text(page.title.isEmpty ? Self.address(page.url) : page.title).lineLimit(1)
                Text(Self.address(page.url)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
            case .tab(let tab, let spaceID):
                FaviconImage(tab: tab)
                Text(tab.displayTitle).lineLimit(1)
                if spaceID != store.activeSpace.id, let space = store.snapshot.spaces.first(where: { $0.id == spaceID }) {
                    Text("\(space.icon) \(space.name)").foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(tab.host).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                chip("Switch to Tab")
            case .space(let space, let index):
                Text(space.icon.isEmpty ? "•" : space.icon).frame(width: 16)
                Text(space.name).lineLimit(1)
                Spacer(minLength: 8)
                if index < 9 { chip("⌃\(index + 1)") }
            case .action(let id):
                if let action = actions.first(where: { $0.id == id }) {
                    symbol(action.symbol)
                    Text(action.title).lineLimit(1)
                    Spacer(minLength: 8)
                    if let shortcut = action.shortcut { chip(shortcut) }
                }
            case .closed(let tab):
                FaviconImage(tab: tab).opacity(0.7)
                Text(tab.displayTitle).lineLimit(1)
                Text(tab.host).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                chip("Reopen")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.primary.opacity(selected ? 0.08 : 0)))
        .contentShape(Rectangle())
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 16)
            .foregroundStyle(.secondary)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.06)))
    }

    /// "https://www.example.com/a" as "example.com/a".
    private static func address(_ url: String) -> String {
        var s = url
        for prefix in ["https://", "http://", "www."] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    private func commit(_ items: [Item], _ actions: [CommandAction]) {
        guard items.indices.contains(selection) else {
            if !query.isEmpty { store.submit(text, mode: mode) }
            return
        }
        switch items[selection] {
        case .go(let url):
            store.submit(url, mode: mode)
        case .search(let query):
            store.search(query, mode: mode)
        case .page(let page):
            store.submit(page.url, mode: mode)
        case .tab(let tab, let spaceID):
            store.commandBar = nil
            store.select(tab.id, in: spaceID)
        case .space(let space, _):
            store.commandBar = nil
            store.activateSpace(space.id)
        case .action(let id):
            store.commandBar = nil
            actions.first { $0.id == id }?.run()
        case .closed(let tab):
            store.commandBar = nil
            store.reopenClosedTab(tab.id)
        }
    }

    private func close() {
        store.commandBar = nil
    }
}

/// A command the bar can run, found by its title or other words for it.
struct CommandAction {
    let id: String
    let title: String
    let symbol: String
    var shortcut: String?
    var keywords: [String] = []
    let run: () -> Void

    func matches(_ query: String) -> Bool {
        let words = (title + " " + keywords.joined(separator: " ")).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return query.lowercased().split(separator: " ").allSatisfy { q in words.contains { $0.hasPrefix(q) } }
    }

    /// The commands that make sense right now.
    @MainActor
    static func all(for store: BrowserStore) -> [CommandAction] {
        var list: [CommandAction] = []
        if let tab = store.visibleTab {
            let space = store.activeSpace
            let pinned = store.isPinned(tab.id, in: space) || store.isFavorite(tab.id, in: space)
            list += [
                CommandAction(id: "pin", title: pinned ? "Unpin Tab" : "Pin Tab", symbol: pinned ? "pin.slash" : "pin",
                              shortcut: "⌘D") { store.togglePin(tab.id) },
                CommandAction(id: "favorite", title: "Add to Favorites", symbol: "star", keywords: ["fav"]) {
                    store.addFavorite(tab.id)
                },
                CommandAction(id: "copy", title: "Copy URL", symbol: "link", shortcut: "⇧⌘C", keywords: ["link", "share"]) {
                    store.copyVisibleURL()
                },
                CommandAction(id: "reload", title: "Reload Page", symbol: "arrow.clockwise", shortcut: "⌘R", keywords: ["refresh"]) {
                    store.reload()
                },
                CommandAction(id: "duplicate", title: "Duplicate Tab", symbol: "plus.square.on.square") {
                    store.duplicate(tab, in: space)
                },
                CommandAction(id: "close", title: pinned ? "Unload Tab" : "Close Tab", symbol: "xmark", shortcut: "⌘W") {
                    store.close(tab.id)
                },
                CommandAction(id: "devtools", title: "Developer Tools", symbol: "hammer", shortcut: "⌥⌘I", keywords: ["inspect", "console"]) {
                    store.showDevTools()
                },
            ]
            if let site = tab.site, store.blockAds {
                list.append(CommandAction(id: "ads", title: tab.adsAllowed ? "Block Ads on \(site)" : "Allow Ads on \(site)",
                                          symbol: "shield.lefthalf.filled", keywords: ["adblock", "trackers", "blocker"]) {
                    store.setAdsAllowed(!tab.adsAllowed, for: tab)
                })
            }
            if let site = tab.site {
                list.append(CommandAction(id: "awake", title: tab.keepAwake ? "Let \(site) Sleep" : "Keep \(site) Awake",
                                          symbol: tab.keepAwake ? "moon.zzz" : "sun.max", keywords: ["sleep", "awake"]) {
                    store.setKeepAwake(!tab.keepAwake, for: tab)
                })
            }
        }
        list += [
            CommandAction(id: "new-space", title: "New Space…", symbol: "square.stack", shortcut: "⇧⌘N") {
                store.spaceEditor = SpaceEditorRequest(spaceID: nil)
            },
            CommandAction(id: "edit-space", title: "Edit Space…", symbol: "pencil", keywords: ["rename", "color", "icon"]) {
                store.spaceEditor = SpaceEditorRequest(spaceID: store.activeSpace.id)
            },
            CommandAction(id: "new-folder", title: "New Folder", symbol: "folder.badge.plus", shortcut: "⌥⌘N") {
                store.newFolder()
            },
            CommandAction(id: "clear", title: "Clear Today Tabs", symbol: "archivebox", shortcut: "⇧⌘K", keywords: ["archive", "clean", "tidy"]) {
                store.clearToday(store.activeSpace.id)
            },
            CommandAction(id: "focus", title: store.layout == .focus ? "Leave Focus Mode" : "Focus Mode", symbol: "rectangle.inset.filled",
                          shortcut: "⌘S", keywords: ["hide", "sidebar", "zen"]) {
                store.toggleSidebar()
            },
            CommandAction(id: "compact", title: store.layout == .compact ? "Full Sidebar" : "Compact Sidebar",
                          symbol: "sidebar.squares.left", keywords: ["rail", "icons", "narrow", "layout"]) {
                store.setLayout(store.layout == .compact ? .full : .compact)
            },
            CommandAction(id: "import", title: "Import from Another Browser…", symbol: "square.and.arrow.down", keywords: ["chrome", "arc", "safari"]) {
                store.importSheet = ImportRequest(firstLaunch: false)
            },
            CommandAction(id: "block-ads", title: store.blockAds ? "Turn Off Ad Blocking" : "Block Ads and Trackers",
                          symbol: "shield", keywords: ["adblock", "trackers", "privacy"]) {
                store.setBlockAds(!store.blockAds)
            },
            CommandAction(id: "clear-history", title: "Clear History", symbol: "clock.arrow.circlepath", keywords: ["forget", "privacy"]) {
                store.core.clearHistory()
                store.showToast(Toast(message: "History cleared", symbol: "clock.arrow.circlepath"))
            },
        ]
        if store.canReopen {
            list.append(CommandAction(id: "reopen", title: "Reopen Closed Tab", symbol: "arrow.uturn.backward", shortcut: "⇧⌘T",
                                      keywords: ["undo", "restore"]) { store.undoClose() })
        }
        let matchPage = UserDefaults.standard.bool(forKey: TintStyle.matchPageKey)
        list.append(CommandAction(id: "match-page", title: matchPage ? "Use Space Colour" : "Match Page Colour",
                                  symbol: "eyedropper", keywords: ["theme", "tint", "color", "colour"]) {
            UserDefaults.standard.set(!matchPage, forKey: TintStyle.matchPageKey)
        })
        for style in TintStyle.allCases {
            list.append(CommandAction(id: "tint-\(style.rawValue)", title: "Sidebar Colour: \(style.title)", symbol: "paintpalette",
                                      keywords: ["theme", "tint", "color", "appearance"]) {
                UserDefaults.standard.set(style.rawValue, forKey: TintStyle.defaultsKey)
            })
        }
        return list
    }
}
