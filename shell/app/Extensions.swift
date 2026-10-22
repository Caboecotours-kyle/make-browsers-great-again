import AppKit

/// Chrome extensions in MBGA's tabs. Chrome's extension system runs them
/// (content scripts, network rules, service workers) but doesn't know MBGA's
/// tabs are tabs: they're Alloy-style browsers, outside any Chrome window.
/// This host fills the gap. Every extension service worker gets
/// ExtensionShim before its own script (paused at start over the browser
/// DevTools connection, then let go, so it still sleeps when idle), and so
/// does every extension page MBGA shows. The shim asks the host about MBGA's
/// tabs and windows through the engine's bridge, and the host sends it
/// MBGA's tab and window events, waking the worker when it sleeps.
@MainActor
final class ExtensionHost {
    /// A profile's copy of an extension: events and state are per profile.
    struct Key: Hashable, Codable {
        let profile: String
        let extensionID: String
    }

    /// What an extension's toolbar button shows, set by its action API calls
    /// (Chrome keeps its own copy for the extensions window).
    struct ActionState {
        var badgeText: String?
        var badgeColor: [Double]?
        var badgeTextColor: [Double]?
        var title: String?
        var icon: String?
        var popup: String?
        var enabled: Bool?
    }

    struct MenuItem: Codable {
        var id: String
        var props: [String: JSONValue]
    }

    /// The window id MBGA's main window has in extension APIs; Chrome's own
    /// windows and tabs share a counter that starts far from it.
    static let mainWindowID = 1_000_000_000
    /// MBGA's helper (shell/resources/extension), loaded in every profile.
    static let helperID = "ngnchdgcmeaekolgcekjmpncoaiepoeb"

    private unowned let store: BrowserStore
    private let devTools: BrowserDevTools
    private let token = (0..<4).map { _ in String(UInt32.random(in: 0...UInt32.max), radix: 16) }.joined()
    private let savePath: URL

    /// Extension workers running now: DevTools target id → extension id.
    private var workers: [String: String] = [:]
    /// Which profile each running worker belongs to, as it reported its
    /// listeners.
    private var workerProfiles: [String: String] = [:]
    /// Workers paused at their first script, by DevTools session.
    private var pausing: [String: String] = [:]
    /// Targets the host is attaching to itself, and how many times.
    private var attaching: [String: Int] = [:]
    /// Events each extension listens to. Kept across launches, so a worker
    /// that hasn't run yet still gets woken for its events.
    private var listening: [Key: Set<String>] = [:]
    private(set) var menus: [Key: [MenuItem]] = [:]
    /// Events waiting for a worker that's being woken.
    private var queued: [Key: [[Any]]] = [:]
    private var waking: Set<Key> = []
    private(set) var actions: [Key: ActionState] = [:]
    private(set) var tabActions: [Key: [Int: ActionState]] = [:]
    /// Popups MBGA shows (see ExtensionPopup).
    private var popupViews = NSHashTable<MBWebView>.weakObjects()
    /// Extension tab ids (Chrome's session ids, which CEF doesn't expose)
    /// of MBGA's browsers, by browser id, and the DevTools target ids they
    /// were matched by.
    private var tabIDs: [Int32: Int] = [:]
    private var targetIDs: [Int32: String] = [:]
    private var resolving: [() -> Void]?
    private var resolveRound = 0
    /// When each browser was last looked for and how often, so one that
    /// can't be found (a frozen page doesn't answer) doesn't hold up every
    /// request: a second later at the soonest, three times at most.
    private var lookedFor: [Int32: (when: Date, times: Int)] = [:]
    /// Asks waiting for the helper's worker to start.
    private var helperWaiters: [(String?) -> Void] = []
    /// Each profile's tabs, windows and focus as last reported, to tell
    /// extensions what changed.
    private var reported: [String: Report] = [:]
    private var syncPending = false
    private var canonical: [String: String] = [:]
    /// Called when a toolbar button or menu changes.
    var onChange: (() -> Void)?
    var onOpenPopup: ((Key) -> Void)?

    /// MBGA_DEBUG_EXTENSION_HOST=1 logs what the host does.
    private static let debug = ProcessInfo.processInfo.environment["MBGA_DEBUG_EXTENSION_HOST"]?.isEmpty == false
    private func log(_ message: @autoclosure () -> String) {
        if Self.debug { NSLog("extensions: %@", message()) }
    }

    private struct Report {
        var tabs: [Int: [String: Any]]
        var active: [Int: Int]
        var focused: Int
    }

    private struct Saved: Codable {
        var listening: [Key: Set<String>]
        var menus: [Key: [MenuItem]]
    }

