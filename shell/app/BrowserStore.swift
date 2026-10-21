import AppKit

struct NavState: Equatable {
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
}

/// How much of the sidebar shows: all of it, an icon rail, or nothing
/// (Focus mode). In the last two the full sidebar slides out at the edge.
enum SidebarLayout: String, CaseIterable {
    case full, compact, focus

    var title: String {
        switch self {
        case .full: "Sidebar"
        case .compact: "Compact"
        case .focus: "Focus"
        }
    }

    static let defaultsKey = "sidebarLayout"
    /// MBGA_DEBUG_LAYOUTS cycles layouts for captures; that must not change
    /// the layout saved for real use (the preferences are shared).
    static let debugCycling = ["MBGA_DEBUG_LAYOUTS", "MBGA_DEBUG_PEEK", "MBGA_DEBUG_LAYOUT"].contains {
        ProcessInfo.processInfo.environment[$0]?.isEmpty == false
    }

    static var saved: SidebarLayout {
        // MBGA_DEBUG_LAYOUT=full|compact|focus starts a test copy in that
        // layout, whatever the shared preferences say.
        if let raw = ProcessInfo.processInfo.environment["MBGA_DEBUG_LAYOUT"], let layout = SidebarLayout(rawValue: raw) {
            return layout
        }
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: defaultsKey), let layout = SidebarLayout(rawValue: raw) { return layout }
        // Before layouts, a hidden sidebar was Focus mode.
        return defaults.object(forKey: "sidebarVisible") as? Bool == false ? .focus : .full
    }
}

enum CommandBarMode: Equatable {
    case newTab
    case editCurrent
}

/// A brief note at the bottom of the window, optionally offering Undo.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var symbol = "checkmark"
    var undoable = false
}

extension NSPasteboard.PasteboardType {
    /// A tab or folder dragged within the sidebar; the data is its id.
    static let sidebarItem = NSPasteboard.PasteboardType("dev.mbga.browser.sidebar-item")
}

/// What part of the store changed, so each view redraws only its part.
enum StoreChange {
    case snapshot, nav, layout, peek, commandBar, toast, media, cleanup, blocked
    case pageColors, dragOverPage, drag, renaming, spaceEditor, importSheet, chrome
    /// The visible tab's developer toolbar: its emulations, how its page
    /// loaded, or whether it shows.
    case developer
    /// An agent started or stopped acting on the visible tab.
    case agent
}

/// A network request, kept for agents (`mbga network`).
struct NetworkEntry {
    let number: Int
    let requestID: String
    let method: String
    let url: String
    var type: String
    var status: Int?
    var mime = ""
    var size: Int?
    let started: Double
    var ended: Double?
    var failure: String?
}

/// A console message, kept for agents (`mbga console`).
struct ConsoleEntry {
    let level: Int
    let text: String
    let source: String
    let line: Int
}

/// The shell's single source of UI state. Browser data lives in the Rust core;
/// this class mirrors it as a snapshot, owns the engine views of loaded tabs
/// and turns user intents into core calls. Views observe it for the kinds of
/// change they show.
@MainActor
final class BrowserStore: NSObject {
    let core: BrowserCore
    private(set) var snapshot: Snapshot {
        didSet { changed(.snapshot) }
    }
    /// How views should animate the snapshot change being reported, if at
    /// all (tidying up, folders opening). Most changes are instant.
    private(set) var snapshotAnimation: Motion.Curve?
    private(set) var nav = NavState() {
        didSet { if nav != oldValue { changed(.nav) } }
    }
    var commandBar: CommandBarMode? {
        didSet {
            if commandBar != nil { releaseWebFocus() }
            if commandBar != oldValue { changed(.commandBar) }
        }
    }
    private(set) var layout = SidebarLayout.saved {
        didSet {
            if !SidebarLayout.debugCycling {
                UserDefaults.standard.set(layout.rawValue, forKey: SidebarLayout.defaultsKey)
            }
            if oldValue != .focus { layoutBeforeFocus = oldValue }
            sidebarPeek = false
            updateTrafficLights()
            changed(.layout)
        }
    }
    /// What Focus mode returns to.
    private var layoutBeforeFocus = SidebarLayout.full
    /// Floating sidebar shown while hovering the left edge with the sidebar
    /// hidden. In Focus mode the traffic lights show only with it.
    var sidebarPeek = false {
        didSet {
            guard sidebarPeek != oldValue else { return }
            updateTrafficLights()
            changed(.peek)
        }
    }
    var spaceEditor: SpaceEditorRequest? {
        didSet { changed(.spaceEditor) }
    }
    var importSheet: ImportRequest? {
        didSet {
            if importSheet != nil { releaseWebFocus() }
            changed(.importSheet)
        }
    }
    var renamingFolder: UInt64? {
        didSet {
            if renamingFolder != nil { releaseWebFocus() }
            if renamingFolder != oldValue { changed(.renaming) }
        }
    }
    private(set) var contentFullscreen = false {
        didSet { changed(.chrome) }
    }
    /// The window's corner radius, which the page's corners follow.
    var windowRadius: CGFloat = 10 {
        didSet { changed(.chrome) }
    }
    private(set) var toast: Toast? {
        didSet { changed(.toast) }
    }
    /// A tab whose media was paused from the mini player; it keeps the
    /// player showing so it can be resumed.
    private(set) var pausedMediaTab: UInt64? {
        didSet { changed(.media) }
    }
    /// Number of old Today tabs in the active space, when MBGA should offer
    /// to tidy them up.
    private(set) var cleanupOffer: Int? {
        didSet { if cleanupOffer != oldValue { changed(.cleanup) } }
    }
    /// Ads and trackers blocked on the visible tab's page.
    private(set) var visibleBlockedCount = 0 {
        didSet { if visibleBlockedCount != oldValue { changed(.blocked) } }
    }
    /// The same for every loaded tab, reported to views only for the visible
    /// tab, so a loading page doesn't redraw on every blocked request.
    private var blockedCounts: [UInt64: Int] = [:]
    private var blockedCountTimer: Timer?
    /// Developer Mode emulations by tab, and how each page loaded.
    private var devStates: [UInt64: DevTabState] = [:]
    private var devReports: [UInt64: DevPageReport] = [:]
    /// Tabs whose developer toolbar was shown or hidden by hand (⇧⌘D).
    private var devToolbarOverrides: [UInt64: Bool] = [:]
    /// Opens Settings, at a pane if given.
    var openSettings: ((SettingsPane?) -> Void)?
    /// Agents' preferences, kept in the data folder.
    lazy var agentPreferences = AgentPreferences.load(from: dataDirectory)
    /// Requests since agents started following each tab, oldest first.
    private var networkLogs: [UInt64: [NetworkEntry]] = [:]
    private var networkNumbers: [UInt64: Int] = [:]
    /// Console messages since each page loaded, newest last.
    private var consoleLogs: [UInt64: [ConsoleEntry]] = [:]
    /// Tabs an agent acted on in the last moments, which glow on screen.
    private(set) var agentActiveTabs: Set<UInt64> = []
    private var agentTimers: [UInt64: Timer] = [:]
    /// Theme colors pages declared, by site, so a site that was put to sleep
    /// keeps its color.
    private(set) var pageColors: [String: RGB] = [:] {
        didSet { changed(.pageColors) }
    }
    /// The tab being dragged over the page, which would pop out on drop.
    private(set) var dragOverPage: UInt64? {
        didSet { if dragOverPage != oldValue { changed(.dragOverPage) } }
    }

