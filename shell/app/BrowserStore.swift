import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NavState: Equatable {
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
}

enum CommandBarMode: Equatable {
    case newTab
    case editCurrent
}

enum DropEdge: Equatable {
    case before, after, into
}

struct DropIndicator: Equatable {
    let key: String
    let edge: DropEdge
}

struct SpaceEditorRequest: Identifiable {
    let id = UUID()
    /// nil creates a new space.
    let spaceID: UInt64?
}

extension UTType {
    static let sidebarItem = UTType(exportedAs: "dev.mbga.browser.sidebar-item")
}

/// The shell's single source of UI state. Browser data lives in the Rust core;
/// this class mirrors it as a snapshot, owns the engine views of loaded tabs
/// and turns user intents into core calls.
@MainActor
final class BrowserStore: NSObject, ObservableObject {
    let core: BrowserCore
    @Published private(set) var snapshot: Snapshot
    @Published private(set) var nav = NavState()
    @Published var commandBar: CommandBarMode? {
        didSet { if commandBar != nil { releaseWebFocus() } }
    }
    @Published var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(sidebarVisible, forKey: "sidebarVisible")
            sidebarPeek = false
            trafficLightsRevealed = false
            updateTrafficLights()
        }
    }
    /// Floating sidebar shown while hovering the left edge with the sidebar hidden.
    @Published var sidebarPeek = false {
        didSet { updateTrafficLights() }
    }
    /// In Focus mode the traffic lights appear only while the pointer is in
    /// the window's top-left corner.
    @Published var trafficLightsRevealed = false {
        didSet { updateTrafficLights() }
    }
    @Published var spaceEditor: SpaceEditorRequest?
    @Published var importSheet: ImportRequest? {
        didSet { if importSheet != nil { releaseWebFocus() } }
    }
    @Published var renamingFolder: UInt64? {
        didSet { if renamingFolder != nil { releaseWebFocus() } }
    }
    @Published var dropIndicator: DropIndicator?
    @Published private(set) var contentFullscreen = false
    /// The window's corner radius, which the page's corners follow.
    @Published var windowRadius: CGFloat = 10

    let pager = PagerModel()
    let webContainer = WebContainerView()
    weak var window: NSWindow?
    /// Tab or folder being dragged inside the sidebar.
    private(set) var draggingItem: UInt64?

    private var views: [UInt64: MBWebView] = [:]
    private var navStates: [UInt64: NavState] = [:]
    private var refreshPending = false
    private var persistTimer: Timer?
    private var enteredFullscreenForContent = false

    init(core: BrowserCore) {
        self.core = core
        snapshot = core.snapshot()
        super.init()
        pager.pageCount = snapshot.spaces.count
        pager.position = CGFloat(activeSpaceIndex)
        pager.onSettle = { [weak self] index in
            guard let self, snapshot.spaces.indices.contains(index) else { return }
            activateSpace(snapshot.spaces[index].id)
        }
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

    func profileName(_ id: UInt64) -> String {
        snapshot.profiles.first { $0.id == id }?.name ?? ""
    }

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
    func refresh() {
        refreshPending = false
        if core.revision() != snapshot.revision {
            snapshot = core.snapshot()
            pager.pageCount = snapshot.spaces.count
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
        webContainer.show(visible.flatMap { views[$0] })
        nav = visible.flatMap { navStates[$0] } ?? NavState()
    }

    private func createView(for tab: TabInfo) {
        guard let profile = core.profileOfTab(tabId: tab.id) else { return }
        let url = tab.url.isEmpty ? "about:blank" : tab.url
        let view = MBWebView(url: url, profilePath: core.profileDir(profileId: profile), tabID: tab.id)
        view.delegate = self
        views[tab.id] = view
        webContainer.add(view)
        core.setLive(id: tab.id, live: true)
        setNeedsRefresh()
    }

    /// Destroys a tab's engine view, freeing its renderer.
    private func destroyView(_ id: UInt64) {
        guard let view = views.removeValue(forKey: id) else { return }
        navStates[id] = nil
        view.isHidden = true
        view.close()
    }

    private func destroyViews(_ ids: [UInt64]?) {
        ids?.forEach(destroyView)
    }

    /// The page keeps keyboard focus until something else takes first
    /// responder; SwiftUI focus alone does not move it.
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
        let spaceID = spaceID ?? activeSpace.id
        if spaceID != snapshot.activeSpace { core.setActiveSpace(id: spaceID) }
        core.activateTab(spaceId: spaceID, tabId: tabID)
        refresh()
        focusVisibleContent()
    }

    func submit(_ input: String, mode: CommandBarMode) {
        commandBar = nil
        let url = core.resolveInput(text: input)
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
        destroyViews(core.clearToday(spaceId: spaceID))
        refresh()
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
    func showDevTools() { visibleView?.showDevTools() }

    func copyVisibleURL() {
        guard let url = visibleTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    // MARK: - Spaces and profiles

    func activateSpace(_ id: UInt64) {
        guard id != snapshot.activeSpace else { return }
        core.setActiveSpace(id: id)
        refresh()
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
        withAnimation(Motion.quick) { refresh() }
    }

    func deleteFolder(_ id: UInt64) {
        destroyViews(core.deleteFolder(id: id))
        refresh()
    }

    // MARK: - Drag and drop

    func dragProvider(for id: UInt64, url: String?) -> NSItemProvider {
        draggingItem = id
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.sidebarItem.identifier, visibility: .ownProcess) { done in
            done(Data(String(id).utf8), nil)
            return nil
        }
        // Dragging a tab out of the browser hands its URL to the other app.
        if let url, let value = URL(string: url) {
            provider.registerObject(value as NSURL, visibility: .all)
        }
        return provider
    }

    func performDrop(_ info: DropInfo, target: DropTarget, index: Int) -> Bool {
        dropIndicator = nil
        // Rows that move under the pointer can report one more hover after
        // the drop; clear the indicator again once that has happened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.dropIndicator = nil }
        if info.hasItemsConforming(to: [.sidebarItem]), let id = draggingItem {
            draggingItem = nil
            move(id, to: target, index: index)
            return true
        }
        // A link dragged in from a page or another app opens as a new tab here.
        guard let provider = info.itemProviders(for: [.url]).first else { return false }
        _ = provider.loadObject(ofClass: NSURL.self) { object, _ in
            guard let url = (object as? URL)?.absoluteString else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let space = spaceID(of: target),
                      let id = core.openTab(spaceId: space, url: url, activate: false)
                else { return }
                move(id, to: target, index: index)
            }
        }
        return true
    }

    private func spaceID(of target: DropTarget) -> UInt64? {
        switch target {
        case .pinned(let spaceId, _), .today(let spaceId): spaceId
        case .favorites: activeSpace.id
        }
    }

    // MARK: - Process model

    var strictSiteIsolation: Bool { snapshot.strictSiteIsolation }

    func setStrictSiteIsolation(_ strict: Bool) {
        core.setStrictSiteIsolation(strict: strict)
        refresh()
    }

    // MARK: - Window chrome

    func toggleSidebar() {
        withAnimation(Motion.glide) { sidebarVisible.toggle() }
    }

    func updateTrafficLights() {
        let hidden = (!sidebarVisible && !sidebarPeek && !trafficLightsRevealed) || contentFullscreen
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    // MARK: - Memory

    /// Puts idle tabs to sleep and freezes idle hidden Today tabs according to
    /// the core's policy, then asks the remaining hidden tabs whether they
    /// play audio so they are kept awake.
    func sleepIdleTabs(pressure: MemoryPressure = .normal) {
        let sleepers = core.collectSleepers(pressure: pressure)
        sleepers.forEach(destroyView)
        let freezers = core.collectFreezers()
        for id in freezers { views[id]?.setFrozen(true) }
        if !sleepers.isEmpty || !freezers.isEmpty { setNeedsRefresh() }
        for (id, view) in views where id != visibleTabID {
            view.probeMedia()
        }
    }
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
            guard isCurrent(view), let window else { return }
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

    nonisolated func webViewDidClose(_ view: MBWebView) {
        MainActor.assumeIsolated {
            view.removeFromSuperview()
        }
    }
}