    init(store: BrowserStore, devTools: BrowserDevTools, dataDirectory: URL) {
        self.store = store
        self.devTools = devTools
        savePath = dataDirectory.appendingPathComponent("extensions.json")
        if let data = try? Data(contentsOf: savePath), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            listening = saved.listening
            menus = saved.menus
        }
    }

    func start() {
        let token = token
        MBEngine.setExtensionBridge({ [weak self] profile, extensionID, browserID, path, body, reply in
            MainActor.assumeIsolated {
                guard let self else { return reply("null") }
                self.handle(profile: profile, extensionID: extensionID, browserID: browserID,
                            path: path, body: body, reply: reply)
            }
        }, pageScript: { _ in ExtensionShim.source(token: token, instance: "page") })
        guard devTools.available else { return prepareProfiles() }
        devTools.onEvent = { [weak self] method, params, session in self?.devToolsEvent(method, params, session) }
        devTools.send("Target.setDiscoverTargets", ["discover": true, "filter": [["type": "service_worker"]]])
        // Workers that start before this takes effect miss the start of the
        // shim: wait for it (a few milliseconds). Other profiles' extensions
        // start with their first tab, still to come; the last used profile's
        // started with the engine (see the late shim below).
        var watching = false
        devTools.send("Target.setAutoAttach", [
            "autoAttach": true, "waitForDebuggerOnStart": true, "flatten": true,
            "filter": [["type": "service_worker"], ["exclude": true]],
        ]) { _, _ in watching = true }
        let deadline = Date(timeIntervalSinceNow: 0.5)
        while !watching, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        prepareProfiles()
        store.observe(self) { [weak self] change in
            if change == .snapshot { self?.setNeedsSync() }
        }
        // Extensions' shortcuts, before the page sees the keys (Chrome's
        // window handles its own).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = event.window, !MBEngine.isExtensionsWindow(window) else { return event }
            return handleShortcut(event) ? nil : event
        }
        // Back from the extensions window, things may have changed there.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow, MBEngine.isExtensionsWindow(window) { self?.refreshInstalled() }
            }
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsSync() }
            }
        }
    }

    /// Extensions' requests reach the bridge once their profile has its
    /// context: set them all up rather than waiting for their first tab.
    private func prepareProfiles() {
        for profile in store.snapshot.profiles {
            MBEngine.prepareProfilePath(store.core.profileDir(profileId: profile.id))
        }
    }

    // MARK: - Workers

    private func devToolsEvent(_ method: String, _ params: [String: Any], _ session: String?) {
        switch method {
        case "Target.attachedToTarget":
            guard let sessionID = params["sessionId"] as? String,
                  let info = params["targetInfo"] as? [String: Any] else { return }
            let url = info["url"] as? String ?? ""
            let waiting = params["waitingForDebugger"] as? Bool ?? false
            let target = info["targetId"] as? String ?? ""
            // Our own attachments (to send events or ask the helper).
            if (attaching[target] ?? 0) > 0 { return }
            if url.hasPrefix("chrome-extension://"), waiting {
                // Paused before its first script, where the shim goes.
                pausing[sessionID] = target
                devTools.send("Debugger.enable", session: sessionID)
                devTools.send("Debugger.setInstrumentationBreakpoint", ["instrumentation": "beforeScriptExecution"], session: sessionID)
                devTools.send("Runtime.runIfWaitingForDebugger", session: sessionID)
            } else if url.hasPrefix("chrome-extension://") {
                // Already running when MBGA connected (Chrome starts the
                // last used profile's extensions with the engine): the shim
                // comes late, after the listeners it should know about.
                devTools.send("Runtime.evaluate", ["expression": ExtensionShim.source(token: token, instance: target)], session: sessionID)
                devTools.send("Target.detachFromTarget", ["sessionId": sessionID])
                // Stopped once its startup work is done, it starts again
                // at its next event, shim first.
                if !url.hasPrefix("chrome-extension://\(Self.helperID)/") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        guard let self, workers[target] != nil else { return }
                        log("restarting \(url)")
                        devTools.send("Target.closeTarget", ["targetId": target])
                    }
                }
            } else {
                // The web's own service workers: let go at once.
                if waiting { devTools.send("Runtime.runIfWaitingForDebugger", session: sessionID) }
                devTools.send("Target.detachFromTarget", ["sessionId": sessionID])
            }
        case "Debugger.paused":
            guard let session, let target = pausing.removeValue(forKey: session) else { return }
            log("injecting into \(target)")
            devTools.send("Runtime.evaluate", ["expression": ExtensionShim.source(token: token, instance: target)], session: session)
            devTools.send("Debugger.disable", session: session)
            devTools.send("Debugger.resume", session: session)
            // Attached, a worker would never be stopped when idle.
            devTools.send("Target.detachFromTarget", ["sessionId": session])
        case "Target.targetCreated", "Target.targetInfoChanged":
            guard let info = params["targetInfo"] as? [String: Any], info["type"] as? String == "service_worker",
                  let target = info["targetId"] as? String, let url = URL(string: info["url"] as? String ?? ""),
                  url.scheme == "chrome-extension", let id = url.host else { return }
            if workers[target] == nil, !installed.values.contains(where: { $0.contains { $0.id == id } }), id != Self.helperID {
                // Just installed (or enabled).
                refreshInstalled()
            }
            workers[target] = id
            if id == Self.helperID, !helperWaiters.isEmpty {
                let waiters = helperWaiters
                helperWaiters = []
                waiters.forEach { $0(target) }
            }
        case "Target.targetDestroyed":
            guard let target = params["targetId"] as? String else { return }
            workers[target] = nil
            workerProfiles[target] = nil
        default:
            break
        }
    }

    /// Sends events to an extension's worker, waking it if it sleeps.
    private func dispatch(_ events: [[Any]], to key: Key) {
        guard !events.isEmpty else { return }
        let running = workers.first { $0.value == key.extensionID && workerProfiles[$0.key] == key.profile }?.key
        guard let target = running, !waking.contains(key) else {
            queued[key, default: []].append(contentsOf: events)
            wake(key)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: events),
              let json = String(data: data, encoding: .utf8) else { return }
        attach(target) { [weak self] session in
            guard let self else { return }
            guard let session else {
                // It stopped meanwhile.
                queued[key, default: []].append(contentsOf: events)
                wake(key)
                return
            }
            devTools.send("Runtime.evaluate", ["expression": "globalThis.__mbga && __mbga.dispatch(\(json))"], session: session)
            devTools.send("Target.detachFromTarget", ["sessionId": session])
        }
    }

    /// Starts a sleeping worker; as it reports its listeners, it gets the
    /// queued events.
    private func wake(_ key: Key) {
        guard !waking.contains(key) else { return }
        guard let view = liveView(in: key.profile), let page = targetIDs[view.browserIdentifier] else {
            queued[key] = nil
            return
        }
        waking.insert(key)
        startWorker(key.extensionID, from: page)
        // Don't keep events forever for a worker that never reports.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, waking.remove(key) != nil else { return }
            queued[key] = nil
        }
    }

    /// Attaches to a target for a few commands; `body` gets the session, or
    /// nil if the target is gone, and must detach when done.
    private func attach(_ target: String, _ body: @escaping (String?) -> Void) {
        attaching[target, default: 0] += 1
        devTools.send("Target.attachToTarget", ["targetId": target, "flatten": true]) { [weak self] result, _ in
            guard let self else { return }
            attaching[target, default: 1] -= 1
            if attaching[target] == 0 { attaching[target] = nil }
            body(result?["sessionId"] as? String)
        }
    }

    /// Starts an extension's service worker, through a page of the same
    /// profile (DevTools starts workers from a page's session).
    private func startWorker(_ extensionID: String, from page: String) {
        attach(page) { [weak self] session in
            guard let self, let session else { return }
            devTools.send("ServiceWorker.enable", session: session)
            devTools.send("ServiceWorker.startWorker", ["scopeURL": "chrome-extension://\(extensionID)/"], session: session) { [weak self] _, _ in
                self?.devTools.send("Target.detachFromTarget", ["sessionId": session])
            }
        }
    }

    // MARK: - Bridge

    private func handle(profile rawProfile: String, extensionID: String, browserID: Int32, path: String,
                        body: String, reply: @escaping (String) -> Void) {
        let profile = canonicalPath(rawProfile)
        let parts = path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0] == token else { return reply("null") }
        let args = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        resolveTabIDs { [weak self] in
            self?.answer(profile: profile, extensionID: extensionID, browserID: browserID,
                         method: parts[1], args: args, reply: reply)
        }
    }

    private func answer(profile: String, extensionID: String, browserID: Int32, method: String,
                        args: [String: Any], reply: @escaping (String) -> Void) {
        let key = Key(profile: profile, extensionID: extensionID)
        log("\(extensionID) \(browserID == 0 ? "worker" : "page \(browserID)") → \(method) \(args)")
        let answer: (Any?) -> Void = { [weak self] value in
            guard let self else { return reply("null") }
            let object: [String: Any] = ["value": value ?? NSNull(), "state": state(profile: profile, requester: browserID)]
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("null".utf8)
            reply(String(decoding: data, as: UTF8.self))
        }
        switch method {
        case "state":
            answer(nil)
        case "listeners":
            // A worker's listeners are added as it starts: the moment to
            // hand it the events it was woken for.
            guard browserID == 0 else { return answer(nil) }
            if let instance = args["instance"] as? String { workerProfiles[instance] = profile }
            setListeners(args["listeners"], for: key)
            waking.remove(key)
            answer(queued.removeValue(forKey: key))
        case "tabs.create":
            openTab(args.merging(["extension": extensionID]) { $1 }, profile: profile) { [weak self] tab in
                answer(tab.flatMap { self?.tabObject(for: $0, profile: profile) })
            }
        case "tabs.update":
            if let id = (args["id"] as? NSNumber)?.intValue, let tab = tab(extensionTabID: id) {
                if let pinned = args["pinned"] as? Bool, pinned != isPinned(tab) { store.togglePin(tab, in: space(of: tab)) }
                if args["active"] as? Bool == true { store.select(tab, in: space(of: tab)?.id) }
            }
            answer(nil)
        case "tabs.remove":
            for id in args["ids"] as? [NSNumber] ?? [] {
                if let tab = tab(extensionTabID: id.intValue) { store.close(tab) }
            }
            answer(nil)
        case "tabs.capture":
            capture(args) { answer($0) }
        case "windows.focus":
            NSApp.activate()
            store.window?.makeKeyAndOrderFront(nil)
            answer(nil)
        case "runtime.openOptionsPage":
            openOptions(key)
            answer(nil)
        case "action":
            updateAction(key, what: args["what"] as? String ?? "", details: args["details"] as? [String: Any] ?? [:])
            answer(nil)
        case "action.openPopup":
            onOpenPopup?(key)
            answer(nil)
        case "menus":
            updateMenus(key, args)
            answer(nil)
        default:
            answer(nil)
        }
    }

    private func setListeners(_ value: Any?, for key: Key) {
        let events = Set(value as? [String] ?? [])
        guard listening[key] != events else { return }
        listening[key] = events.isEmpty ? nil : events
        save()
    }

    private func save() {
        let saved = Saved(listening: listening, menus: menus)
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: savePath, options: .atomic) }
    }

    // MARK: - Installed extensions

    private var installed: [String: [InstalledExtension]] = [:]

    /// The profile's extensions, as Chrome last recorded them.
    func extensions(in profile: String) -> [InstalledExtension] {
        if let known = installed[profile] { return known }
        let list = InstalledExtension.all(in: profile)
        installed[profile] = list
        return list
    }

    /// Reads the installed extensions again (Chrome writes its records a few
    /// seconds after a change, so again a little later too).
    func refreshInstalled() {
        installed = [:]
        shortcuts = [:]
        onChange?()
        for delay in [3.0, 12.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.installed = [:]
                self?.shortcuts = [:]
                self?.onChange?()
            }
        }
    }

    private var shortcuts: [String: [String: (key: Key, command: String)]] = [:]

    /// The profile's extension shortcuts, as Chrome assigned them ("Alt+Shift+P"
    /// in Chrome's terms, "Command" being ⌘ and "MacCtrl" ⌃) → command.
    func shortcuts(in profile: String) -> [String: (key: Key, command: String)] {
        if let known = shortcuts[profile] { return known }
        var result: [String: (key: Key, command: String)] = [:]
        let enabled = Set(extensions(in: profile).filter(\.enabled).map(\.id))
        let file = URL(fileURLWithPath: profile).appendingPathComponent("Preferences")
        if let data = try? Data(contentsOf: file),
           let prefs = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let commands = (prefs["extensions"] as? [String: Any])?["commands"] as? [String: Any] {
            for (accelerator, value) in commands {
                guard accelerator.hasPrefix("mac:"), let entry = value as? [String: Any], entry["global"] as? Bool != true,
                      let id = entry["extension"] as? String, enabled.contains(id),
                      let command = entry["command_name"] as? String else { continue }
                result[String(accelerator.dropFirst(4))] = (Key(profile: profile, extensionID: id), command)
            }
        }
        shortcuts[profile] = result
        return result
    }

    /// Runs the extension shortcut `event` is, if it is one.
    func handleShortcut(_ event: NSEvent) -> Bool {
        guard let accelerator = Self.accelerator(event),
              let (key, command) = shortcuts(in: profilePath(store.activeSpace.profileId))[accelerator] else { return false }
        if command == "_execute_action" {
            store.runExtensionAction(key, from: nil)
        } else {
            runCommand(key, command: command, tab: store.visibleTabID)
        }
        return true
    }

    /// A key press in Chrome's accelerator syntax: "Command+Shift+Y".
    private static func accelerator(_ event: NSEvent) -> String? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if flags.contains(.command) { parts.append("Command") }
        if flags.contains(.control) { parts.append("MacCtrl") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        // A shortcut needs Command, Control or Option.
        guard !parts.isEmpty, parts != ["Shift"] else { return nil }
        let named: [UInt16: String] = [
            49: "Space", 43: "Comma", 47: "Period", 115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
            114: "Insert", 117: "Delete", 126: "Up", 125: "Down", 123: "Left", 124: "Right",
        ]
        // By physical key, as the menu does, so other layouts work too.
        let letters: [UInt16: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L", 46: "M",
            45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        ]
        guard let name = named[event.keyCode] ?? letters[event.keyCode] else { return nil }
        return (parts + [name]).joined(separator: "+")
    }

    func openOptions(_ key: Key) {
        guard let page = extensions(in: key.profile).first(where: { $0.id == key.extensionID })?.optionsPage else { return }
        openTab(["url": page, "active": true], profile: key.profile) { _ in }
    }

    // MARK: - Toolbar buttons and menus

    private func updateAction(_ key: Key, what: String, details: [String: Any]) {
        let tab = (details["tabId"] as? NSNumber)?.intValue
        var state = tab.flatMap { tabActions[key]?[$0] } ?? (tab == nil ? actions[key] ?? ActionState() : ActionState())
        switch what {
        case "setBadgeText": state.badgeText = details["text"] as? String
        case "setBadgeBackgroundColor": state.badgeColor = color(details["color"])
        case "setBadgeTextColor": state.badgeTextColor = color(details["color"])
        case "setTitle": state.title = details["title"] as? String
        case "setPopup": state.popup = details["popup"] as? String
        case "setIcon": state.icon = details["icon"] as? String
        case "enable": state.enabled = true
        case "disable": state.enabled = false
        default: return
        }
        if let tab { tabActions[key, default: [:]][tab] = state } else { actions[key] = state }
        onChange?()
    }

    private func color(_ value: Any?) -> [Double]? {
        if let array = value as? [NSNumber] { return array.map(\.doubleValue) }
        guard let text = value as? String else { return nil }
        let hex = text.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let n = UInt32(hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex, radix: 16) else { return nil }
        return [Double(n >> 16 & 0xFF), Double(n >> 8 & 0xFF), Double(n & 0xFF), 255]
    }

    /// The toolbar button for `key` as it shows on `tab` (an extension tab
    /// id).
    func action(_ key: Key, tab: Int?) -> ActionState {
        var state = actions[key] ?? ActionState()
        if let tab, let own = tabActions[key]?[tab] {
            state.badgeText = own.badgeText ?? state.badgeText
            state.badgeColor = own.badgeColor ?? state.badgeColor
            state.badgeTextColor = own.badgeTextColor ?? state.badgeTextColor
            state.title = own.title ?? state.title
            state.icon = own.icon ?? state.icon
            state.popup = own.popup ?? state.popup
            state.enabled = own.enabled ?? state.enabled
        }
        return state
    }

    private func updateMenus(_ key: Key, _ args: [String: Any]) {
        let id = (args["id"] as? NSNumber)?.stringValue ?? args["id"] as? String
        let props = (args["props"] as? [String: Any] ?? [:]).compactMapValues(JSONValue.init)
        var items = menus[key] ?? []
        switch args["op"] as? String {
        case "create":
            guard let id else { return }
            items.removeAll { $0.id == id }
            items.append(MenuItem(id: id, props: props))
        case "update":
            guard let id, let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].props.merge(props) { $1 }
        case "remove":
            // Removing an item removes its submenu too.
            var gone: Set<String> = [id].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
            var grew = true
            while grew {
                let before = gone.count
                for item in items where item.props["parentId"].map({ gone.contains($0.string) }) == true { gone.insert(item.id) }
                grew = gone.count > before
            }
            items.removeAll { gone.contains($0.id) }
        case "removeAll":
            items = []
        default:
            return
        }
        menus[key] = items.isEmpty ? nil : items
        save()
        onChange?()
    }

    /// Runs a toolbar button: shows its popup, or tells the extension it was
    /// clicked. Returns the popup page to show, if any.
    func clickAction(_ key: Key, tab: UInt64) -> String? {
        let button = action(key, tab: extensionTabID(of: tab))
        let popup = button.popup ?? extensions(in: key.profile).first { $0.id == key.extensionID }?.popup
        if let popup, !popup.isEmpty {
            return popup.hasPrefix("chrome-extension://") ? popup : "chrome-extension://\(key.extensionID)/\(popup.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }
        if let subject = tabObject(for: tab, profile: key.profile) {
            dispatch([["action.onClicked", [subject], state(profile: key.profile, requester: 0)]], to: key)
        }
        return nil
    }

    /// The page menu's items from the profile's extensions, for a menu
    /// opened on `context` (see MBWebViewDelegate): an extension's items
    /// directly if it has one, else under its name, as Chrome does.
    func pageMenuItems(profile: String, context: [String: Any]) -> [[String: Any]] {
        let contexts = Set(context["contexts"] as? [String] ?? [])
        let selection = context["selectionText"] as? String ?? ""
        var result: [[String: Any]] = []
        for ext in extensions(in: profile) where ext.enabled {
            let key = Key(profile: profile, extensionID: ext.id)
            guard let items = menus[key], !items.isEmpty else { continue }
            func shown(_ item: MenuItem) -> Bool {
                let props = item.props
                if case .bool(false) = props["visible"] { return false }
                let wanted: [String] = {
                    if case .array(let list) = props["contexts"] { return list.map(\.string) }
                    return ["page"]
                }()
                guard wanted.contains("all") || !contexts.isDisjoint(with: wanted) else { return false }
                if case .array(let patterns) = props["documentUrlPatterns"],
                   !patterns.contains(where: { matches($0.string, context["pageUrl"] as? String ?? "") }) { return false }
                if case .array(let patterns) = props["targetUrlPatterns"] {
                    let target = (context["linkUrl"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? context["srcUrl"] as? String ?? ""
                    if !patterns.contains(where: { matches($0.string, target) }) { return false }
                }
                return true
            }
            func build(parent: String?) -> [[String: Any]] {
                items.filter { $0.props["parentId"]?.string == parent && shown($0) }.map { item in
                    let title = (item.props["title"]?.string ?? "").replacingOccurrences(of: "%s", with: selection)
                    var entry: [String: Any] = [
                        "id": "\(ext.id)\u{1}\(item.id)", "title": title,
                        "type": item.props["type"]?.string ?? "normal",
                    ]
                    if case .bool(let enabled) = item.props["enabled"] { entry["enabled"] = enabled }
                    if case .bool(let checked) = item.props["checked"] { entry["checked"] = checked }
                    let children = build(parent: item.id)
                    if !children.isEmpty { entry["children"] = children }
                    return entry
                }
            }
            let top = build(parent: nil)
            if top.count == 1 {
                result += top
            } else if !top.isEmpty {
                result.append(["id": "", "title": ext.name, "children": top])
            }
        }
        return result
    }

    /// The extension's items for its toolbar button's menu (the "action"
    /// context), with ids for `choosePageMenuItem`.
    func actionMenuItems(_ key: Key) -> [(id: String, title: String, checked: Bool?)] {
        (menus[key] ?? []).compactMap { item in
            guard case .array(let contexts) = item.props["contexts"],
                  contexts.contains(where: { ["action", "browser_action", "page_action", "all"].contains($0.string) }),
                  item.props["parentId"] == nil else { return nil }
            if case .bool(false) = item.props["visible"] { return nil }
            let checked: Bool? = { if case .bool(let b) = item.props["checked"] { return b } else { return nil } }()
            return ("\(key.extensionID)\u{1}\(item.id)", item.props["title"]?.string ?? "", checked)
        }
    }

    /// A page menu item from `pageMenuItems` was chosen on `tab`.
    func choosePageMenuItem(_ id: String, context: [String: Any], profile: String, tab: UInt64) {
        let parts = id.split(separator: "\u{1}", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let key = Key(profile: profile, extensionID: parts[0])
        guard let index = menus[key]?.firstIndex(where: { $0.id == parts[1] }), let item = menus[key]?[index] else { return }
        var info: [String: Any] = ["frameId": 0, "editable": context["editable"] as? Bool ?? false]
        for field in ["pageUrl", "frameUrl", "linkUrl", "srcUrl", "mediaType", "selectionText"] {
            if let value = context[field] as? String, !value.isEmpty { info[field] = value }
        }
        // Checkboxes and radio items change as they're chosen.
        switch item.props["type"]?.string {
        case "checkbox":
            let was: Bool = { if case .bool(let b) = item.props["checked"] { return b } else { return false } }()
            info["wasChecked"] = was
            info["checked"] = !was
            menus[key]?[index].props["checked"] = .bool(!was)
        case "radio":
            let was: Bool = { if case .bool(let b) = item.props["checked"] { return b } else { return false } }()
            info["wasChecked"] = was
            info["checked"] = true
            menus[key]?[index].props["checked"] = .bool(true)
        default:
            break
        }
        clickMenu(key, item: item, info: info, tab: tab)
    }

    private func matches(_ pattern: String, _ url: String) -> Bool {
        if pattern == "<all_urls>" { return url.hasPrefix("http") || url.hasPrefix("file") || url.hasPrefix("ws") }
        let escaped = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
        let scheme = escaped.replacingOccurrences(of: "^\\.\\*://", with: "(https?|wss?)://", options: .regularExpression)
        return url.range(of: "^" + scheme + "$", options: .regularExpression) != nil
    }

    /// Tells the extension one of its menu items was chosen on a page.
    func clickMenu(_ key: Key, item: MenuItem, info: [String: Any], tab: UInt64) {
        guard let subject = tabObject(for: tab, profile: key.profile) else { return }
        var info = info
        info["menuItemId"] = item.props["id"]?.object ?? item.id
        if let parent = item.props["parentId"]?.object { info["parentMenuItemId"] = parent }
        dispatch([["contextMenus.onClicked", [info, subject], state(profile: key.profile, requester: 0)]], to: key)
    }

    /// Tells the extension one of its keyboard shortcuts was pressed.
    func runCommand(_ key: Key, command: String, tab: UInt64?) {
        let subject = tab.flatMap { tabObject(for: $0, profile: key.profile) }
        dispatch([["commands.onCommand", [command, subject.map { $0 as Any } ?? NSNull()], state(profile: key.profile, requester: 0)]], to: key)
    }

    /// Records a popup view, which counts as in MBGA's focused window.
    func registerPopup(_ view: MBWebView) {
        popupViews.add(view)
    }

    private func isPopup(_ browserID: Int32) -> Bool {
        browserID != 0 && popupViews.allObjects.contains { $0.browserIdentifier == browserID }
    }

    // MARK: - MBGA's tabs and windows, as extensions see them

    private func canonicalPath(_ path: String) -> String {
        if let known = canonical[path] { return known }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        canonical[path] = resolved
        return resolved
    }

    func profilePath(_ profileID: UInt64) -> String {
        canonicalPath(store.core.profileDir(profileId: profileID))
    }

    private func spaces(in profile: String) -> [SpaceInfo] {
        store.snapshot.spaces.filter { profilePath($0.profileId) == profile }
    }

    private func space(of tab: UInt64) -> SpaceInfo? {
        store.snapshot.spaces.first { s in
            s.favorites.contains { $0.id == tab } || s.pinned.contains { $0.tab?.id == tab } || s.today.contains { $0.id == tab }
        }
    }

    private func isPinned(_ tab: UInt64) -> Bool {
        guard let space = space(of: tab) else { return false }
        return store.isPinned(tab, in: space) || store.isFavorite(tab, in: space)
    }

    private func liveView(in profile: String) -> MBWebView? {
        for space in spaces(in: profile) {
            for tab in space.favorites + space.pinned.compactMap(\.tab) + space.today {
                if let view = store.views[tab.id], targetIDs[view.browserIdentifier] != nil { return view }
            }
        }
        return nil
    }

    /// MBGA's tab with this extension tab id.
    func tab(extensionTabID id: Int) -> UInt64? {
        store.views.first { tabIDs[$0.value.browserIdentifier] == id }?.key
    }

    /// The extension tab id of MBGA's tab, once known.
    func extensionTabID(of tab: UInt64) -> Int? {
        store.views[tab].flatMap { tabIDs[$0.browserIdentifier] }
    }

    /// Learns the extension tab ids of browsers that don't have one yet,
    /// then calls `done`. Each browser's DevTools target id is matched with
    /// the helper's chrome.debugger.getTargets(), which lists both.
    private func resolveTabIDs(_ done: @escaping () -> Void) {
        let live = store.views.values.map(\.browserIdentifier).filter { $0 != 0 }
        let liveSet = Set(live)
        tabIDs = tabIDs.filter { liveSet.contains($0.key) }
        targetIDs = targetIDs.filter { liveSet.contains($0.key) }
        lookedFor = lookedFor.filter { liveSet.contains($0.key) }
        if resolving != nil {
            resolving?.append(done)
            return
        }
        let missing = live.filter { browser in
            guard tabIDs[browser] == nil else { return false }
            guard let last = lookedFor[browser] else { return true }
            return last.times < 3 && -last.when.timeIntervalSinceNow > 1
        }
        guard devTools.available, !missing.isEmpty else { return done() }
        for browser in missing { lookedFor[browser] = (Date(), (lookedFor[browser]?.times ?? 0) + 1) }
        resolving = [done]
        resolveRound += 1
        let round = resolveRound
        let finish = { [weak self] in
            guard let self, round == resolveRound, let waiting = resolving else { return }
            resolving = nil
            waiting.forEach { $0() }
            // Tabs found now are news to extensions; ones not yet found are
            // looked for again soon.
            if missing.contains(where: { self.tabIDs[$0] != nil }) { setNeedsSync() }
            if missing.contains(where: { self.tabIDs[$0] == nil && (self.lookedFor[$0]?.times ?? 3) < 3 }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.setNeedsSync() }
            }
        }
        let views = store.views.values.filter { missing.contains($0.browserIdentifier) && targetIDs[$0.browserIdentifier] == nil }
        let group = DispatchGroup()
        for view in views {
            group.enter()
            let browser = view.browserIdentifier
            // A page's target id is its main frame's id. (The tab's own
            // DevTools connection doesn't answer the Target domain.)
            view.sendDevToolsCommand("Page.getFrameTree", params: nil) { [weak self] result, _ in
                MainActor.assumeIsolated {
                    if let data = result?.data(using: .utf8),
                       let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                       let frame = (object["frameTree"] as? [String: Any])?["frame"] as? [String: Any],
                       let target = frame["id"] as? String {
                        self?.targetIDs[browser] = target
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            helperTargets { [weak self] targets in
                guard let self else { return finish() }
                var byTarget: [String: Int] = [:]
                for target in targets {
                    if let id = target["id"] as? String, let tab = target["tabId"] as? Int { byTarget[id] = tab }
                }
                for (browser, target) in targetIDs { if let tab = byTarget[target] { tabIDs[browser] = tab } }
                log("targets \(targetIDs) → helper listed \(byTarget.count), tab ids \(tabIDs)")
                finish()
            }
        }
        // Never hold extensions up for long.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { finish() }
    }

    /// chrome.debugger.getTargets() in the helper, starting its worker if
    /// it sleeps.
    private func helperTargets(_ done: @escaping ([[String: Any]]) -> Void) {
        let evaluate = { [weak self] (target: String?) in
            guard let self, let target else { return done([]) }
            attach(target) { [weak self] session in
                guard let self, let session else { return done([]) }
                devTools.send("Runtime.evaluate", ["expression": "chrome.debugger.getTargets()", "awaitPromise": true, "returnByValue": true],
                              session: session) { [weak self] result, _ in
                    self?.devTools.send("Target.detachFromTarget", ["sessionId": session])
                    done(((result?["result"] as? [String: Any])?["value"] as? [[String: Any]]) ?? [])
                }
            }
        }
        if let running = workers.first(where: { $0.value == Self.helperID })?.key { return evaluate(running) }
        guard let page = targetIDs.values.first else { return done([]) }
        helperWaiters.append(evaluate)
        startWorker(Self.helperID, from: page)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !helperWaiters.isEmpty else { return }
            let waiters = helperWaiters
            helperWaiters = []
            waiters.forEach { $0(nil) }
        }
    }

    private func windowID(of tab: UInt64) -> Int {
        store.isInLittleWindow(tab) ? Self.mainWindowID + Int(tab) : Self.mainWindowID
    }

    /// The tab active in MBGA's main window for `profile`: the visible one
    /// when the active space uses that profile, else the current tab of its
    /// first space that has one.
    private func activeTab(in profile: String) -> UInt64? {
        let active = store.activeSpace
        if profilePath(active.profileId) == profile, let tab = active.activeTab { return tab }
        return spaces(in: profile).lazy.compactMap(\.activeTab).first
    }

    /// MBGA's main window counts as focused while MBGA is in front, unless
    /// the extensions window (Chrome's) or a little window has the keyboard:
    /// a popup or Settings in front of it still leaves it the current one.
    private var mbgaFocused: Bool {
        guard NSApp.isActive else { return false }
        guard let key = NSApp.keyWindow else { return true }
        if MBEngine.isExtensionsWindow(key) { return false }
        return !isLittleWindow(key)
    }

    private func isLittleWindow(_ window: NSWindow) -> Bool {
        store.views.contains { store.isInLittleWindow($0.key) && $0.value.window === window }
    }

    private func state(profile: String, requester: Int32) -> [String: Any] {
        var tabs: [[String: Any]] = []
        var windows: [Int: [String: Any]] = [:]
        let mainFocused = mbgaFocused && profilePath(store.activeSpace.profileId) == profile
        let active = activeTab(in: profile)
        var index: [Int: Int] = [:]
        for space in spaces(in: profile) {
            let pinned = Set((space.favorites + space.pinned.compactMap(\.tab)).map(\.id))
            for tab in space.favorites + space.pinned.compactMap(\.tab) + space.today {
                guard let view = store.views[tab.id], let id = tabIDs[view.browserIdentifier] else { continue }
                let window = windowID(of: tab.id)
                let little = window != Self.mainWindowID
                let isActive = little || tab.id == active
                let position = index[window, default: 0]
                index[window] = position + 1
                tabs.append(tabObject(tab, id: id, view: view, window: window, index: position, active: isActive,
                                      pinned: pinned.contains(tab.id)))
                if windows[window] == nil {
                    let host = little ? view.window : store.window
                    windows[window] = windowObject(window, host: host, focused: little ? NSApp.isActive && host?.isKeyWindow == true : mainFocused)
                }
            }
        }
        if windows[Self.mainWindowID] == nil {
            windows[Self.mainWindowID] = windowObject(Self.mainWindowID, host: store.window, focused: mainFocused)
        }
        let focused = windows.values.contains { $0["focused"] as? Bool == true }
        return [
            "focused": focused,
            "popup": isPopup(requester),
            "windows": windows.keys.sorted().compactMap { windows[$0] },
            "tabs": tabs,
        ]
    }

    private func tabObject(_ tab: TabInfo, id: Int, view: MBWebView, window: Int, index: Int, active: Bool,
                           pinned: Bool) -> [String: Any] {
        let loading = store.navStates[tab.id]?.isLoading == true
        return [
            "id": id, "windowId": window, "index": index,
            "active": active, "highlighted": active, "selected": active, "pinned": pinned,
            "audible": tab.audible, "discarded": false, "autoDiscardable": !tab.keepAwake, "frozen": tab.frozen,
            "mutedInfo": ["muted": false], "groupId": -1, "incognito": false,
            "url": tab.url, "title": tab.title, "status": loading ? "loading" : "complete",
            "width": Int(view.bounds.width), "height": Int(view.bounds.height),
        ]
    }

    func tabObject(for tab: UInt64, profile: String) -> [String: Any]? {
        guard let id = extensionTabID(of: tab) else { return nil }
        return (state(profile: profile, requester: 0)["tabs"] as? [[String: Any]])?.first { $0["id"] as? Int == id }
    }

    private func windowObject(_ id: Int, host: NSWindow?, focused: Bool) -> [String: Any] {
        let frame = host?.frame ?? .zero
        let screenHeight = host?.screen?.frame.maxY ?? frame.maxY
        let fullscreen = host?.styleMask.contains(.fullScreen) == true
        return [
            "id": id, "focused": focused, "type": "normal", "incognito": false, "alwaysOnTop": false,
            "state": fullscreen ? "fullscreen" : host?.isMiniaturized == true ? "minimized" : "normal",
            "left": Int(frame.minX), "top": Int(screenHeight - frame.maxY),
            "width": Int(frame.width), "height": Int(frame.height),
        ]
    }

    // MARK: - Acting on MBGA's tabs

    private func openTab(_ args: [String: Any], profile: String, done: @escaping (UInt64?) -> Void) {
        let candidates = spaces(in: profile)
        let space = candidates.first { $0.id == store.activeSpace.id } ?? candidates.first
        guard let space else { return done(nil) }
        var url = args["url"] as? String ?? ""
        if !url.isEmpty, !url.contains(":") {
            // Relative to the extension, as Chrome resolves them.
            url = URL(string: url, relativeTo: URL(string: "chrome-extension://\(args["extension"] as? String ?? "")/"))?.absoluteString ?? url
        }
        let active = args["active"] as? Bool ?? true
        guard let tab = store.core.openTab(spaceId: space.id, url: url.isEmpty ? "about:blank" : url, activate: active) else { return done(nil) }
        if args["pinned"] as? Bool == true { store.togglePin(tab, in: space) }
        store.refresh()
        store.warmTab(tab)
        // The browser, and its id, come a moment later.
        func poll(_ tries: Int) {
            if let id = store.views[tab]?.browserIdentifier, id != 0 {
                return resolveTabIDs { done(tab) }
            }
            guard tries > 0 else { return done(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { poll(tries - 1) }
        }
        poll(150)
    }

    private func capture(_ args: [String: Any], done: @escaping (String?) -> Void) {
        guard let tab = store.visibleTabID, let view = store.views[tab] else { return done(nil) }
        let format = args["format"] as? String == "png" ? "png" : "jpeg"
        let quality = args["quality"] as? Int ?? 92
        view.sendDevToolsCommand("Page.captureScreenshot", params: #"{"format":"\#(format)","quality":\#(quality)}"#) { result, _ in
            MainActor.assumeIsolated {
                guard let data = result?.data(using: .utf8),
                      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let base64 = object["data"] as? String else { return done(nil) }
                done("data:image/\(format);base64,\(base64)")
            }
        }
    }

    // MARK: - Events

    func setNeedsSync() {
        guard !syncPending else { return }
        syncPending = true
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    /// Tells each profile's extensions what changed about its tabs and
    /// windows since last time.
    private func sync() {
        syncPending = false
        resolveTabIDs { [weak self] in self?.report() }
    }

    private func report() {
        let profiles = Set(store.snapshot.spaces.map { profilePath($0.profileId) })
        for profile in profiles {
            let now = state(profile: profile, requester: 0)
            let tabs = (now["tabs"] as? [[String: Any]] ?? []).reduce(into: [Int: [String: Any]]()) { $0[$1["id"] as? Int ?? 0] = $1 }
            var active: [Int: Int] = [:]
            for tab in tabs.values where tab["active"] as? Bool == true { active[tab["windowId"] as? Int ?? 0] = tab["id"] as? Int }
            let focused = (now["windows"] as? [[String: Any]] ?? []).first { $0["focused"] as? Bool == true }?["id"] as? Int ?? -1
            let current = Report(tabs: tabs, active: active, focused: focused)
            defer { reported[profile] = current }
            guard let before = reported[profile] else { continue }
            var events: [[Any]] = []
            for (id, tab) in tabs where before.tabs[id] == nil {
                events.append(["tabs.onCreated", [tab]])
            }
            for (id, tab) in tabs {
                guard let old = before.tabs[id] else { continue }
                var change: [String: Any] = [:]
                for field in ["url", "title", "status", "pinned", "audible"] where !same(old[field], tab[field]) {
                    change[field] = tab[field]
                }
                if !change.isEmpty { events.append(["tabs.onUpdated", [id, change, tab]]) }
            }
            for (window, id) in active where before.active[window] != id {
                events.append(["tabs.onActivated", [["tabId": id, "windowId": window]]])
                events.append(["tabs.onHighlighted", [["tabIds": [id], "windowId": window]]])
            }
            for (id, old) in before.tabs where tabs[id] == nil {
                events.append(["tabs.onRemoved", [id, ["windowId": old["windowId"] ?? Self.mainWindowID, "isWindowClosing": false]]])
                for key in tabActions.keys where key.profile == profile { tabActions[key]?[id] = nil }
            }
            if focused != before.focused {
                events.append(["windows.onFocusChanged", [focused]])
            }
            guard !events.isEmpty else { continue }
            if let last = events.indices.last { events[last].append(now) }
            send(events, in: profile)
        }
    }

    private func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a as String, b as String): a == b
        case let (a as Bool, b as Bool): a == b
        default: false
        }
    }

    /// Sends each extension of `profile` the events it listens to.
    private func send(_ events: [[Any]], in profile: String) {
        for (key, names) in listening where key.profile == profile {
            let wanted = events.filter { names.contains($0[0] as? String ?? "") }
            guard !wanted.isEmpty else { continue }
            var batch = wanted
            // Every batch ends with the state it leads to.
            if batch[batch.count - 1].count < 3, let state = events.last?.last { batch[batch.count - 1].append(state) }
            dispatch(batch, to: key)
        }
    }
}

/// A JSON value that can be saved, for extensions' menu items.
enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue])

    init?(_ any: Any) {
        switch any {
        case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
        case let n as NSNumber: self = .number(n.doubleValue)
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.compactMap(JSONValue.init))
        case let o as [String: Any]: self = .object(o.compactMapValues(JSONValue.init))
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var string: String {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): String(b)
        default: ""
        }
    }

    var object: Any {
        switch self {
        case .string(let s): s
        case .number(let n): n == n.rounded() ? Int(n) as Any : n
        case .bool(let b): b
        case .array(let a): a.map(\.object)
        case .object(let o): o.mapValues(\.object)
        }
    }
}