    private struct Observer {
        weak var owner: AnyObject?
        let handle: @MainActor (StoreChange) -> Void
    }
    private var observers: [Observer] = []

    /// Calls `handle` with every change for as long as `owner` lives.
    func observe(_ owner: AnyObject, _ handle: @escaping @MainActor (StoreChange) -> Void) {
        observers.append(Observer(owner: owner, handle: handle))
    }

    private func changed(_ change: StoreChange) {
        observers.removeAll { $0.owner == nil }
        for observer in observers where observer.owner != nil {
            observer.handle(change)
        }
    }

    let pager = PagerModel()
    let webContainer = WebContainerView()
    weak var window: NSWindow?
    /// Tab or folder being dragged out of the sidebar.
    private(set) var draggingItem: UInt64? {
        didSet { if (draggingItem == nil) != (oldValue == nil) { changed(.drag) } }
    }

    var isDragging: Bool { draggingItem != nil }

    private var views: [UInt64: MBWebView] = [:]
    private var navStates: [UInt64: NavState] = [:]
    private var refreshPending = false
    private var persistTimer: Timer?
    private var toastTimer: Timer?
    private var littleWindows: [UInt64: LittleWindow] = [:]
    private var enteredFullscreenForContent = false
    private var lastVisibleTab: UInt64?
    /// The space whose page is on screen, to crossfade on a switch.
    private var shownSpace: UInt64?

