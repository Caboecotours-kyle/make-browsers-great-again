import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let core: BrowserCore
    /// The first window's store. Agents, Settings and imports work through
    /// it, and its window hides rather than closes.
    private(set) lazy var primary = BrowserStore(core: core)
    /// The store of the window in front, which menu commands act on.
    var store: BrowserStore { BrowserStore.front ?? primary }
    /// The browser windows, the first window's first.
    private var windows: [BrowserWindow] = []
    private var sleepTimer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var scrollMonitor: Any?
    private var settings: SettingsWindowController?
    private var agentServer: AgentServer?
    /// Safari-style: the Develop menu is there only in Developer Mode.
    private var developMenu: NSMenuItem?

    init(core: BrowserCore) {
        self.core = core
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // MBGA_APPEARANCE=light|dark overrides the system appearance, for
        // screenshots of either look.
        switch ProcessInfo.processInfo.environment["MBGA_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        NSApp.mainMenu = buildMainMenu()
        // Before the first tab: a profile's extension workers start with its
        // first tab, and the host must be there to see them start.
        let extensions = ExtensionHost(core: core, devTools: BrowserDevTools(available: hasBrowserDevTools),
                                       dataDirectory: dataDirectory)
        ExtensionHost.shared = extensions
        extensions.onChange = { BrowserStore.extensionsChanged() }
        extensions.onOpenPopup = { [weak self] key in self?.store.runExtensionAction(key, from: nil) }
        _ = primary
        extensions.start(withExtensions: loadsExtensionHelper)
        agentServer = AgentServer(store: primary, path: dataDirectory.appendingPathComponent("agent.sock").path)
        updateDevelopMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(updateDevelopMenu),
                                               name: UserDefaults.didChangeNotification, object: nil)
        AdBlocking.install(core: core)
        MBEngine.setFormScript(FormScript.source)
        AdBlocking.updateLists(core: core, loaded: AdBlocking.loadCached(core: core))
        let window = makeWindow(for: primary)
        primary.becomeFront()
        _ = core.selectDefaultTab(spaceId: store.activeSpace.id)
        store.refresh()
        store.updateCleanupOffer()
        store.warmOtherSpaces()
        store.wakeAlwaysAwakeTabs()
        window.makeKeyAndOrderFront(nil)
        Updater.shared.start(store: primary)
        // MBGA_DEBUG_LITTLE_WINDOW pops the visible tab out at launch, for
        // screenshots of little windows.
        if ProcessInfo.processInfo.environment["MBGA_DEBUG_LITTLE_WINDOW"]?.isEmpty == false, let tab = store.visibleTabID {
            store.openInLittleWindow(tab)
        }
        // MBGA_DEBUG_EXTENSIONS=<url> opens the extensions window at launch,
        // on that page if it's a URL.
        if let page = ProcessInfo.processInfo.environment["MBGA_DEBUG_EXTENSIONS"] {
            store.showExtensions(url: page.contains(":") ? page : "")
        }
        // MBGA_DEBUG_LAYOUTS=<seconds> switches between Full and Focus that
        // often (every 3 s if not a number), for captures of the transition.
        if let every = ProcessInfo.processInfo.environment["MBGA_DEBUG_LAYOUTS"], !every.isEmpty {
            let timer = Timer(timeInterval: Double(every) ?? 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let store = self?.store else { return }
                    store.setLayout(store.layout == .full ? .focus : .full)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        // MBGA_DEBUG_COMMAND_CLOSE=<seconds> closes the command bar that
        // long after launch, for captures of it closing.
        if let after = ProcessInfo.processInfo.environment["MBGA_DEBUG_COMMAND_CLOSE"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + after) { [weak self] in self?.store.commandBar = nil }
        }
        // MBGA_DEBUG_PEEK=<seconds> shows the sidebar peeking over the page
        // in Focus mode, then not, that often, for captures of the slide.
        if let every = ProcessInfo.processInfo.environment["MBGA_DEBUG_PEEK"], !every.isEmpty {
            store.setLayout(.focus)
            let timer = Timer(timeInterval: Double(every) ?? 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let store = self?.store else { return }
                    store.sidebarPeek.toggle()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        // MBGA_DEBUG_DEVELOPER_DO=light,device:0,rotate,pick,screenshot runs
        // developer toolbar actions two seconds after launch, for captures.
        if let actions = ProcessInfo.processInfo.environment["MBGA_DEBUG_DEVELOPER_DO"], !actions.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let store = self?.store else { return }
                for action in actions.split(separator: ",") {
                    let parts = action.split(separator: ":")
                    switch parts[0] {
                    case "light", "dark": store.updateDev { $0.colorScheme = ColorSchemePreview(rawValue: String(parts[0]))! }
                    case "device": store.setDevice(DevicePreset.all[Int(parts[1]) ?? 0])
                    case "rotate": store.updateDev { $0.landscape.toggle() }
                    case "pick": store.togglePicking()
                    case "screenshot": store.screenshotPage()
                    case "source": store.viewSource()
                    case "devtools": store.openDevTools()
                    default: NSLog("unknown developer action %@", String(action))
                    }
                }
            }
        }
        // MBGA_DEBUG_SETTINGS=general|privacy|developer opens Settings at launch.
        if let raw = ProcessInfo.processInfo.environment["MBGA_DEBUG_SETTINGS"],
           let pane = SettingsPane.allCases.first(where: { $0.title.lowercased() == raw }) {
            showSettings(pane)
        }
        // MBGA_DEBUG_SIGNINS=1 brings the first browser's sign-ins into the
        // active space's profile at launch and logs how it went.
        if ProcessInfo.processInfo.environment["MBGA_DEBUG_SIGNINS"] != nil {
            let home = ProcessInfo.processInfo.environment["MBGA_IMPORT_HOME"] ?? NSHomeDirectory()
            Task { [store, core] in
                let sources = await Task.detached { core.detectBrowsers(home: home) }.value
                guard let source = sources.first(where: SignIns.available), let profile = source.profiles.first else {
                    NSLog("sign-ins: no browser found")
                    return
                }
                let outcome = await SignIns.bring(from: source, profileID: profile.id, into: store.activeSpace.profileId, store: store)
                NSLog("sign-ins: %@ (added %d, kept %d)", SignIns.describe(outcome, from: source.name), outcome.added, outcome.kept)
            }
        }
        // MBGA_DEBUG_PASSWORDS=1 does the same with the first browser's
        // saved passwords.
        if ProcessInfo.processInfo.environment["MBGA_DEBUG_PASSWORDS"] != nil {
            let home = ProcessInfo.processInfo.environment["MBGA_IMPORT_HOME"] ?? NSHomeDirectory()
            Task { [store, core] in
                let sources = await Task.detached { core.detectBrowsers(home: home) }.value
                guard let source = sources.first(where: PasswordImport.available),
                      let profile = source.profiles.first(where: { $0.passwords > 0 }) else {
                    NSLog("passwords: no browser found")
                    return
                }
                let outcome = await PasswordImport.bring(from: source, profileID: profile.id,
                                                         into: store.activeSpace.profileId, store: store)
                _ = core.persist()
                NSLog("passwords: %@", PasswordImport.describe(outcome, from: source.name))
            }
        }
        if core.needsOnboarding() {
            store.importSheet = ImportRequest(firstLaunch: true)
        } else if store.visibleTabID == nil || CommandBarView.debugPreset != nil {
            store.commandBar = .newTab
        }

        // Two-finger swipes in the sidebar switch spaces.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let store = self?.windows.first(where: { $0.window === event.window })?.store else { return event }
            return store.pager.handle(event) ? nil : event
        }

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.sleepIdleTabs() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            MainActor.assumeIsolated {
                self?.store.sleepIdleTabs(pressure: event.contains(.critical) ? .critical : .warning)
            }
        }
        source.resume()
        pressureSource = source
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        _ = core.persist()
        // The engine must close every browser before the process exits; the
        // message loop returns to main.swift once that is done.
        MBEngine.closeAllAndQuit()
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { show(windows.first?.window) }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { store.openFromSystem(url.absoluteString) }
        show(store.window)
    }

    private func show(_ window: NSWindow?) {
        window?.makeKeyAndOrderFront(nil)
        BrowserStore.windowsChanged()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Closing the first window keeps the browser running, like other Mac
        // apps; other windows close for good.
        guard sender === windows.first?.window else { return true }
        sender.orderOut(nil)
        BrowserStore.windowsChanged()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let index = windows.indices.dropFirst().first(where: { windows[$0].window === notification.object as? NSWindow })
        else { return }
        let closed = windows.remove(at: index)
        NotificationCenter.default.removeObserver(closed.frontObserver)
        closed.store.windowClosed()
    }

    /// Another window on the spaces, its own space and tab chosen apart from
    /// the others'. It starts on the front window's space, ready for an
    /// address.
    @objc func newWindow(_ sender: Any?) {
        let store = BrowserStore(core: core, newWindow: true)
        let window = makeWindow(for: store)
        store.refresh()
        window.makeKeyAndOrderFront(nil)
        store.commandBar = .newTab
    }

    private func makeWindow(for store: BrowserStore) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "MBGA"
        window.minSize = NSSize(width: 640, height: 420)
        // The hidden sidebar and Focus mode's traffic lights follow the pointer.
        window.acceptsMouseMovedEvents = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = RootView(store: store)
        if windows.isEmpty {
            if !window.setFrameUsingName("MainWindow") { window.center() }
            window.setFrameAutosaveName("MainWindow")
        } else if let front = self.store.window {
            // Down and right of the window in front, as other Mac apps do,
            // smaller if that would run off the screen.
            var frame = front.frame.offsetBy(dx: 24, dy: -24)
            if let area = (front.screen ?? NSScreen.main)?.visibleFrame {
                frame.size.width = min(frame.width, area.maxX - frame.minX)
                frame.origin.y = max(frame.minY, area.minY)
                frame.size.height = min(frame.height, front.frame.maxY - 24 - frame.minY)
            }
            window.setFrame(frame, display: false)
        }
        store.window = window
        store.windowRadius = window.systemCornerRadius
        store.openSettings = { [weak self] pane in self?.showSettings(pane) }
        store.updateTrafficLights()
        let frontObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: window, queue: .main
        ) { [weak store] _ in
            MainActor.assumeIsolated { store?.becomeFront() }
        }
        windows.append(BrowserWindow(store: store, window: window, sidebarReveal: SidebarReveal(store: store),
                                     frontObserver: frontObserver))
        return window
    }

    func showSettings(_ pane: SettingsPane?) {
        let settings = settings ?? SettingsWindowController(store: primary)
        self.settings = settings
        settings.show(pane)
    }

    @objc private func updateDevelopMenu() {
        guard let main = NSApp.mainMenu, let develop = developMenu else { return }
        let shown = develop.menu === main
        if DeveloperSettings.enabled, !shown {
            // After View, as in Safari.
            let view = main.items.firstIndex { $0.title == "View" } ?? 2
            main.insertItem(develop, at: view + 1)
        } else if !DeveloperSettings.enabled, shown {
            main.removeItem(develop)
        }
    }

    // MARK: - Menu actions

    @objc func openSettings(_ sender: Any?) { showSettings(nil) }
    @objc func reloadIgnoringCache(_ sender: Any?) { if !MBEngine.performChromeCommand(.reloadIgnoringCache) { store.hardReload() } }
    @objc func toggleDeveloperToolbar(_ sender: Any?) { store.toggleDeveloperToolbar() }
    @objc func pickElement(_ sender: Any?) { store.togglePicking() }
    @objc func setColorScheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let scheme = ColorSchemePreview(rawValue: raw) else { return }
        store.updateDev { $0.colorScheme = scheme }
    }
    @objc func setDevice(_ sender: NSMenuItem) {
        store.setDevice(DevicePreset.all.indices.contains(sender.tag) ? DevicePreset.all[sender.tag] : nil)
    }
    @objc func rotateDevice(_ sender: Any?) { store.updateDev { $0.landscape.toggle() } }
    @objc func setNetwork(_ sender: NSMenuItem) { store.updateDev { $0.network = NetworkPreset.allCases[sender.tag] } }
    @objc func toggleCache(_ sender: Any?) { store.updateDev { $0.cacheDisabled.toggle() } }
    @objc func toggleScripts(_ sender: Any?) { store.toggleScripts() }
    @objc func toggleReducedMotion(_ sender: Any?) { store.updateDev { $0.reducedMotion.toggle() } }
    @objc func screenshotPage(_ sender: Any?) { store.screenshotPage() }
    @objc func clearSiteData(_ sender: Any?) { store.clearSiteData() }
    @objc func viewSource(_ sender: Any?) { store.viewSource() }
    @objc func openInBrowser(_ sender: NSMenuItem) {
        if let app = sender.representedObject as? URL { store.openVisible(in: app) }
    }

    // In the extensions window (Chrome's own), tab commands are Chrome's.
    @objc func newTab(_ sender: Any?) { if !MBEngine.performChromeCommand(.newTab) { store.commandBar = .newTab } }
    @objc func openLocation(_ sender: Any?) { if !MBEngine.performChromeCommand(.focusLocation) { store.commandBar = .editCurrent } }
    @objc func closeTab(_ sender: Any?) {
        if MBEngine.performChromeCommand(.closeTab) { return }
        if let key = NSApp.keyWindow, let browser = windows.first(where: { $0.window === key }) {
            browser.store.closeVisibleTab()
        } else {
            NSApp.keyWindow?.performClose(sender)
        }
    }
    /// Closes the window even when its traffic lights are hidden (Focus
    /// mode), which `performClose` won't.
    @objc func closeWindow(_ sender: Any?) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        if window.delegate?.windowShouldClose?(window) ?? true { window.close() }
    }
    @objc func newSpace(_ sender: Any?) { store.spaceEditor = SpaceEditorRequest(spaceID: nil) }
    @objc func importFromBrowser(_ sender: Any?) { store.importSheet = ImportRequest(firstLaunch: false) }
    @objc func importSignIns(_ sender: Any?) { showSettings(.privacy) }
    @objc func editSpace(_ sender: Any?) { store.spaceEditor = SpaceEditorRequest(spaceID: store.activeSpace.id) }
    @objc func newFolder(_ sender: Any?) { store.newFolder() }
    @objc func clearToday(_ sender: Any?) { store.clearToday(store.activeSpace.id) }
    @objc func toggleSidebar(_ sender: Any?) { store.toggleSidebar() }
    @objc func reload(_ sender: Any?) { if !MBEngine.performChromeCommand(.reload) { store.reload() } }
    @objc func zoomIn(_ sender: Any?) { if !MBEngine.performChromeCommand(.zoomIn) { store.zoomIn() } }
    @objc func zoomOut(_ sender: Any?) { if !MBEngine.performChromeCommand(.zoomOut) { store.zoomOut() } }
    @objc func resetZoom(_ sender: Any?) { if !MBEngine.performChromeCommand(.actualSize) { store.resetZoom() } }
    @objc func developerTools(_ sender: Any?) { store.showDevTools() }
    @objc func javaScriptConsole(_ sender: Any?) { store.openDevTools() }
    @objc func chromeDevTools(_ sender: Any?) { store.openChromeDevTools() }
    @objc func goBack(_ sender: Any?) { if !MBEngine.performChromeCommand(.back) { store.goBack() } }
    @objc func goForward(_ sender: Any?) { if !MBEngine.performChromeCommand(.forward) { store.goForward() } }
    @objc func copyURL(_ sender: Any?) { store.copyVisibleURL() }
    @objc func togglePin(_ sender: Any?) { store.togglePinVisibleTab() }
    @objc func nextTab(_ sender: Any?) { store.selectAdjacentTab(1) }
    @objc func previousTab(_ sender: Any?) { store.selectAdjacentTab(-1) }
    @objc func nextSpace(_ sender: Any?) { store.activateAdjacentSpace(1) }
    @objc func previousSpace(_ sender: Any?) { store.activateAdjacentSpace(-1) }
    @objc func selectTab(_ sender: NSMenuItem) { store.selectTab(at: sender.tag) }
    @objc func reopenClosedTab(_ sender: Any?) { if !MBEngine.performChromeCommand(.reopenTab) { store.undoClose() } }
    @objc func toggleBlockAds(_ sender: Any?) { store.setBlockAds(!store.blockAds) }
    @objc func editFilters(_ sender: Any?) { NSWorkspace.shared.open(URL(fileURLWithPath: core.userFiltersPath())) }
    @objc func showExtensions(_ sender: Any?) { store.showExtensions() }
    @objc func checkForUpdates(_ sender: Any?) { Updater.shared.check(userInitiated: true) }
    @objc func restartToUpdate(_ sender: Any?) { Updater.shared.restartToUpdate() }
    /// Edit ▸ Undo reaches the app only when no page or text field took it;
    /// then it undoes the last closed tab, cleared list or deleted folder.
    @objc func undo(_ sender: Any?) { store.undoClose() }
    @objc func setArchiveInterval(_ sender: NSMenuItem) { store.setArchiveAfterHours(UInt32(sender.tag)) }
    @objc func setTintStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        UserDefaults.standard.set(style, forKey: TintStyle.defaultsKey)
    }

    @objc func setLayout(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let layout = SidebarLayout(rawValue: raw) { store.setLayout(layout) }
    }

    @objc func toggleMatchPage(_ sender: Any?) {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: TintStyle.matchPageKey), forKey: TintStyle.matchPageKey)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)), #selector(reopenClosedTab(_:)):
            return store.canReopen
        case #selector(setArchiveInterval(_:)):
            item.state = store.archiveAfterHours == UInt32(item.tag) ? .on : .off
        case #selector(setTintStyle(_:)):
            let current = UserDefaults.standard.string(forKey: TintStyle.defaultsKey) ?? TintStyle.calm.rawValue
            item.state = current == item.representedObject as? String ? .on : .off
        case #selector(toggleSidebar(_:)):
            item.state = store.layout == .focus ? .on : .off
        case #selector(setLayout(_:)):
            item.state = store.layout.rawValue == item.representedObject as? String ? .on : .off
        case #selector(toggleMatchPage(_:)):
            item.state = UserDefaults.standard.bool(forKey: TintStyle.matchPageKey) ? .on : .off
        case #selector(toggleBlockAds(_:)):
            item.state = store.blockAds ? .on : .off
        case #selector(restartToUpdate(_:)):
            guard let version = Updater.shared.readyVersion else {
                item.isHidden = true
                return false
            }
            item.isHidden = false
            item.title = "Restart to Update to \(version)"
        case #selector(toggleDeveloperToolbar(_:)):
            item.title = store.developerToolbarShown ? "Hide Developer Toolbar" : "Show Developer Toolbar"
        case #selector(pickElement(_:)):
            item.state = store.visibleDevState.picking ? .on : .off
        case #selector(setColorScheme(_:)):
            item.state = store.visibleDevState.colorScheme.rawValue == item.representedObject as? String ? .on : .off
        case #selector(setDevice(_:)):
            let device = store.visibleDevState.device
            item.state = (DevicePreset.all.indices.contains(item.tag) ? DevicePreset.all[item.tag] : nil) == device ? .on : .off
        case #selector(rotateDevice(_:)):
            item.state = store.visibleDevState.landscape ? .on : .off
            return store.visibleDevState.device != nil
        case #selector(setNetwork(_:)):
            item.state = NetworkPreset.allCases[item.tag] == store.visibleDevState.network ? .on : .off
        case #selector(toggleCache(_:)):
            item.state = store.visibleDevState.cacheDisabled ? .on : .off
        case #selector(toggleScripts(_:)):
            item.state = store.visibleDevState.scriptsDisabled ? .on : .off
        case #selector(toggleReducedMotion(_:)):
            item.state = store.visibleDevState.reducedMotion ? .on : .off
        default:
            break
        }
        return true
    }
    @objc func selectSpace(_ sender: NSMenuItem) { store.activateSpace(at: sender.tag) }

    @objc func toggleStrictSiteIsolation(_ sender: NSMenuItem) {
        let strict = !store.strictSiteIsolation
        store.setStrictSiteIsolation(strict)
        sender.state = strict ? .on : .off
        let alert = NSAlert()
        alert.messageText = strict ? "Strict site isolation turns on at next launch"
            : "Strict site isolation turns off at next launch"
        alert.informativeText = strict
            ? "Every site will get its own renderer process, as in desktop Chrome. This is the strongest protection against one site reading another's data, and uses about 30% more memory."
            : "Sites will share a few renderer processes, as in Chrome on Android. Sign-in pages and sites that ask for isolation keep their own process. This saves about a fifth of memory."
        alert.runModal()
    }

    // MARK: - Menu

    private func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        main.addSubmenu("MBGA") { m in
            m.addItem(withTitle: "About MBGA", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
            m.item("Check for Updates…", #selector(checkForUpdates(_:)), "", [], target: self)
            m.item("Restart to Update", #selector(restartToUpdate(_:)), "", [], target: self).isHidden = true
            m.addItem(.separator())
            m.item("Settings…", #selector(openSettings(_:)), ",", target: self)
            m.addItem(.separator())
            m.item("Block Ads and Trackers", #selector(toggleBlockAds(_:)), "", [], target: self)
            m.item("Edit My Filters…", #selector(editFilters(_:)), "", [], target: self)
            m.item("Extensions…", #selector(showExtensions(_:)), "", [], target: self)
            let isolation = m.item("Strict Site Isolation", #selector(toggleStrictSiteIsolation(_:)), "", [], target: self)
            isolation.state = store.strictSiteIsolation ? .on : .off
            m.addItem(.separator())
            m.addItem(withTitle: "Hide MBGA", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
            m.item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: nil)
            m.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
            m.addItem(.separator())
            m.addItem(withTitle: "Quit MBGA", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }

        main.addSubmenu("File") { m in
            m.item("New Tab", #selector(newTab(_:)), "t", target: self)
            m.item("New Window", #selector(newWindow(_:)), "n", target: self)
            m.item("Open Location…", #selector(openLocation(_:)), "l", target: self)
            m.item("New Folder", #selector(newFolder(_:)), "n", [.command, .option], target: self)
            m.item("New Space…", #selector(newSpace(_:)), "n", [.command, .shift], target: self)
            m.addItem(.separator())
            m.item("Import from Another Browser…", #selector(importFromBrowser(_:)), "", target: self)
            m.item("Import Sign-ins…", #selector(importSignIns(_:)), "", target: self)
            m.addItem(.separator())
            m.item("Close Tab", #selector(closeTab(_:)), "w", target: self)
            m.item("Close Window", #selector(closeWindow(_:)), "w", [.command, .shift], target: self)
            m.item("Reopen Closed Tab", #selector(reopenClosedTab(_:)), "t", [.command, .shift], target: self)
            m.item("Clear Today Tabs", #selector(clearToday(_:)), "k", [.command, .shift], target: self)
        }

        main.addSubmenu("Edit") { m in
            m.item("Undo", #selector(undo(_:)), "z", target: nil)
            m.item("Redo", Selector(("redo:")), "z", [.command, .shift], target: nil)
            m.addItem(.separator())
            m.item("Cut", #selector(NSText.cut(_:)), "x", target: nil)
            m.item("Copy", #selector(NSText.copy(_:)), "c", target: nil)
            m.item("Paste", #selector(NSText.paste(_:)), "v", target: nil)
            m.item("Select All", #selector(NSText.selectAll(_:)), "a", target: nil)
            m.addItem(.separator())
            m.item("Copy URL", #selector(copyURL(_:)), "c", [.command, .shift], target: self)
        }

        main.addSubmenu("View") { m in
            m.item("Full Sidebar", #selector(setLayout(_:)), "", target: self).representedObject = SidebarLayout.full.rawValue
            m.item("Compact Sidebar", #selector(setLayout(_:)), "", target: self).representedObject = SidebarLayout.compact.rawValue
            m.item("Focus Mode", #selector(toggleSidebar(_:)), "s", target: self)
            m.addSubmenu("Sidebar Colour") { colours in
                for style in TintStyle.allCases {
                    colours.item(style.title, #selector(setTintStyle(_:)), "", target: self).representedObject = style.rawValue
                }
                colours.addItem(.separator())
                colours.item("Match Page Colour", #selector(toggleMatchPage(_:)), "", target: self)
            }
            m.addItem(.separator())
            m.item("Reload Page", #selector(reload(_:)), "r", target: self)
            m.item("Reload Without Cache", #selector(reloadIgnoringCache(_:)), "r", [.command, .shift], target: self)
            m.item("Zoom In", #selector(zoomIn(_:)), "=", target: self)
            m.item("Zoom Out", #selector(zoomOut(_:)), "-", target: self)
            m.item("Actual Size", #selector(resetZoom(_:)), "0", target: self)
            m.addItem(.separator())
            m.item("Developer Tools", #selector(developerTools(_:)), "i", [.command, .option], target: self)
            m.item("JavaScript Console", #selector(javaScriptConsole(_:)), "j", [.command, .option], target: self)
            m.item("Chrome DevTools", #selector(chromeDevTools(_:)), "i", [.command, .option, .shift], target: self)
            m.addItem(.separator())
            m.item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control], target: nil)
        }

        main.addSubmenu("Develop") { m in
            m.item("Show Developer Toolbar", #selector(toggleDeveloperToolbar(_:)), "d", [.command, .shift], target: self)
            m.addItem(.separator())
            m.item("Pick an Element", #selector(pickElement(_:)), "c", [.command, .option], target: self)
            m.item("View Page Source", #selector(viewSource(_:)), "u", [.command, .option], target: self)
            m.item("Screenshot the Whole Page", #selector(screenshotPage(_:)), "", target: self)
            m.addItem(.separator())
            m.addSubmenu("Colour Scheme") { schemes in
                for scheme in [ColorSchemePreview.system, .dark, .light] {
                    schemes.item(scheme.title, #selector(setColorScheme(_:)), "", target: self).representedObject = scheme.rawValue
                }
            }
            m.addSubmenu("Device Preview") { devices in
                devices.item("Off", #selector(setDevice(_:)), "", target: self).tag = -1
                devices.addItem(.separator())
                for (i, preset) in DevicePreset.all.enumerated() {
                    devices.item(preset.name, #selector(setDevice(_:)), "", target: self).tag = i
                }
                devices.addItem(.separator())
                devices.item("Landscape", #selector(rotateDevice(_:)), "", target: self)
            }
            m.addSubmenu("Network") { network in
                for (i, preset) in NetworkPreset.allCases.enumerated() {
                    network.item(preset.title, #selector(setNetwork(_:)), "", target: self).tag = i
                }
            }
            m.item("Disable Cache", #selector(toggleCache(_:)), "", target: self)
            m.item("Disable JavaScript", #selector(toggleScripts(_:)), "", target: self)
            m.item("Prefer Reduced Motion", #selector(toggleReducedMotion(_:)), "", target: self)
            m.addItem(.separator())
            m.item("Clear Site Data and Reload", #selector(clearSiteData(_:)), "", target: self)
            m.addSubmenu("Open Page In") { browsers in
                for browser in DevBrowsers.installed {
                    let item = browsers.item(browser.name, #selector(openInBrowser(_:)), "", target: self)
                    item.representedObject = browser.url
                    item.image = browser.icon
                }
            }
        }
        developMenu = main.items.last
        main.removeItem(developMenu!)

        main.addSubmenu("History") { m in
            m.item("Back", #selector(goBack(_:)), "[", target: self)
            m.item("Forward", #selector(goForward(_:)), "]", target: self)
        }

        main.addSubmenu("Tabs") { m in
            m.item("Pin/Unpin Tab", #selector(togglePin(_:)), "d", target: self)
            m.addSubmenu("Archive Unused Today Tabs") { archive in
                for (title, hours) in [("Never", 0), ("After 12 Hours", 12), ("After a Day", 24), ("After a Week", 168)] {
                    archive.item(title, #selector(setArchiveInterval(_:)), "", target: self).tag = hours
                }
            }
            m.addItem(.separator())
            m.item("Next Tab", #selector(nextTab(_:)), "\t", [.control], target: self)
            m.item("Previous Tab", #selector(previousTab(_:)), "\t", [.control, .shift], target: self)
            m.item("Next Tab", #selector(nextTab(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option], target: self)
            m.item("Previous Tab", #selector(previousTab(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option], target: self)
            m.addItem(.separator())
            for i in 0..<9 {
                let item = m.item(i == 8 ? "Last Tab" : "Tab \(i + 1)", #selector(selectTab(_:)), "\(i + 1)", target: self)
                item.tag = i
            }
        }

        main.addSubmenu("Spaces") { m in
            m.item("Edit Space…", #selector(editSpace(_:)), "", target: self)
            m.addItem(.separator())
            m.item("Next Space", #selector(nextSpace(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option], target: self)
            m.item("Previous Space", #selector(previousSpace(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option], target: self)
            m.addItem(.separator())
            for i in 0..<9 {
                let item = m.item("Space \(i + 1)", #selector(selectSpace(_:)), "\(i + 1)", [.control], target: self)
                item.tag = i
            }
        }

        let windowMenu = main.addSubmenu("Window") { m in
            m.item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", target: nil)
            m.item("Zoom", #selector(NSWindow.performZoom(_:)), "", target: nil)
            m.addItem(.separator())
            m.item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), "", target: nil)
        }
        NSApp.windowsMenu = windowMenu
        return main
    }
}

/// A browser window: its store, the window, and what follows the pointer
/// in it.
@MainActor
private struct BrowserWindow {
    let store: BrowserStore
    let window: NSWindow
    let sidebarReveal: SidebarReveal
    /// Brings the store forward as the window becomes main.
    let frontObserver: NSObjectProtocol
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
        let menu = NSMenu(title: title)
        build(menu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        addItem(item)
        return menu
    }

    @discardableResult
    func item(
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject?
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        addItem(item)
        return item
    }
}