/// An extension installed in a profile, as Chrome recorded it.
struct InstalledExtension {
    let id: String
    let name: String
    let directory: URL
    let enabled: Bool
    let manifest: [String: Any]

    var popup: String? {
        (manifest["action"] as? [String: Any])?["default_popup"] as? String
    }

    var hasAction: Bool { manifest["action"] != nil }

    var optionsPage: String? {
        let page = (manifest["options_ui"] as? [String: Any])?["page"] as? String ?? manifest["options_page"] as? String
        return page.map { "chrome-extension://\(id)/\($0.trimmingCharacters(in: CharacterSet(charactersIn: "/")))" }
    }

    /// The icon closest to `size` points (at 2x), from the action's own
    /// icons or the extension's.
    func iconFile(size: Int) -> URL? {
        let action = (manifest["action"] as? [String: Any])?["default_icon"]
        let sets: [Any?] = [action, manifest["icons"]]
        for set in sets {
            if let path = set as? String { return directory.appendingPathComponent(path) }
            guard let icons = set as? [String: String] else { continue }
            let sizes = icons.keys.compactMap(Int.init).sorted()
            guard let best = sizes.first(where: { $0 >= size * 2 }) ?? sizes.last, let path = icons[String(best)] else { continue }
            return directory.appendingPathComponent(path)
        }
        return nil
    }