    init(core: BrowserCore) {
        self.core = core
        snapshot = core.snapshot()
        super.init()
        pager.pageCount = snapshot.spaces.count
        pager.setPosition(CGFloat(activeSpaceIndex), animated: false)
        pager.onSettle = { [weak self] index in
            guard let self, snapshot.spaces.indices.contains(index) else { return }
            activateSpace(snapshot.spaces[index].id)
        }
        pager.onSwipeTowards = { [weak self] index in
            guard let self, snapshot.spaces.indices.contains(index) else { return }
            warmSpace(snapshot.spaces[index].id)
        }
        webContainer.viewport = { [weak self] view in self?.devStates[view.tabID]?.viewport }
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    // MARK: - Derived state

    var activeSpace: SpaceInfo {
        snapshot.spaces.first { $0.id == snapshot.activeSpace } ?? snapshot.spaces[0]
    }

    var activeSpaceIndex: Int {
        snapshot.spaces.firstIndex { $0.id == snapshot.activeSpace } ?? 0
    }

    var visibleTabID: UInt64? { activeSpace.activeTab }

    var visibleTab: TabInfo? { visibleTabID.flatMap { core.tab(id: $0) } }

    /// Tabs of the active space in sidebar order: favorites, pinned, today.
    var orderedTabs: [TabInfo] {
        let space = activeSpace
        return space.favorites + space.pinned.compactMap(\.tab) + space.today
    }

    func isFavorite(_ id: UInt64, in space: SpaceInfo) -> Bool {
        space.favorites.contains { $0.id == id }
    }

    func isPinned(_ id: UInt64, in space: SpaceInfo) -> Bool {
        space.pinned.contains { $0.id == id }
    }

    private func space(owning tabID: UInt64) -> SpaceInfo? {
        snapshot.spaces.first { s in
            s.today.contains { $0.id == tabID } || s.pinned.contains { $0.id == tabID }
        }
    }

    // MARK: - Sync

    func setNeedsRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    /// Pulls a new snapshot if the core changed and makes the visible tab live.
    /// Views animate the change along `animation` if given.
    func refresh(animation: Motion.Curve? = nil) {
        refreshPending = false
        if core.revision() != snapshot.revision {
            let next = core.snapshot()
            pager.pageCount = next.spaces.count
            snapshotAnimation = animation
            snapshot = next
            snapshotAnimation = nil
            pager.show(activeSpaceIndex, animated: true)
            schedulePersist()
        }
        syncWebViews()
    }

    private func syncWebViews() {
        let visible = visibleTabID
        if let id = visible, views[id] == nil, let tab = core.tab(id: id) {
            createView(for: tab)
        }
        if let id = visible, core.thaw(id: id) {
            views[id]?.setFrozen(false)
        }
        let switchedSpace = shownSpace != nil && shownSpace != snapshot.activeSpace
        shownSpace = snapshot.activeSpace
        webContainer.show(visible.flatMap { views[$0] }, crossfade: switchedSpace)
        nav = visible.flatMap { navStates[$0] } ?? NavState()
        publishBlockedCount()
        // A tab left playing should show the mini player right away rather
        // than at the next idle check.
        if lastVisibleTab != visible {
            if let previous = lastVisibleTab {
                views[previous]?.probeMedia()
                // Picking an element ends with the page out of sight.
                if devStates[previous]?.picking == true {
                    devStates[previous]?.picking = false
                    views[previous]?.setPicking(false)
                }
            }
            lastVisibleTab = visible
            changed(.developer)
            changed(.agent)
        }
    }

    private func createView(for tab: TabInfo) {
        guard let profile = core.profileOfTab(tabId: tab.id) else { return }
        let url = tab.url.isEmpty ? "about:blank" : tab.url
        let view = MBWebView(url: url, profilePath: core.profileDir(profileId: profile), tabID: tab.id)
        view.delegate = self
        // A tab put to sleep wakes with the emulations it had.
        if let state = devStates[tab.id] { view.apply(state) }
        views[tab.id] = view
        webContainer.add(view)
        core.setLive(id: tab.id, live: true)
        setNeedsRefresh()
    }

    /// Destroys a tab's engine view, freeing its renderer.
    private func destroyView(_ id: UInt64) {
        if let little = littleWindows.removeValue(forKey: id) {
            core.setShownElsewhere(id: id, shown: false)
            little.dismiss()
        }
        guard let view = views.removeValue(forKey: id) else { return }
        navStates[id] = nil
        blockedCounts[id] = nil
        devReports[id] = nil
        consoleLogs[id] = nil
        networkLogs[id] = nil
        devStates[id]?.picking = false
        if pausedMediaTab == id { pausedMediaTab = nil }
        view.isHidden = true
        view.close()
    }

    private func destroyViews(_ ids: [UInt64]?) {
        ids?.forEach(destroyView)
    }

    /// The page keeps keyboard focus until something else takes first
    /// responder.
    private func releaseWebFocus() {
        window?.makeFirstResponder(nil)
    }

    private func focusVisibleContent() {
        if let id = visibleTabID { views[id]?.focusContent() }
    }

    /// Saves 2 s after the first unsaved change. A throttle, not a debounce:
    /// pages whose title changes every second must not postpone saving forever.
    private func schedulePersist() {
        guard persistTimer?.isValid != true else { return }
        let timer = Timer(timeInterval: 2, repeats: false) { [core] _ in _ = core.persist() }
        RunLoop.main.add(timer, forMode: .common)
        persistTimer = timer
    }

    // MARK: - Tabs

    func select(_ tabID: UInt64, in spaceID: UInt64? = nil) {
        // A tab in a little window comes back to the main window.
        if let little = littleWindows[tabID] {
            little.putBack()
            return
        }
        let spaceID = spaceID ?? activeSpace.id
        if spaceID != snapshot.activeSpace { core.setActiveSpace(id: spaceID) }
        core.activateTab(spaceId: spaceID, tabId: tabID)
        refresh()
        focusVisibleContent()
    }

    func submit(_ input: String, mode: CommandBarMode) {
        open(core.resolveInput(text: input), mode: mode)
    }

    /// Searches the web for `query` even if it looks like an address.
    func search(_ query: String, mode: CommandBarMode) {
        open(core.searchUrl(text: query), mode: mode)
    }

    private func open(_ url: String, mode: CommandBarMode) {
        commandBar = nil
        guard !url.isEmpty else { return }
        if mode == .editCurrent, let id = visibleTabID {
            core.updateTab(id: id, url: url, title: nil)
            views[id]?.loadURL(url)
        } else {
            _ = core.openTab(spaceId: activeSpace.id, url: url, activate: true)
        }
        refresh()
        focusVisibleContent()
    }

    func openFromSystem(_ url: String) {
        commandBar = nil
        _ = core.openTab(spaceId: activeSpace.id, url: url, activate: true)
        refresh()
    }

    func close(_ tabID: UInt64) {
        _ = core.closeTab(id: tabID)
        destroyView(tabID)
        refresh()
    }

    func closeVisibleTab() {
        if let id = visibleTabID { close(id) }
    }

    /// Unloads a tab but keeps it in the sidebar.
    func sleep(_ tabID: UInt64) {
        guard views[tabID] != nil else { return }
        destroyView(tabID)
        core.setLive(id: tabID, live: false)
        refresh()
    }

    /// Brings back what was closed last: a tab, a cleared Today list, a
    /// tidy-up or a deleted folder.
    func undoClose() {
        toast = nil
        guard let outcome = core.undoClose() else { return }
        refresh()
        if outcome.tabs.count == 1, let id = outcome.tabs.first { select(id, in: outcome.spaceId) }
    }

    func reopenClosedTab(_ id: UInt64) {
        guard let space = core.reopenTab(id: id) else { return }
        select(id, in: space)
    }

    var canReopen: Bool { snapshot.canReopen }

    func duplicate(_ tab: TabInfo, in space: SpaceInfo) {
        _ = core.openTab(spaceId: space.id, url: tab.url, activate: true)
        refresh()
    }

    func togglePin(_ tabID: UInt64, in space: SpaceInfo? = nil) {
        let space = space ?? activeSpace
        if isPinned(tabID, in: space) || isFavorite(tabID, in: space) {
            destroyViews(core.unpinTab(id: tabID))
        } else {
            destroyViews(core.pinTab(id: tabID))
        }
        refresh()
    }

    func togglePinVisibleTab() {
        if let id = visibleTabID { togglePin(id) }
    }

    func setKeepAwake(_ keep: Bool, for tab: TabInfo) {
        core.setKeepAwake(url: tab.url, keep: keep)
        refresh()
    }

    func addFavorite(_ tabID: UInt64) {
        destroyViews(core.addFavorite(id: tabID))
        refresh()
    }

    func move(_ id: UInt64, to target: DropTarget, index: Int) {
        destroyViews(core.moveItem(id: id, target: target, index: UInt32(clamping: index)))
        refresh()
    }

    func clearToday(_ spaceID: UInt64) {
        let closed = core.clearToday(spaceId: spaceID)
        destroyViews(closed)
        // The tabs drop away toward Clear.
        refresh(animation: Motion.settle)
        if !closed.isEmpty {
            showToast(Toast(message: closed.count == 1 ? "Archived 1 tab" : "Archived \(closed.count) tabs",
                            symbol: "archivebox", undoable: true))
        }
    }

    // MARK: - Tidying up

    /// Today tabs untouched this long are offered for tidying up.
    static let cleanupOfferHours: UInt32 = 12

    /// Offers to tidy up once, when the active space has piled up old tabs
    /// and the person hasn't answered before.
    func updateCleanupOffer() {
        guard !snapshot.cleanupAnswered else {
            if cleanupOffer != nil { cleanupOffer = nil }
            return
        }
        let count = Int(core.idleTodayCount(spaceId: activeSpace.id, hours: Self.cleanupOfferHours))
        let offer = count >= 5 ? count : nil
        if offer != cleanupOffer { cleanupOffer = offer }
    }

    enum CleanupAnswer { case notNow, once, daily }

    func answerCleanup(_ answer: CleanupAnswer) {
        core.answerCleanup()
        cleanupOffer = nil
        if answer == .daily { core.setArchiveAfterHours(hours: 24) }
        if answer != .notNow {
            let archived = core.archiveIdle(spaceId: activeSpace.id, hours: Self.cleanupOfferHours)
            destroyViews(archived)
            // The first tidy-up is shown: the tabs drop away toward Clear.
            refresh(animation: Motion.settle)
            showToast(Toast(message: "Archived \(archived.count) tabs", symbol: "archivebox", undoable: true))
        } else {
            refresh()
        }
    }

    /// Hours after which untouched Today tabs are archived; 0 is never.
    var archiveAfterHours: UInt32 { snapshot.archiveAfterHours }

    func setArchiveAfterHours(_ hours: UInt32) {
        core.setArchiveAfterHours(hours: hours)
        if !snapshot.cleanupAnswered { core.answerCleanup() }
        refresh()
        updateCleanupOffer()
    }

    // MARK: - Toasts

    func showToast(_ toast: Toast, duration: TimeInterval = 4) {
        self.toast = toast
        toastTimer?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.toast?.id == toast.id else { return }
                self.toast = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        toastTimer = timer
    }

    func dismissToast() {
        toast = nil
    }

    func selectTab(at index: Int) {
        let tabs = orderedTabs
        // Like other browsers, the last shortcut always selects the last tab.
        let i = index == 8 ? tabs.count - 1 : index
        if tabs.indices.contains(i) { select(tabs[i].id) }
    }

    func selectAdjacentTab(_ offset: Int) {
        let tabs = orderedTabs
        guard !tabs.isEmpty else { return }
        let current = tabs.firstIndex { $0.id == visibleTabID } ?? -1
        let next = (current + offset + tabs.count) % tabs.count
        select(tabs[next].id)
    }

    // MARK: - Navigation

    private var visibleView: MBWebView? { visibleTabID.flatMap { views[$0] } }

    func goBack() { visibleView?.goBack() }
    func goForward() { visibleView?.goForward() }
    func reloadOrStop() { nav.isLoading ? visibleView?.stopLoading() : visibleView?.reload() }
    func reload() { visibleView?.reload() }
    func zoomIn() { visibleView?.zoomIn() }
    func zoomOut() { visibleView?.zoomOut() }
    func resetZoom() { visibleView?.resetZoom() }
    /// ⌥⌘I: opens DevTools, or closes it if docked and open.
    func showDevTools() {
        guard let view = visibleView else { return }
        if view.devToolsWindow != nil { view.closeDevTools() } else { view.showDevTools() }
    }

    /// Opens DevTools, or brings it forward.
    func openDevTools() { visibleView?.showDevTools() }

    var visibleDevToolsOpen: Bool { visibleView?.devToolsWindow != nil }

    func reloadIgnoringCache() { visibleView?.reloadIgnoringCache() }

    func copyVisibleURL() {
        if let url = visibleTab?.url { copyLink(url) }
    }

    func copyLink(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        showToast(Toast(message: "Link copied", symbol: "link"), duration: 1.6)
    }

    // MARK: - Media

    /// The tab the mini player shows: one playing sound out of sight, or
    /// one paused from the player.
    var mediaTab: (tab: TabInfo, space: SpaceInfo)? {
        var found: (TabInfo, SpaceInfo)?
        for space in snapshot.spaces {
            for tab in space.favorites + space.pinned.compactMap(\.tab) + space.today
            where tab.id != visibleTabID && tab.live && (tab.audible || tab.id == pausedMediaTab) {
                if tab.id == pausedMediaTab { return (tab, space) }
                if found == nil { found = (tab, space) }
            }
        }
        return found
    }

    func toggleMedia(_ tabID: UInt64) {
        let pause = pausedMediaTab != tabID
        views[tabID]?.setMediaPaused(pause)
        pausedMediaTab = pause ? tabID : nil
    }

    /// Hides the player for a paused tab.
    func dismissMedia() {
        pausedMediaTab = nil
    }

    // MARK: - Spaces and profiles

    func activateSpace(_ id: UInt64) {
        guard id != snapshot.activeSpace else { return }
        core.setActiveSpace(id: id)
        _ = core.selectDefaultTab(spaceId: id)
        refresh()
        updateCleanupOffer()
    }

    // MARK: - Warming

    /// Loads a tab's page ahead of it being shown (the pointer resting on it
    /// or on its space, a swipe towards its space), so selecting it shows a
    /// loaded page instead of starting the load.
    func warmTab(_ id: UInt64) {
        guard views[id] == nil, let tab = core.tab(id: id), !tab.url.isEmpty else { return }
        createView(for: tab)
    }

    /// Loads the tab another space shows when switched to.
    func warmSpace(_ id: UInt64) {
        guard id != snapshot.activeSpace else { return }
        if let tab = core.selectDefaultTab(spaceId: id) ?? snapshot.spaces.first(where: { $0.id == id })?.activeTab {
            warmTab(tab)
        }
    }

    /// After launch, loads the other spaces' current tabs one at a time,
    /// nearest first, so the first switch to each is instant too.
    func warmOtherSpaces() {
        let current = activeSpaceIndex
        let others = snapshot.spaces.indices.filter { $0 != current }.sorted { abs($0 - current) < abs($1 - current) }
        for (n, index) in others.prefix(4).enumerated() {
            let id = snapshot.spaces[index].id
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5 + Double(n) * 0.8) { [weak self] in
                self?.warmSpace(id)
            }
        }
    }

    /// A space with tabs always shows one: its most recently used, as Arc
    /// does. Only an empty space shows the empty page.
    func showDefaultTab() {
        if core.selectDefaultTab(spaceId: activeSpace.id) != nil { refresh() }
    }

    func activateSpace(at index: Int) {
        if snapshot.spaces.indices.contains(index) { activateSpace(snapshot.spaces[index].id) }
    }

    func activateAdjacentSpace(_ offset: Int) {
        activateSpace(at: min(max(activeSpaceIndex + offset, 0), snapshot.spaces.count - 1))
    }

    func createSpace(name: String, icon: String, color: UInt32, profileID: UInt64) {
        let id = core.createSpace(name: name, icon: icon, color: color, profileId: profileID)
        core.setActiveSpace(id: id)
        refresh()
    }

    func updateSpace(_ id: UInt64, name: String, icon: String, color: UInt32, profileID: UInt64) {
        core.updateSpace(id: id, name: name, icon: icon, color: color)
        destroyViews(core.setSpaceProfile(id: id, profileId: profileID))
        refresh()
    }

    func setProfile(_ profileID: UInt64, for spaceID: UInt64) {
        destroyViews(core.setSpaceProfile(id: spaceID, profileId: profileID))
        refresh()
    }

    func deleteSpace(_ id: UInt64) {
        destroyViews(core.deleteSpace(id: id))
        refresh()
        showDefaultTab()
    }

    func createProfile(_ name: String) -> UInt64 {
        let id = core.createProfile(name: name)
        refresh()
        return id
    }

    func renameProfile(_ id: UInt64, name: String) {
        core.renameProfile(id: id, name: name)
        refresh()
    }

    func deleteProfile(_ id: UInt64) {
        destroyViews(core.deleteProfile(id: id))
        refresh()
    }

    // MARK: - Folders

    func newFolder(in spaceID: UInt64? = nil, parent: UInt64? = nil) {
        let spaceID = spaceID ?? activeSpace.id
        if let id = core.createFolder(spaceId: spaceID, name: "New Folder", parent: parent) {
            renamingFolder = id
        }
        refresh()
    }

    func renameFolder(_ id: UInt64, to name: String) {
        renamingFolder = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { core.renameFolder(id: id, name: trimmed) }
        refresh()
    }

    func setFolder(_ id: UInt64, expanded: Bool) {
        core.setFolderExpanded(id: id, expanded: expanded)
        refresh(animation: Motion.quick)
    }