    /// Commands (keyboard shortcuts) from the manifest: name → suggested key
    /// for the Mac.
    var commands: [String: String] {
        var result: [String: String] = [:]
        for (name, value) in manifest["commands"] as? [String: Any] ?? [:] {
            let keys = (value as? [String: Any])?["suggested_key"] as? [String: String]
            if let key = keys?["mac"] ?? keys?["default"] { result[name] = key }
        }
        return result
    }

    static func load(_ id: String, profile: String) -> InstalledExtension? {
        all(in: profile).first { $0.id == id }
    }

    /// The profile's extensions, without Chrome's built-in ones.
    static func all(in profile: String) -> [InstalledExtension] {
        let base = URL(fileURLWithPath: profile)
        var settings: [String: Any] = [:]
        for file in ["Preferences", "Secure Preferences"] {
            guard let data = try? Data(contentsOf: base.appendingPathComponent(file)),
                  let prefs = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let found = (prefs["extensions"] as? [String: Any])?["settings"] as? [String: Any] else { continue }
            settings.merge(found) { $1 }
        }
        return settings.compactMap { id, value -> InstalledExtension? in
            guard let entry = value as? [String: Any], let path = entry["path"] as? String else { return nil }
            // 5 and 10 are Chrome's own (the PDF viewer and such).
            let location = entry["location"] as? Int ?? 0
            guard location != 5, location != 10, id != ExtensionHost.helperID else { return nil }
            // 8 was loaded from the command line, which Chrome remembers after
            // it's gone: only those loaded this time count.
            if location == 8, !commandLinePaths.contains(URL(fileURLWithPath: path).resolvingSymlinksInPath().path) { return nil }
            let directory = path.hasPrefix("/") ? URL(fileURLWithPath: path)
                : base.appendingPathComponent("Extensions").appendingPathComponent(path)
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
                  let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
            if manifest["theme"] != nil { return nil }
            let reasons = entry["disable_reasons"] as? [Any] ?? []
            let disabledBits = entry["disable_reasons"] as? Int ?? 0
            let enabled = reasons.isEmpty && disabledBits == 0 && entry["state"] as? Int != 0
            return InstalledExtension(id: id, name: localized(manifest["name"] as? String ?? id, directory: directory, manifest: manifest),
                                      directory: directory, enabled: enabled, manifest: manifest)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Unpacked extensions loaded for development, with
    /// MBGA_ENGINE_SWITCHES="--load-extension=<dir>[,<dir>...]".
    private static let commandLinePaths: Set<String> = {
        let switches = ProcessInfo.processInfo.environment["MBGA_ENGINE_SWITCHES"] ?? ""
        return Set(switches.split(separator: " ").filter { $0.hasPrefix("--load-extension=") }.flatMap {
            $0.dropFirst("--load-extension=".count).split(separator: ",").map {
                URL(fileURLWithPath: String($0)).resolvingSymlinksInPath().path
            }
        })
    }()

    /// Resolves "__MSG_name__" from the extension's messages.
    private static func localized(_ text: String, directory: URL, manifest: [String: Any]) -> String {
        guard text.hasPrefix("__MSG_"), text.hasSuffix("__") else { return text }
        let key = String(text.dropFirst(6).dropLast(2)).lowercased()
        let locales: [String?] = [Locale.current.identifier, Locale.current.language.languageCode?.identifier, manifest["default_locale"] as? String, "en"]
        for locale in locales.compactMap({ $0 }) {
            let file = directory.appendingPathComponent("_locales/\(locale)/messages.json")
            guard let data = try? Data(contentsOf: file),
                  let messages = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            for (name, value) in messages where name.lowercased() == key {
                if let message = (value as? [String: Any])?["message"] as? String { return message }
            }
        }
        return text
    }
}