    func deleteFolder(_ id: UInt64) {
        let name = activeSpace.pinned.first { $0.id == id }?.folderName
        destroyViews(core.deleteFolder(id: id))
        refresh()
        showToast(Toast(message: name.map { "Deleted “\($0)”" } ?? "Deleted folder", symbol: "trash", undoable: true))
    }

    // MARK: - Drag and drop

    /// A tab or folder started being dragged out of the sidebar. Pages
    /// refuse drops meanwhile, so letting go over one pops the tab out
    /// instead of navigating the page to it.
    func beginDrag(_ id: UInt64) {
        draggingItem = id
        MBEngine.setRejectsDrops(true)
    }

    /// Follows the drag (screen coordinates): over the page, the window
    /// shows where a little window would open.
    func dragMoved(to point: NSPoint) {
        guard let id = draggingItem else { return }
        let overPage = core.tab(id: id) != nil && pageFrameOnScreen?.contains(point) == true
        dragOverPage = overPage ? id : nil
    }

    /// The drag ended at `point`; `accepted` if something took the item. A
    /// tab let go over the page opens in a little window.
    func endDrag(at point: NSPoint, accepted: Bool) {
        MBEngine.setRejectsDrops(false)
        let id = draggingItem
        draggingItem = nil
        let overPage = dragOverPage != nil
        dragOverPage = nil
        if let id, !accepted, overPage, core.tab(id: id) != nil {
            openInLittleWindow(id, near: point)
        }
    }

    /// A sidebar item dropped on a target.
    func drop(_ id: UInt64, on target: DropTarget, index: Int) {
        move(id, to: target, index: index)
    }

    /// A link dragged in from a page or another app opens as a tab there.
    func dropURL(_ url: String, on target: DropTarget, index: Int) {
        guard let space = spaceID(of: target),
              let id = core.openTab(spaceId: space, url: url, activate: false)
        else { return }
        move(id, to: target, index: index)
    }

    /// The page area of the main window, in screen coordinates.
    private var pageFrameOnScreen: NSRect? {
        guard let window, webContainer.window === window else { return nil }
        return window.convertToScreen(webContainer.convert(webContainer.bounds, to: nil))
    }

    // MARK: - Little windows

    /// Pops a tab out into a window of its own, near `point` if given.
    func openInLittleWindow(_ tabID: UInt64, near point: NSPoint? = nil) {
        if let little = littleWindows[tabID] {
            little.show()
            return
        }
        guard let tab = core.tab(id: tabID) else { return }
        if views[tabID] == nil { createView(for: tab) }
        guard let view = views[tabID] else { return }
        if core.thaw(id: tabID) { view.setFrozen(false) }
        core.setShownElsewhere(id: tabID, shown: true)
        _ = core.stepAway(id: tabID)
        let little = LittleWindow(tabID: tabID, view: view, store: self, near: point)
        littleWindows[tabID] = little
        refresh()
        little.show()
    }

    func isInLittleWindow(_ tabID: UInt64) -> Bool {
        littleWindows[tabID] != nil
    }

    /// Called as a little window closes: its tab goes back to the main window.
    func littleWindowClosed(_ tabID: UInt64, select: Bool) {
        guard littleWindows.removeValue(forKey: tabID) != nil else { return }
        core.setShownElsewhere(id: tabID, shown: false)
        if let view = views[tabID] { webContainer.add(view) }
        if select {
            self.select(tabID)
            window?.makeKeyAndOrderFront(nil)
        } else {
            refresh()
        }
    }

    private func spaceID(of target: DropTarget) -> UInt64? {
        switch target {
        case .pinned(let spaceId, _), .today(let spaceId): spaceId
        case .favorites: activeSpace.id
        }
    }

    // MARK: - Window color

    /// Space colors for the window, with the active space's replaced by the
    /// visible page's theme color when matching pages, unless that color
    /// would make the sidebar hard to read in this appearance.
    func tintColors(matchPage: Bool, dark: Bool) -> [UInt32] {
        var colors = snapshot.spaces.map(\.color)
        guard matchPage, colors.indices.contains(activeSpaceIndex),
              let site = visibleTab?.site, let page = pageColors[site],
              dark ? page.luminance <= 0.7 : page.luminance >= 0.2
        else { return colors }
        colors[activeSpaceIndex] = page.hex
        return colors
    }

    // MARK: - Ad blocking

    var blockAds: Bool { snapshot.blockAds }

    func setBlockAds(_ enabled: Bool) {
        core.setBlockAds(enabled: enabled)
        refresh()
        guard enabled else {
            reload()
            return
        }
        // The engine was freed while blocking was off; load it, then reload.
        let core = core
        Task {
            _ = await Task.detached(priority: .userInitiated) { core.loadFilters() }.value
            reload()
        }
    }

    /// Turns blocking off or on for a tab's site and reloads it to apply.
    func setAdsAllowed(_ allowed: Bool, for tab: TabInfo) {
        core.setAdsAllowed(url: tab.url, allowed: allowed)
        refresh()
        views[tab.id]?.reload()
    }

    // MARK: - Process model

    var strictSiteIsolation: Bool { snapshot.strictSiteIsolation }

    func setStrictSiteIsolation(_ strict: Bool) {
        core.setStrictSiteIsolation(strict: strict)
        refresh()
    }

    // MARK: - Window chrome

    /// Focus mode on, or back to the layout before it.
    func toggleSidebar() {
        setLayout(layout == .focus ? layoutBeforeFocus : .focus)
    }

    func setLayout(_ layout: SidebarLayout) {
        self.layout = layout
    }

    /// Shows or hides the traffic lights, fading them in Focus mode so they
    /// don't pop. Hidden buttons are also made unclickable.
    private var lightsOffset = CGSize.zero
    private var lightsNativeX: [NSWindow.ButtonType: CGFloat] = [:]
    private var lightsObservers: [NSObjectProtocol] = []
    private var placingLights = false
    /// Where the traffic lights' centres sit below the top of the window (or
    /// of the peek card): the middle of the sidebar's toolbar row, so they
    /// line up with its buttons. AppKit's place, for a plain title bar, is
    /// about 5 points higher.
    static let trafficLightsCenterY: CGFloat = 21

    /// Places the traffic lights on the sidebar's toolbar row, `offset` from
    /// the window's corner: the peek card's corner while the sidebar peeks.
    func offsetTrafficLights(_ offset: CGSize) {
        lightsOffset = offset
        placeTrafficLights()
    }

    private func placeTrafficLights() {
        guard let window, !placingLights else { return }
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = types.compactMap { type in window.standardWindowButton(type).map { (type, $0) } }
        if lightsNativeX.isEmpty {
            for (type, button) in buttons { lightsNativeX[type] = button.frame.minX }
            // AppKit lays the title bar out again now and then (showing the
            // window, a resize, becoming key) and puts the buttons back in
            // its place; put them back in ours.
            for (_, button) in buttons {
                button.postsFrameChangedNotifications = true
                lightsObservers.append(NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification, object: button, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        // Moved while the others were being placed: after.
                        if self.placingLights {
                            DispatchQueue.main.async { [weak self] in self?.placeTrafficLights() }
                        } else {
                            self.placeTrafficLights()
                        }
                    }
                })
            }
        }
        placingLights = true
        defer { placingLights = false }
        for (type, button) in buttons {
            guard let x = lightsNativeX[type], let container = button.superview else { continue }
            // How far the container's top is below the window's top.
            let top = container.isFlipped ? 0 : container.bounds.height
            let topInWindow = container.convert(NSPoint(x: 0, y: top), to: nil).y
            let inset = (window.contentView?.bounds.height ?? topInWindow) - topInWindow
            let centerFromTop = Self.trafficLightsCenterY + lightsOffset.height - inset
            let y = container.isFlipped ? centerFromTop - button.frame.height / 2
                : container.bounds.height - centerFromTop - button.frame.height / 2
            let origin = NSPoint(x: x + lightsOffset.width, y: y.rounded())
            if button.frame.origin != origin { button.setFrameOrigin(origin) }
        }
    }

    func updateTrafficLights() {
        // In Focus mode they show only with the sidebar.
        let hidden = (layout == .focus && !sidebarPeek) || contentFullscreen
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window?.standardWindowButton($0) }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !contentFullscreen
        if !hidden {
            for button in buttons where button.isHidden {
                button.alphaValue = animate ? 0 : 1
                button.isHidden = false
            }
            placeTrafficLights()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animate ? 0.14 : 0
            for button in buttons { button.animator().alphaValue = hidden ? 0 : 1 }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Still meant to be hidden once the fade is over?
                guard let self, hidden, (self.layout == .focus && !self.sidebarPeek)
                    || self.contentFullscreen else { return }
                for button in buttons { button.isHidden = true }
            }
        }
    }

    // MARK: - Memory

    /// Archives old Today tabs if the person chose to, puts idle tabs to
    /// sleep and freezes idle hidden Today tabs according to the core's
    /// policy, then asks the remaining hidden tabs whether they play audio so
    /// they are kept awake.
    func sleepIdleTabs(pressure: MemoryPressure = .normal) {
        let archived = core.archiveByPolicy()
        destroyViews(archived)
        let sleepers = core.collectSleepers(pressure: pressure)
        sleepers.forEach(destroyView)
        let freezers = core.collectFreezers()
        for id in freezers { views[id]?.setFrozen(true) }
        if !archived.isEmpty || !sleepers.isEmpty || !freezers.isEmpty { setNeedsRefresh() }
        for (id, view) in views where id != visibleTabID {
            view.probeMedia()
        }
        updateCleanupOffer()
    }
}

// MARK: - Developer Mode

extension BrowserStore {
    var visibleDevState: DevTabState { visibleTabID.flatMap { devStates[$0] } ?? DevTabState() }
    var visibleDevReport: DevPageReport { visibleTabID.flatMap { devReports[$0] } ?? DevPageReport() }

    /// Whether the visible tab gets the developer toolbar: a local site, or
    /// any site if so set, unless shown or hidden by hand.
    var developerToolbarShown: Bool {
        guard DeveloperSettings.enabled, !contentFullscreen, let tab = visibleTab, !tab.url.isEmpty else { return false }
        if let shown = devToolbarOverrides[tab.id] { return shown }
        return DeveloperSettings.everywhere || DevSite.isLocal(tab.url)
    }

    /// Shows or hides the toolbar on the visible tab, turning Developer Mode
    /// on if needed.
    func toggleDeveloperToolbar() {
        guard let id = visibleTabID else { return }
        if !DeveloperSettings.enabled {
            devToolbarOverrides[id] = true
            UserDefaults.standard.set(true, forKey: DeveloperSettings.enabledKey)
        } else {
            devToolbarOverrides[id] = !developerToolbarShown
        }
        changed(.developer)
    }

    /// Changes the visible tab's emulations and sends the change to its page.
    func updateDev(_ change: (inout DevTabState) -> Void) {
        guard let id = visibleTabID else { return }
        let old = devStates[id] ?? DevTabState()
        var state = old
        change(&state)
        guard state != old else { return }
        devStates[id] = state
        views[id]?.apply(state, from: old)
        if state.viewport != old.viewport { webContainer.viewportChanged() }
        changed(.developer)
    }

    func hardReload() { visibleView?.reloadIgnoringCache() }

    func togglePicking() {
        guard visibleView != nil else { return }
        updateDev { $0.picking.toggle() }
    }

    func setDevice(_ device: DevicePreset?) {
        updateDev {
            $0.device = device
            if device == nil { $0.landscape = false }
        }
    }

    /// Scripts that already ran stay; a reload shows the page without them.
    func toggleScripts() {
        updateDev { $0.scriptsDisabled.toggle() }
        visibleView?.reload()
    }

    func clearSiteData() {
        guard let view = visibleView else { return }
        view.clearSiteDataAndReload()
        showToast(Toast(message: "Site data cleared", symbol: "trash"), duration: 1.6)
    }

    func viewSource() {
        guard let url = visibleTab?.url, !url.isEmpty, !url.hasPrefix("view-source:") else { return }
        _ = core.openTab(spaceId: activeSpace.id, url: "view-source:" + url, activate: true)
        refresh()
    }

    func openVisible(in app: URL) {
        guard let url = visibleTab?.url, let page = URL(string: url) else { return }
        NSWorkspace.shared.open([page], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func loadInVisibleTab(_ url: String) {
        open(url, mode: .editCurrent)
    }

    /// The whole page as PNG, copied and saved to Downloads.
    func screenshotPage() {
        guard let view = visibleView, let tab = visibleTab else { return }
        view.captureFullPage { [weak self] png in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let png else {
                    self.showToast(Toast(message: "Couldn't take the screenshot", symbol: "exclamationmark.triangle"), duration: 2.5)
                    return
                }
                // MBGA_DEBUG_SCREENSHOTS=<dir> saves test copies' screenshots
                // there and leaves the clipboard alone.
                let debugDir = ProcessInfo.processInfo.environment["MBGA_DEBUG_SCREENSHOTS"]
                if debugDir == nil {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setData(png, forType: .png)
                }
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
                let site = DevSite.label(tab.url).replacingOccurrences(of: ":", with: " ").replacingOccurrences(of: "/", with: " ")
                let name = "\(site) \(formatter.string(from: Date())).png"
                let downloads = debugDir.map { URL(fileURLWithPath: $0) }
                    ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                try? png.write(to: downloads.appendingPathComponent(name))
                self.showToast(Toast(message: "Screenshot copied and saved to Downloads", symbol: "camera.viewfinder"), duration: 2.5)
            }
        }
    }

    /// Turning Developer Mode off drops every emulation with the toolbar.
    @objc fileprivate func defaultsChanged() {
        webContainer.placeCurrent()
        if !DeveloperSettings.enabled, !devStates.isEmpty {
            for (id, state) in devStates { views[id]?.apply(DevTabState(), from: state) }
            devStates = [:]
            webContainer.viewportChanged()
        }
        if !DeveloperSettings.enabled { devToolbarOverrides = [:] }
        changed(.developer)
    }

    fileprivate func updateDevReport(_ id: UInt64, _ change: (inout DevPageReport) -> Void) {
        var report = devReports[id] ?? DevPageReport()
        change(&report)
        guard report != devReports[id] else { return }
        devReports[id] = report
        if id == visibleTabID, DeveloperSettings.enabled { changed(.developer) }
    }
}

// MARK: - Agents

extension BrowserStore {
    /// The tab's engine view, made (and its page loaded) if it was asleep.
    func engineView(for id: UInt64) -> MBWebView? {
        if views[id] == nil, let tab = core.tab(id: id), !tab.url.isEmpty { createView(for: tab) }
        return views[id]
    }

    func isLoaded(_ id: UInt64) -> Bool { views[id] != nil && navStates[id] != nil }

    /// Lets a tab out of sight draw (behind the visible page) until the
    /// returned closure is called.
    func renderBehind(_ id: UInt64) -> () -> Void {
        guard id != visibleTabID, let view = views[id] else { return {} }
        return webContainer.renderBehind(view)
    }

    func navState(of id: UInt64) -> NavState { navStates[id] ?? NavState() }

    func devReport(of id: UInt64) -> DevPageReport { devReports[id] ?? DevPageReport() }

    func consoleEntries(of id: UInt64) -> [ConsoleEntry] { consoleLogs[id] ?? [] }

    func networkEntries(of id: UInt64) -> [NetworkEntry] { networkLogs[id] ?? [] }

    func clearNetwork(of id: UInt64) { networkLogs[id] = nil }

    fileprivate func recordNetwork(_ tab: UInt64, _ method: String, _ request: String, _ params: [AnyHashable: Any]) {
        var log = networkLogs[tab] ?? []
        let index = log.lastIndex { $0.requestID == request }
        switch method {
        case "Network.requestWillBeSent":
            guard let info = params["request"] as? [String: Any], let url = info["url"] as? String,
                  !url.hasPrefix("data:") else { return }
            // A new page starts a new log.
            if params["type"] as? String == "Document", params["frameId"] as? String == params["loaderId"] as? String ?? "" { log.removeAll() }
            let number = (networkNumbers[tab] ?? 0) + 1
            networkNumbers[tab] = number
            log.append(NetworkEntry(number: number, requestID: request, method: info["method"] as? String ?? "GET", url: url,
                                    type: (params["type"] as? String ?? "Other").lowercased(),
                                    started: params["timestamp"] as? Double ?? 0))
            if log.count > 300 { log.removeFirst(log.count - 300) }
        case "Network.responseReceived":
            guard let index, let response = params["response"] as? [String: Any] else { return }
            log[index].status = response["status"] as? Int
            log[index].mime = response["mimeType"] as? String ?? ""
        case "Network.loadingFinished":
            guard let index else { return }
            log[index].size = params["encodedDataLength"] as? Int
            log[index].ended = params["timestamp"] as? Double
        case "Network.loadingFailed":
            guard let index else { return }
            log[index].failure = (params["canceled"] as? Bool == true) ? "canceled"
                : params["blockedReason"] as? String ?? params["errorText"] as? String ?? "failed"
            log[index].ended = params["timestamp"] as? Double
        default:
            return
        }
        networkLogs[tab] = log
    }

    func clearConsole(of id: UInt64) { consoleLogs[id] = nil }

    func spaceID(of tabID: UInt64) -> UInt64? {
        snapshot.spaces.first { space in
            (space.favorites + space.pinned.compactMap(\.tab) + space.today).contains { $0.id == tabID }
        }?.id
    }

    /// Opens a tab for an agent in its own space (or the person's, if so
    /// set), never taking the screen unless `focus`.
    func openTabForAgent(_ url: String, focus: Bool) -> UInt64? {
        let space = agentSpaceID()
        let onScreen = focus && space == activeSpace.id
        guard !url.isEmpty, let id = core.openTab(spaceId: space, url: url, activate: onScreen) else { return nil }
        if focus, !onScreen {
            select(id, in: space)
        } else {
            refresh()
        }
        if views[id] == nil, let tab = core.tab(id: id) { createView(for: tab) }
        // From its first request, and its cross-site frames from the start.
        views[id]?.recordsNetwork = true
        views[id]?.attachToFrames()
        return id
    }

    /// The space agents work in: their own, made on first use with the
    /// profile chosen in Settings, so their tabs never crowd the person's.
    func agentSpaceID() -> UInt64 {
        var preferences = agentPreferences
        guard preferences.ownSpace else { return activeSpace.id }
        let profile = agentProfileID()
        if let id = preferences.spaceID, let space = snapshot.spaces.first(where: { $0.id == id }) {
            if space.profileId != profile {
                destroyViews(core.setSpaceProfile(id: id, profileId: profile))
                refresh()
            }
            return id
        }
        let id = core.createSpace(name: "Agents", icon: "✨", color: 0x8B5CF6, profileId: profile)
        preferences.spaceID = id
        agentPreferences = preferences
        agentPreferences.save(to: dataDirectory)
        refresh()
        return id
    }

    /// The profile agents browse as: one of the person's (their sign-ins),
    /// or a separate one with its own cookies.
    func agentProfileID() -> UInt64 {
        var preferences = agentPreferences
        let profiles = snapshot.profiles
        if preferences.separateProfile {
            if let id = preferences.separateProfileID, profiles.contains(where: { $0.id == id }) { return id }
            let id = core.createProfile(name: "Agents")
            preferences.separateProfileID = id
            agentPreferences = preferences
            agentPreferences.save(to: dataDirectory)
            refresh()
            return id
        }
        if let id = preferences.profileID, profiles.contains(where: { $0.id == id }) { return id }
        return snapshot.spaces.first?.profileId ?? profiles.first?.id ?? 0
    }

    func setAgentPreferences(_ change: (inout AgentPreferences) -> Void) {
        change(&agentPreferences)
        agentPreferences.save(to: dataDirectory)
        // A space already made follows the new profile.
        if agentPreferences.ownSpace, agentPreferences.spaceID != nil { _ = agentSpaceID() }
        changed(.agent)
    }

    /// Marks the tab as being worked by an agent for a moment: on screen,
    /// the page glows, so it's clear something other than the person is
    /// acting on it.
    func agentActed(on id: UInt64) {
        let wasActive = agentActiveTabs.contains(id)
        agentActiveTabs.insert(id)
        agentTimers[id]?.invalidate()
        let timer = Timer(timeInterval: 1.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.agentActiveTabs.remove(id)
                self.agentTimers[id] = nil
                if id == self.visibleTabID { self.changed(.agent) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        agentTimers[id] = timer
        if !wasActive, id == visibleTabID { changed(.agent) }
    }

    var agentActingOnVisibleTab: Bool { visibleTabID.map { agentActiveTabs.contains($0) } ?? false }
}

// MARK: - Engine events

extension BrowserStore: MBWebViewDelegate {
    private func isCurrent(_ view: MBWebView) -> Bool {
        views[view.tabID] === view
    }

    nonisolated func webView(_ view: MBWebView, didChangeURL url: String) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            core.updateTab(id: view.tabID, url: url, title: nil)
            setNeedsRefresh()
        }
    }

    nonisolated func webView(_ view: MBWebView, didChangeTitle title: String) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            core.updateTab(id: view.tabID, url: nil, title: title)
            setNeedsRefresh()
        }
    }

    nonisolated func webView(_ view: MBWebView, didChangeLoading loading: Bool, canGoBack: Bool, canGoForward: Bool) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            // A new page starts a new console.
            if loading, navStates[view.tabID]?.isLoading != true { consoleLogs[view.tabID] = nil }
            let state = NavState(isLoading: loading, canGoBack: canGoBack, canGoForward: canGoForward)
            navStates[view.tabID] = state
            if view.tabID == visibleTabID { nav = state }
        }
    }

    nonisolated func webView(_ view: MBWebView, didReceiveFavicon png: Data) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            core.setFavicon(tabId: view.tabID, png: png)
            if let path = core.tab(id: view.tabID)?.faviconPath {
                FaviconCache.shared.invalidate(path)
            }
            setNeedsRefresh()
        }
    }

    nonisolated func webView(_ view: MBWebView, didChangeBusy busy: Bool) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            core.setAudible(id: view.tabID, audible: busy)
            setNeedsRefresh()
        }
    }

    nonisolated func webView(_ view: MBWebView, requestsNewTabWithURL url: String, foreground: Bool) {
        MainActor.assumeIsolated {
            let space = space(owning: view.tabID)?.id ?? activeSpace.id
            _ = core.openTab(spaceId: space, url: url, activate: foreground)
            refresh()
        }
    }

    nonisolated func webView(_ view: MBWebView, didChangeFullscreen fullscreen: Bool) {
        MainActor.assumeIsolated {
            // Pages in little windows use their own window's full screen.
            guard isCurrent(view), let window, view.window === window else { return }
            contentFullscreen = fullscreen
            let windowFullscreen = window.styleMask.contains(.fullScreen)
            if fullscreen && !windowFullscreen {
                enteredFullscreenForContent = true
                window.toggleFullScreen(nil)
            } else if !fullscreen && windowFullscreen && enteredFullscreenForContent {
                enteredFullscreenForContent = false
                window.toggleFullScreen(nil)
            }
            updateTrafficLights()
        }
    }

    nonisolated func webViewRendererDidTerminate(_ view: MBWebView) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            if view.tabID == visibleTabID {
                view.reload()
            } else {
                destroyView(view.tabID)
                core.setLive(id: view.tabID, live: false)
                setNeedsRefresh()
            }
        }
    }

    nonisolated func webView(_ view: MBWebView, didChangeThemeColor color: String) {
        MainActor.assumeIsolated {
            guard isCurrent(view), let site = core.tab(id: view.tabID)?.site else { return }
            let parsed = RGB(css: color)
            if pageColors[site] != parsed { pageColors[site] = parsed }
        }
    }

    nonisolated func webView(_ view: MBWebView, didChangeBlockedCount count: UInt) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            blockedCounts[view.tabID] = Int(count)
            guard view.tabID == visibleTabID else { return }
            // A new page starts at zero right away; increases are batched.
            if count == 0 {
                publishBlockedCount()
            } else if blockedCountTimer?.isValid != true {
                let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.publishBlockedCount() }
                }
                RunLoop.main.add(timer, forMode: .common)
                blockedCountTimer = timer
            }
        }
    }

    private func publishBlockedCount() {
        visibleBlockedCount = visibleTabID.flatMap { blockedCounts[$0] } ?? 0
    }

    nonisolated func webView(_ view: MBWebView, didChangeConsoleErrors errors: UInt, warnings: UInt) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            updateDevReport(view.tabID) {
                $0.errors = Int(errors)
                $0.warnings = Int(warnings)
            }
        }
    }

    nonisolated func webView(_ view: MBWebView, didFinishLoadWithStatus status: Int32, duration: TimeInterval) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            updateDevReport(view.tabID) {
                $0.status = Int(status)
                $0.duration = duration
            }
        }
    }

    nonisolated func webViewDidStopPicking(_ view: MBWebView) {
        MainActor.assumeIsolated {
            guard isCurrent(view), devStates[view.tabID]?.picking == true else { return }
            devStates[view.tabID]?.picking = false
            if view.tabID == visibleTabID { changed(.developer) }
        }
    }

    nonisolated func webView(_ view: MBWebView, didLogConsoleMessage message: String, level: Int, source: String, line: Int32) {
        MainActor.assumeIsolated {
            guard isCurrent(view) else { return }
            var log = consoleLogs[view.tabID] ?? []
            log.append(ConsoleEntry(level: level, text: message, source: source, line: Int(line)))
            if log.count > 200 { log.removeFirst(log.count - 200) }
            consoleLogs[view.tabID] = log
        }
    }

    nonisolated func webView(_ view: MBWebView, didObserveNetworkEvent method: String, params: [AnyHashable: Any]) {
        MainActor.assumeIsolated {
            guard isCurrent(view), let request = params["requestId"] as? String else { return }
            recordNetwork(view.tabID, method, request, params)
        }
    }

    nonisolated func webViewDidChangeDevTools(_ view: MBWebView) {
        MainActor.assumeIsolated {
            guard isCurrent(view), view.tabID == visibleTabID else { return }
            webContainer.placeCurrent()
            changed(.developer)
        }
    }

    nonisolated func webViewDidClose(_ view: MBWebView) {
        MainActor.assumeIsolated {
            view.removeFromSuperview()
        }
    }
}
