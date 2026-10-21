import AppKit
import JavaScriptCore

// The commands agents run, built to keep their context small: a page is a
// short outline of what can be read and used, each element with a ref
// ("e12") to act on, instead of HTML or screenshots. Pages are read through
// a JavaScript world of MBGA's own, which shares the page's DOM but not its
// scripts, and acted on with real (trusted) input events.

struct AgentError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Lets only the first of a reply and a timeout through.
@MainActor
private final class Once {
    private var done = false
    func claim() -> Bool {
        defer { done = true }
        return !done
    }
}

/// Parsed command line: words, and --flags with optional values.
struct AgentArguments {
    var words: [String] = []
    var flags: [String: String] = [:]

    init(_ argv: ArraySlice<String>) {
        var rest = argv[...]
        while let arg = rest.popFirst() {
            if arg.hasPrefix("--"), arg.count > 2 {
                let body = arg.dropFirst(2)
                if let eq = body.firstIndex(of: "=") {
                    flags[String(body[..<eq])] = String(body[body.index(after: eq)...])
                } else if ["tab", "max", "out", "timeout"].contains(body), let value = rest.popFirst() {
                    flags[String(body)] = value
                } else {
                    flags[String(body)] = ""
                }
            } else if arg == "-t", let value = rest.popFirst() {
                flags["tab"] = value
            } else {
                words.append(arg)
            }
        }
    }

    func has(_ flag: String) -> Bool { flags[flag] != nil }
    func int(_ flag: String) -> Int? { flags[flag].flatMap { Int($0) } }
    subscript(_ i: Int) -> String? { words.indices.contains(i) ? words[i] : nil }
}

@MainActor
final class AgentCommands {
    private let store: BrowserStore
    /// Each tab's JavaScript world, by execution context.
    private var worlds: [UInt64: Int] = [:]

    init(store: BrowserStore) {
        self.store = store
    }

    func run(_ argv: [String]) async -> AgentReply {
        guard AgentSettings.enabled else {
            return .failure("Agent access is off. Turn it on in MBGA ▸ Settings ▸ Agents.")
        }
        let command = argv[0].lowercased()
        let args = AgentArguments(argv.dropFirst())
        do {
            return .success(try await perform(command, args))
        } catch let error as AgentError {
            return .failure(error.message)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func perform(_ command: String, _ args: AgentArguments) async throws -> String {
        switch command {
        case "tabs": return tabs(all: args.has("all"))
        case "open": return try await open(args)
        case "use": return try use(args)
        case "focus": return try focus(args)
        case "close": return try close(args)
        case "info": return try await info(args)
        case "snapshot", "snap": return try await snapshot(args)
        case "read", "text": return try await read(args)
        case "find": return try await find(args)
        case "click": return try await click(args)
        case "hover": return try await hover(args)
        case "fill", "type": return try await fill(args, append: command == "type" && args.has("append"))
        case "press", "key": return try await press(args)
        case "select": return try await select(args)
        case "scroll": return try await scroll(args)
        case "wait": return try await wait(args)
        case "eval", "js": return try await eval(args)
        case "screenshot", "shot": return try await screenshot(args)
        case "console": return try console(args)
        case "back", "forward", "reload": return try await navigate(command, args)
        case "goto", "navigate": return try await goto(args)
        case "run": return try await runScript(args)
        default: throw AgentError("Unknown command \"\(command)\". Run `mbga help`.")
        }
    }

    // MARK: Tabs

    /// The tab a command is for: --tab, else the one the agent last used,
    /// else the one on screen.
    private func target(_ args: AgentArguments) throws -> UInt64 {
        if let name = args.flags["tab"] {
            guard let id = UInt64(name.hasPrefix("t") ? String(name.dropFirst()) : name), store.core.tab(id: id) != nil else {
                throw AgentError("No tab \(name). Run `mbga tabs`.")
            }
            return id
        }
        if let id = store.agentTab, store.core.tab(id: id) != nil { return id }
        guard let id = store.visibleTabID else { throw AgentError("No tab is open. Use `mbga open <url>`.") }
        return id
    }

    /// The tab's page, loading it if it was asleep.
    private func page(_ id: UInt64) async throws -> MBWebView {
        let loaded = store.isLoaded(id)
        guard let view = store.engineView(for: id) else { throw AgentError("Tab t\(id) has no page.") }
        if !loaded { try await waitForLoad(id, timeout: 15) }
        store.agentActed(on: id)
        return view
    }

    private func line(_ id: UInt64) -> String {
        guard let tab = store.core.tab(id: id) else { return "t\(id)" }
        var text = "t\(id) \(tab.title.isEmpty ? "Untitled" : tab.title) — \(tab.url)"
        let report = store.devReport(of: id)
        if let status = report.statusText, (report.status ?? 0) >= 400 || (report.status ?? 0) < 0 { text += " (\(status))" }
        return text
    }

    private func tabs(all: Bool) -> String {
        var out: [String] = []
        let spaces = all ? store.snapshot.spaces : [store.activeSpace]
        for space in spaces {
            if all { out.append("\(space.name):") }
            for tab in space.favorites + space.pinned.compactMap(\.tab) + space.today {
                let mark = tab.id == store.visibleTabID ? "*" : tab.id == store.agentTab ? ">" : " "
                out.append("\(all ? "  " : "")\(mark) \(line(tab.id))")
            }
        }
        out.append("(* on screen, > yours; act on another with --tab tN)")
        return out.joined(separator: "\n")
    }

    private func open(_ args: AgentArguments) async throws -> String {
        guard let input = args[0] else { throw AgentError("Usage: mbga open <url or search> [--focus]") }
        let url = store.core.resolveInput(text: args.words.joined(separator: " "))
        guard let id = store.openTabForAgent(url, focus: args.has("focus")) else { throw AgentError("Couldn't open \(input).") }
        store.agentTab = id
        _ = try await page(id)
        try await waitForLoad(id, timeout: Double(args.int("timeout") ?? 15))
        return line(id)
    }

    private func use(_ args: AgentArguments) throws -> String {
        guard let name = args[0] else { throw AgentError("Usage: mbga use tN") }
        var named = args
        named.flags["tab"] = name
        let id = try target(named)
        store.agentTab = id
        return line(id)
    }

    private func focus(_ args: AgentArguments) throws -> String {
        var named = args
        if let name = args[0] { named.flags["tab"] = name }
        let id = try target(named)
        store.select(id, in: store.spaceID(of: id))
        return line(id)
    }

    private func close(_ args: AgentArguments) throws -> String {
        var named = args
        if let name = args[0] { named.flags["tab"] = name }
        let id = try target(named)
        let closed = line(id)
        store.close(id)
        if store.agentTab == id { store.agentTab = nil }
        return "closed \(closed)"
    }

    private func info(_ args: AgentArguments) async throws -> String {
        let id = try target(args)
        var out = [line(id)]
        let report = store.devReport(of: id)
        if store.navState(of: id).isLoading { out.append("loading") }
        if let status = report.statusText { out.append("status \(status)" + (report.durationText.map { ", \($0)" } ?? "")) }
        if report.errors + report.warnings > 0 { out.append("console: \(report.errors) errors, \(report.warnings) warnings") }
        return out.joined(separator: "\n")
    }

    // MARK: Reading

    private func snapshot(_ args: AgentArguments) async throws -> String {
        let id = try target(args)
        let view = try await page(id)
        let options: [String: Any] = [
            "max": args.int("max") ?? 250, "text": args.has("text"), "viewport": args.has("viewport"),
        ]
        return try await call(id, view, "snapshot", options) as? String ?? ""
    }

    private func read(_ args: AgentArguments) async throws -> String {
        let id = try target(args)
        let view = try await page(id)
        let options: [String: Any] = ["max": args.int("max") ?? 6000, "all": args.has("all")]
        return try await call(id, view, "read", options) as? String ?? ""
    }

    private func find(_ args: AgentArguments) async throws -> String {
        guard !args.words.isEmpty else { throw AgentError("Usage: mbga find <text>") }
        let id = try target(args)
        let view = try await page(id)
        return try await call(id, view, "find", args.words.joined(separator: " ")) as? String ?? ""
    }

    private func eval(_ args: AgentArguments) async throws -> String {
        guard !args.words.isEmpty else { throw AgentError("Usage: mbga eval '<expression>' (runs in the page's own world)") }
        let id = try target(args)
        let view = try await page(id)
        // In the page's world, so its own globals and frameworks are there.
        let result = try await cdp(view, "Runtime.evaluate", [
            "expression": args.words.joined(separator: " "), "returnByValue": true, "awaitPromise": true,
            "userGesture": true,
        ])
        if let exception = result["exceptionDetails"] as? [String: Any] { throw AgentError(Self.describe(exception)) }
        let value = (result["result"] as? [String: Any])?["value"]
        return Self.json(value)
    }

    private func console(_ args: AgentArguments) throws -> String {
        let id = try target(args)
        var entries = store.consoleEntries(of: id)
        if args.has("errors") { entries = entries.filter { $0.level >= 3 } }
        if args.has("clear") { store.clearConsole(of: id) }
        let max = args.int("max") ?? 50
        guard !entries.isEmpty else { return "No console messages since the page loaded." }
        let names = ["debug", "info", "warn", "error"]
        var out = entries.suffix(max).map { entry in
            let place = entry.source.isEmpty ? "" : " (\(URL(string: entry.source)?.lastPathComponent ?? entry.source):\(entry.line))"
            return "\(names[min(entry.level, 3)])  \(entry.text.prefix(300))\(place)"
        }
        if entries.count > max { out.insert("… \(entries.count - max) earlier", at: 0) }
        return out.joined(separator: "\n")
    }

    // MARK: Acting

    private func click(_ args: AgentArguments) async throws -> String {
        let (id, view, ref) = try await element(args, usage: "mbga click <ref> [--force]")
        let point = try await call(id, view, "point", ref) as? [String: Any] ?? [:]
        let label = point["label"] as? String ?? ref
        if let covered = point["covered"] as? String, !covered.isEmpty, !args.has("force") {
            throw AgentError("\(label) is covered by \(covered). Close that first, or use --force to click whatever is on top.")
        }
        let x = point["x"] as? Double ?? 0, y = point["y"] as? Double ?? 0
        let before = store.core.tab(id: id)?.url
        for type in ["mouseMoved", "mousePressed", "mouseReleased"] {
            _ = try await cdp(view, "Input.dispatchMouseEvent", [
                "type": type, "x": x, "y": y, "button": type == "mouseMoved" ? "none" : "left",
                "buttons": type == "mousePressed" ? 1 : 0, "clickCount": type == "mouseMoved" ? 0 : 1,
            ])
        }
        return "clicked \(label)" + (try await settle(id, from: before))
    }

    private func hover(_ args: AgentArguments) async throws -> String {
        let (id, view, ref) = try await element(args, usage: "mbga hover <ref>")
        let point = try await call(id, view, "point", ref) as? [String: Any] ?? [:]
        _ = try await cdp(view, "Input.dispatchMouseEvent", [
            "type": "mouseMoved", "x": point["x"] as? Double ?? 0, "y": point["y"] as? Double ?? 0,
        ])
        return "hovering \(point["label"] as? String ?? ref)"
    }

    private func fill(_ args: AgentArguments, append: Bool) async throws -> String {
        guard args.words.count >= 2 else { throw AgentError("Usage: mbga fill <ref> <text> [--enter]  (type --append adds to what's there)") }
        let (id, view, ref) = try await element(args, usage: "")
        let text = args.words.dropFirst().joined(separator: " ")
        let label = try await call(id, view, "focus", ["ref": ref, "select": !append]) as? String ?? ref
        if text.isEmpty {
            try await key(view, "Backspace")
        } else {
            _ = try await cdp(view, "Input.insertText", ["text": text])
        }
        let before = store.core.tab(id: id)?.url
        if args.has("enter") {
            try await key(view, "Enter")
            return "filled \(label) and pressed Enter" + (try await settle(id, from: before))
        }
        // As it is now, with the text in it.
        return "filled " + ((try? await call(id, view, "label", ref) as? String) ?? label)
    }

    private func press(_ args: AgentArguments) async throws -> String {
        guard let name = args[0] else { throw AgentError("Usage: mbga press <key>  (Enter, Tab, Escape, ArrowDown, Shift+Tab, …)") }
        let id = try target(args)
        let view = try await page(id)
        let before = store.core.tab(id: id)?.url
        for _ in 0..<(args.int("times") ?? 1) { try await key(view, name) }
        return "pressed \(name)" + (try await settle(id, from: before))
    }

    private func select(_ args: AgentArguments) async throws -> String {
        guard args.words.count >= 2 else { throw AgentError("Usage: mbga select <ref> <option text or value>") }
        let (id, view, ref) = try await element(args, usage: "")
        let value = args.words.dropFirst().joined(separator: " ")
        return try await call(id, view, "choose", ["ref": ref, "value": value]) as? String ?? ""
    }

    private func scroll(_ args: AgentArguments) async throws -> String {
        let id = try target(args)
        let view = try await page(id)
        let word = args[0] ?? "down"
        if word.hasPrefix("e"), Int(word.dropFirst()) != nil {
            return try await call(id, view, "reveal", word) as? String ?? ""
        }
        let size = try await call(id, view, "viewport", nil) as? [String: Any] ?? [:]
        let width = size["width"] as? Double ?? 800, height = size["height"] as? Double ?? 600
        let amount = args[1].flatMap(Double.init) ?? height * 0.8
        let (dx, dy): (Double, Double) = switch word {
        case "up": (0, -amount)
        case "left": (-amount, 0)
        case "right": (amount, 0)
        case "top": (0, -1e7)
        case "bottom": (0, 1e7)
        default: (0, amount)
        }
        _ = try await cdp(view, "Input.dispatchMouseEvent", [
            "type": "mouseWheel", "x": width / 2, "y": height / 2, "deltaX": dx, "deltaY": dy,
        ])
        try await Task.sleep(for: .milliseconds(250))
        return try await call(id, view, "position", nil) as? String ?? "scrolled"
    }

    private func navigate(_ command: String, _ args: AgentArguments) async throws -> String {
        let id = try target(args)
        let view = try await page(id)
        switch command {
        case "back": view.goBack()
        case "forward": view.goForward()
        default: args.has("hard") ? view.reloadIgnoringCache() : view.reload()
        }
        try await Task.sleep(for: .milliseconds(150))
        try await waitForLoad(id, timeout: 15)
        return line(id)
    }

    private func goto(_ args: AgentArguments) async throws -> String {
        guard !args.words.isEmpty else { throw AgentError("Usage: mbga goto <url>") }
        let id = try target(args)
        let view = try await page(id)
        let url = store.core.resolveInput(text: args.words.joined(separator: " "))
        store.core.updateTab(id: id, url: url, title: nil)
        view.loadURL(url)
        try await Task.sleep(for: .milliseconds(150))
        try await waitForLoad(id, timeout: Double(args.int("timeout") ?? 15))
        return line(id)
    }

    private func wait(_ args: AgentArguments) async throws -> String {
        let id = try target(args)
        let timeout = Double(args.int("timeout") ?? 15)
        guard let what = args[0] else { throw AgentError("Usage: mbga wait load | <ms> | text <text> | gone <text>") }
        if let ms = Int(what) {
            try await Task.sleep(for: .milliseconds(ms))
            return "waited \(ms) ms"
        }
        if what == "load" {
            try await waitForLoad(id, timeout: timeout)
            return line(id)
        }
        let text = args.words.dropFirst().joined(separator: " ")
        guard what == "text" || what == "gone", !text.isEmpty else {
            throw AgentError("Usage: mbga wait load | <ms> | text <text> | gone <text>")
        }
        let view = try await page(id)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let found = try await call(id, view, "contains", text) as? Bool ?? false
            if found == (what == "text") { return what == "text" ? "found \"\(text)\"" : "\"\(text)\" is gone" }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw AgentError("Timed out after \(Int(timeout)) s waiting for \"\(text)\" to \(what == "text" ? "appear" : "go").")
    }

    private func screenshot(_ args: AgentArguments) async throws -> String {
        let id = try target(args)
        let view = try await page(id)
        let size = try await call(id, view, "viewport", nil) as? [String: Any] ?? [:]
        let width = size["width"] as? Double ?? 800, height = size["height"] as? Double ?? 600
        let full = args.has("full")
        var params: [String: Any] = ["format": "png"]
        // At CSS pixels, not the display's: a quarter of the size for the same
        // detail an agent can use.
        let scale = 1 / max(size["dpr"] as? Double ?? 1, 1)
        if full {
            let page = size["page"] as? Double ?? height
            params["captureBeyondViewport"] = true
            params["clip"] = ["x": 0, "y": 0, "width": width, "height": min(page, 16384), "scale": scale]
        } else {
            let scrollY = size["scrollY"] as? Double ?? 0, scrollX = size["scrollX"] as? Double ?? 0
            params["clip"] = ["x": scrollX, "y": scrollY, "width": width, "height": height, "scale": scale]
        }
        // A tab out of sight draws nothing to capture: it draws behind the
        // page on screen meanwhile, where the person doesn't see it.
        let restore = store.renderBehind(id)
        defer { restore() }
        if id != store.visibleTabID { try await Task.sleep(for: .milliseconds(300)) }
        let result = try await cdp(view, "Page.captureScreenshot", params, timeout: 10)
        guard let base64 = result["data"] as? String, let data = Data(base64Encoded: base64) else {
            throw AgentError("The screenshot failed.")
        }
        let path = args.flags["out"].map { ($0 as NSString).expandingTildeInPath }
            ?? NSTemporaryDirectory() + "mbga-t\(id)-\(Int(Date().timeIntervalSince1970)).png"
        try data.write(to: URL(fileURLWithPath: path))
        return "\(path) (\(Int(width)) × \(Int(full ? (size["page"] as? Double ?? height) : height)))"
    }

    // MARK: Scripts

    /// `mbga run`: a script with the commands as async functions, run here
    /// so one call can open, act and extract across pages, and only what it
    /// returns or logs comes back.
    private func runScript(_ args: AgentArguments) async throws -> String {
        guard let source = args.words.first, !source.isEmpty else {
            throw AgentError("Usage: mbga run <file.js | - | -e 'code'>")
        }
        let script = AgentScriptRunner(commands: self, timeout: Double(args.int("timeout") ?? 120))
        return try await script.run(source)
    }

    // MARK: Helpers

    private func element(_ args: AgentArguments, usage: String) async throws -> (UInt64, MBWebView, String) {
        guard let ref = args[0] else { throw AgentError("Usage: \(usage)") }
        let id = try target(args)
        let view = try await page(id)
        return (id, view, ref.hasPrefix("[") && ref.hasSuffix("]") ? String(ref.dropFirst().dropLast()) : ref)
    }

    /// After an action: waits for a navigation it started, and says where
    /// the page went.
    private func settle(_ id: UInt64, from before: String?) async throws -> String {
        try await Task.sleep(for: .milliseconds(200))
        if store.navState(of: id).isLoading { try await waitForLoad(id, timeout: 15) }
        guard let after = store.core.tab(id: id)?.url, after != before else { return "" }
        return "\n→ " + line(id)
    }

    private func waitForLoad(_ id: UInt64, timeout: Double) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while store.navState(of: id).isLoading || !store.isLoaded(id) {
            guard Date() < deadline else { throw AgentError("t\(id) is still loading after \(Int(timeout)) s.") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func key(_ view: MBWebView, _ name: String) async throws {
        var parts = name.split(separator: "+").map(String.init)
        let keyName = parts.removeLast()
        var modifiers = 0
        for part in parts {
            switch part.lowercased() {
            case "alt", "option": modifiers |= 1
            case "ctrl", "control": modifiers |= 2
            case "meta", "cmd", "command": modifiers |= 4
            case "shift": modifiers |= 8
            default: throw AgentError("Unknown modifier \(part)")
            }
        }
        let named: [String: (code: String, keyCode: Int, text: String)] = [
            "Enter": ("Enter", 13, "\r"), "Tab": ("Tab", 9, ""), "Escape": ("Escape", 27, ""),
            "Backspace": ("Backspace", 8, ""), "Delete": ("Delete", 46, ""), "Space": ("Space", 32, " "),
            "ArrowUp": ("ArrowUp", 38, ""), "ArrowDown": ("ArrowDown", 40, ""), "ArrowLeft": ("ArrowLeft", 37, ""),
            "ArrowRight": ("ArrowRight", 39, ""), "Home": ("Home", 36, ""), "End": ("End", 35, ""),
            "PageUp": ("PageUp", 33, ""), "PageDown": ("PageDown", 34, ""),
        ]
        let aliases = ["esc": "Escape", "return": "Enter", "up": "ArrowUp", "down": "ArrowDown", "left": "ArrowLeft",
                       "right": "ArrowRight", "space": "Space", "del": "Delete", "backspace": "Backspace",
                       "tab": "Tab", "enter": "Enter", "escape": "Escape", "pageup": "PageUp", "pagedown": "PageDown",
                       "home": "Home", "end": "End"]
        let canonical = aliases[keyName.lowercased()] ?? keyName
        var event: [String: Any] = ["modifiers": modifiers]
        if let known = named[canonical] {
            event["key"] = canonical == "Space" ? " " : canonical
            event["code"] = known.code
            event["windowsVirtualKeyCode"] = known.keyCode
            if !known.text.isEmpty, modifiers & 7 == 0 { event["text"] = known.text }
        } else if canonical.count == 1 {
            let character = modifiers & 8 != 0 ? canonical.uppercased() : canonical.lowercased()
            event["key"] = character
            event["code"] = canonical.first!.isLetter ? "Key\(canonical.uppercased())" : "Digit\(canonical)"
            event["windowsVirtualKeyCode"] = Int(canonical.uppercased().unicodeScalars.first!.value)
            if modifiers & 7 == 0 { event["text"] = character }
        } else {
            throw AgentError("Unknown key \(keyName)")
        }
        var down = event
        down["type"] = event["text"] != nil ? "keyDown" : "rawKeyDown"
        _ = try await cdp(view, "Input.dispatchKeyEvent", down)
        var up = event
        up["type"] = "keyUp"
        up["text"] = nil
        _ = try await cdp(view, "Input.dispatchKeyEvent", up)
    }

    /// A DevTools command, given up on after `timeout` so no command hangs
    /// (a page can stop answering, or wait for a frame that never comes).
    private func cdp(_ view: MBWebView, _ method: String, _ params: [String: Any]? = nil,
                     timeout: Double = 20) async throws -> [String: Any] {
        let json = try params.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
        let once = Once()
        let text: String = try await withCheckedThrowingContinuation { continuation in
            view.sendDevToolsCommand(method, params: json) { result, error in
                guard once.claim() else { return }
                if let result { continuation.resume(returning: result) } else {
                    continuation.resume(throwing: AgentError(error ?? "\(method) failed"))
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard once.claim() else { return }
                continuation.resume(throwing: AgentError("The page didn't answer \(method) within \(Int(timeout)) s."))
            }
        }
        return (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
    }

    /// Calls one of AgentScript's functions in MBGA's world in the tab's
    /// page, making the world first (again after a navigation).
    private func call(_ id: UInt64, _ view: MBWebView, _ function: String, _ argument: Any?) async throws -> Any? {
        let argumentJSON = argument.map { Self.json($0) } ?? "null"
        let expression = "__mbga.\(function)(\(argumentJSON))"
        for attempt in 0..<2 {
            let context = try await world(id, view, fresh: attempt > 0)
            let result: [String: Any]
            do {
                result = try await cdp(view, "Runtime.evaluate", [
                    "expression": expression, "contextId": context, "returnByValue": true, "awaitPromise": true,
                ])
            } catch let error as AgentError where attempt == 0 && error.message.contains("context") {
                continue
            }
            if let exception = result["exceptionDetails"] as? [String: Any] {
                let message = Self.describe(exception)
                // The world went with the page it was made in.
                if attempt == 0, message.contains("__mbga is not defined") { continue }
                throw AgentError(message.replacingOccurrences(of: "Error: ", with: ""))
            }
            return (result["result"] as? [String: Any])?["value"]
        }
        throw AgentError("The page changed while reading it; try again.")
    }

    private func world(_ id: UInt64, _ view: MBWebView, fresh: Bool) async throws -> Int {
        if !fresh, let context = worlds[id] { return context }
        let tree = try await cdp(view, "Page.getFrameTree")
        guard let frame = ((tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any])?["id"] as? String else {
            throw AgentError("The page has no frame yet.")
        }
        let made = try await cdp(view, "Page.createIsolatedWorld", ["frameId": frame, "worldName": "mbga-agent"])
        guard let context = made["executionContextId"] as? Int else { throw AgentError("Couldn't reach the page.") }
        _ = try await cdp(view, "Runtime.evaluate", ["expression": AgentScript.source, "contextId": context])
        worlds[id] = context
        return context
    }

    private static func describe(_ exception: [String: Any]) -> String {
        ((exception["exception"] as? [String: Any])?["description"] as? String)?
            .components(separatedBy: "\n").first ?? exception["text"] as? String ?? "The script failed."
    }

    static func json(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "null" }
        if let string = value as? String {
            let data = try? JSONSerialization.data(withJSONObject: [string], options: [.fragmentsAllowed])
            return data.map { String(decoding: $0, as: UTF8.self).dropFirst().dropLast() }.map(String.init) ?? "\"\""
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// The page side, defined once in MBGA's world of each page.
enum AgentScript {
    static let source = #"""
    (() => {
    if (window.__mbga) return;
    const S = { next: 1, byRef: new Map(), refOf: new WeakMap() };
    const ACT = 'a[href],button,input:not([type=hidden]),select,textarea,summary,[role=button],[role=link],[role=checkbox],[role=radio],[role=switch],[role=tab],[role=menuitem],[role=menuitemcheckbox],[role=menuitemradio],[role=option],[role=combobox],[role=textbox],[role=searchbox],[role=slider],[role=spinbutton],[contenteditable=""],[contenteditable=true],[onclick],[tabindex]:not([tabindex="-1"])';
    const HEAD = 'h1,h2,h3,h4,h5,h6,[role=heading]';
    const TEXT = 'p,li,td,th,dt,dd,blockquote,pre,figcaption,caption';
    const LAND = { NAV: 'nav', MAIN: 'main', HEADER: 'header', FOOTER: 'footer', ASIDE: 'aside', FORM: 'form', DIALOG: 'dialog' };
    const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'HEAD', 'META', 'LINK']);
    const clean = (s, n) => { s = (s || '').replace(/\s+/g, ' ').trim(); return n && s.length > n ? s.slice(0, n - 1) + '…' : s; };
    const ref = el => { let r = S.refOf.get(el); if (!r) { r = 'e' + S.next++; S.refOf.set(el, r); } S.byRef.set(r, el); return r; };
    const shown = el => el.checkVisibility ? el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true }) : el.getClientRects().length > 0;
    // A ref from a snapshot, or css=<selector> / text=<words> for code
    // that already knows the page.
    const get = r => {
      if (r.startsWith('css=')) { const el = document.querySelector(r.slice(4)); if (!el) throw new Error(`Nothing matches ${r.slice(4)}.`); return el; }
      if (r.startsWith('text=')) {
        const q = r.slice(5).toLowerCase();
        let fallback = null;
        for (const el of document.body.querySelectorAll('*')) {
          if (SKIP.has(el.tagName) || !shown(el)) continue;
          const own = Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' ');
          if (!(own + ' ' + (el.getAttribute('aria-label') || '') + ' ' + (el.value || '')).toLowerCase().includes(q)) continue;
          // Something to act on wins over a heading or paragraph saying the same.
          const label = el.closest('label');
          const target = (label && label.control) || el.closest(ACT);
          if (target) return target;
          fallback = fallback || el;
        }
        if (fallback) return fallback;
        throw new Error(`Nothing on the page says "${r.slice(5)}".`);
      }
      const el = S.byRef.get(r);
      if (!el || !el.isConnected) throw new Error(`No element ${r} on the page now. Run \`mbga snapshot\` for fresh refs.`);
      return el;
    };
    function role(el) {
      const r = el.getAttribute('role'); if (r) return r.split(' ')[0];
      const t = el.tagName;
      if (t === 'A') return 'link';
      if (t === 'BUTTON' || t === 'SUMMARY') return 'button';
      if (t === 'SELECT') return 'combobox';
      if (t === 'TEXTAREA') return 'textbox';
      if (t === 'INPUT') { const ty = (el.type || 'text').toLowerCase(); return { checkbox: 'checkbox', radio: 'radio', range: 'slider', submit: 'button', button: 'button', reset: 'button', image: 'button', file: 'file', color: 'color', search: 'searchbox', number: 'spinbutton' }[ty] || 'textbox'; }
      if (/^H[1-6]$/.test(t)) return 'heading';
      if (el.isContentEditable) return 'textbox';
      return 'clickable';
    }
    const typing = el => ['textbox', 'searchbox', 'spinbutton', 'combobox'].includes(role(el)) && el.tagName !== 'SELECT';
    function name(el) {
      let n = el.getAttribute('aria-label'); if (n && n.trim()) return n;
      const by = el.getAttribute('aria-labelledby');
      if (by) { n = by.split(/\s+/).map(id => document.getElementById(id)?.innerText || '').join(' '); if (n.trim()) return n; }
      // A label's own words, not those of the control inside it.
      if (el.labels && el.labels.length) { n = Array.from(el.labels).map(labelText).join(' '); if (n.trim()) return n; }
      if (el.tagName === 'IMG') return el.alt || '';
      if (el.tagName === 'INPUT' && ['submit', 'button', 'reset'].includes(el.type)) return el.value;
      if (!typing(el)) { n = el.innerText; if (n && n.trim()) return n; }
      return el.getAttribute('placeholder') || el.getAttribute('title') || el.querySelector?.('img[alt]')?.alt || el.querySelector?.('[aria-label]')?.getAttribute('aria-label') || el.getAttribute('name') || '';
    }
    function labelText(l) {
      const copy = l.cloneNode(true);
      copy.querySelectorAll('input,select,textarea,button').forEach(c => c.remove());
      return copy.textContent;
    }
    function describe(el) {
      const ro = role(el);
      let s = `[${ref(el)}] ${ro}`;
      const nm = clean(name(el), 80);
      if (nm) s += ` "${nm.replace(/"/g, "'")}"`;
      if (ro === 'link') {
        const h = el.getAttribute('href');
        if (h && !h.startsWith('javascript:') && h !== '#') { try { const u = new URL(h, location.href); s += ' → ' + (u.origin === location.origin ? u.pathname + u.search + u.hash : clean(u.href, 70)); } catch (e) {} }
      }
      if (typing(el)) {
        const v = el.isContentEditable ? el.innerText : el.value;
        if (v) s += ` = "${clean(el.type === 'password' ? '•'.repeat(Math.min(v.length, 8)) : v, 60)}"`;
        if (el.tagName === 'INPUT' && !['text', 'search', 'number', 'password'].includes(el.type)) s += ` (${el.type})`;
      }
      if (el.tagName === 'SELECT') s += ` = "${clean(el.selectedOptions[0]?.text, 40)}" of ${el.options.length}`;
      if (['checkbox', 'radio', 'switch', 'menuitemcheckbox'].includes(ro)) s += (el.checked || el.getAttribute('aria-checked') === 'true') ? ' [x]' : ' [ ]';
      if (ro === 'tab' && el.getAttribute('aria-selected') === 'true') s += ' (selected)';
      if (el.disabled || el.getAttribute('aria-disabled') === 'true') s += ' (disabled)';
      const ex = el.getAttribute('aria-expanded'); if (ex) s += ex === 'true' ? ' (expanded)' : ' (collapsed)';
      if (document.activeElement === el) s += ' (focused)';
      return s;
    }
    // Divs that act as buttons: a pointer cursor its parent doesn't have.
    function pointer(el) {
      if (!el.firstChild || el.children.length > 8) return false;
      const c = getComputedStyle(el).cursor;
      return c === 'pointer' && (!el.parentElement || getComputedStyle(el.parentElement).cursor !== 'pointer');
    }
    function where() {
      const max = Math.max(document.documentElement.scrollHeight - innerHeight, 0);
      return max > 0 ? `scrolled ${Math.round(scrollY)} of ${max} px` : 'fits on screen';
    }
    function snapshot(o) {
      o = o || {};
      const max = o.max || 250, lines = [], vh = innerHeight;
      let more = 0, above = false, visible = false, below = false;
      const emit = (el, text, depth) => {
        const r = el.getBoundingClientRect();
        if (o.viewport && (r.bottom < 0 || r.top > vh)) return;
        if (r.bottom < 0) above = true;
        else if (r.top > vh) { if (!below && lines.length) lines.push('--- below the visible area ---'); below = true; }
        else if (!visible) { if (above) lines.push('--- visible area ---'); visible = true; }
        if (lines.length >= max) { more++; return; }
        lines.push('  '.repeat(depth) + text);
      };
      const visit = (root, depth) => {
        for (let el = root.firstElementChild; el; el = el.nextElementSibling) {
          if (SKIP.has(el.tagName)) continue;
          if (!shown(el)) continue;
          if (el.matches(HEAD)) { const lv = +(el.getAttribute('aria-level') || el.tagName[1] || 2); emit(el, '#'.repeat(Math.min(lv, 6) || 2) + ' ' + clean(el.innerText, 100), depth); continue; }
          const act = el.matches(ACT) || (el.tagName !== 'BODY' && pointer(el));
          if (act && !(role(el) === 'clickable' && el.querySelector(ACT))) { emit(el, describe(el), depth); continue; }
          if (el.tagName === 'IFRAME') { emit(el, `[frame] ${clean(el.title || el.src, 70)} (not read)`, depth); continue; }
          if (el.tagName === 'IMG' && el.alt && o.text) { emit(el, `img "${clean(el.alt, 60)}"`, depth); continue; }
          if (o.text && el.tagName === 'TR') {
            const cells = Array.from(el.cells).map(c => clean(c.innerText, 60)).filter(Boolean);
            if (cells.length) emit(el, cells.join(' | '), depth);
            if (!el.querySelector(ACT)) continue;
          }
          else if (el.tagName === 'LABEL' && el.control) { /* named by its control */ }
          else if (o.text && el.matches(TEXT)) { const t = clean(el.innerText, 200); if (t) emit(el, t, depth); if (!el.querySelector(ACT)) continue; }
          // Apps put text straight in divs and spans: their own text counts.
          else if (o.text) { const own = clean(Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' '), 200); if (own.length > 1) emit(el, own, depth); }
          const land = LAND[el.tagName] || ({ navigation: 'nav', main: 'main', dialog: 'dialog', alertdialog: 'dialog', banner: 'header', contentinfo: 'footer', search: 'search', form: 'form' })[el.getAttribute('role')];
          let d = depth;
          if (land) { const label = clean(el.getAttribute('aria-label'), 40); emit(el, land + (label ? ` "${label}"` : '') + ':', depth); d++; }
          visit(el, d);
          if (el.shadowRoot) visit(el.shadowRoot, d);
        }
      };
      if (document.body) visit(document.body, 0);
      const head = `${document.title || 'Untitled'} — ${location.href}\n${where()}`;
      if (more) lines.push(`… ${more} more (--max for more, --viewport for just what's visible)`);
      if (!lines.length) lines.push('(nothing to read or use)');
      return head + '\n\n' + lines.join('\n');
    }
    function read(o) {
      o = o || {};
      const root = o.all ? document.body : (document.querySelector('main,[role=main],article') || document.body);
      let t = (root?.innerText || '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
      const max = o.max || 6000;
      if (t.length > max) t = t.slice(0, max) + `\n… ${t.length - max} more characters (--max for more)`;
      return `${document.title || 'Untitled'} — ${location.href}\n\n${t}`;
    }
    function find(q) {
      q = q.toLowerCase();
      const out = [], seen = new Set();
      const all = document.body ? document.body.querySelectorAll('*') : [];
      for (const el of all) {
        if (SKIP.has(el.tagName) || out.length >= 20) continue;
        const own = Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' ');
        const attrs = [el.getAttribute('aria-label'), el.getAttribute('placeholder'), el.getAttribute('title'), el.getAttribute('alt'), el.value].join(' ');
        if (!(own + ' ' + attrs).toLowerCase().includes(q) || !shown(el)) continue;
        const target = el.closest(ACT) || el;
        if (seen.has(target)) continue;
        seen.add(target);
        out.push(target.matches(ACT) ? describe(target) : `[${ref(target)}] ${target.tagName.toLowerCase()} "${clean(target.innerText, 80)}"`);
      }
      return out.length ? out.join('\n') : `Nothing on the page says "${q}".`;
    }
    function short(el) {
      let s = el.tagName.toLowerCase();
      if (el.id) s += '#' + el.id;
      else if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.');
      const t = clean(el.innerText, 40); if (t) s += ` "${t}"`;
      return s;
    }
    function point(r) {
      const el = get(r);
      el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
      const b = el.getBoundingClientRect();
      const x = Math.min(Math.max(b.left + b.width / 2, 1), innerWidth - 1), y = Math.min(Math.max(b.top + b.height / 2, 1), innerHeight - 1);
      const hit = document.elementFromPoint(x, y);
      const covered = hit && hit !== el && !el.contains(hit) && !hit.contains(el) && !(el.labels && Array.from(el.labels).includes(hit)) ? short(hit) : '';
      return { x, y, covered, label: describe(el) };
    }
    function focus(o) {
      const el = get(o.ref);
      el.scrollIntoView({ block: 'center', behavior: 'instant' });
      el.focus();
      if (o.select) {
        if (typeof el.select === 'function' && el.tagName !== 'SELECT') el.select();
        else if (el.isContentEditable) { const range = document.createRange(); range.selectNodeContents(el); const sel = getSelection(); sel.removeAllRanges(); sel.addRange(range); }
      } else if (typeof el.setSelectionRange === 'function') { try { el.setSelectionRange(el.value.length, el.value.length); } catch (e) {} }
      return describe(el);
    }
    function choose(o) {
      const el = get(o.ref);
      if (el.tagName !== 'SELECT') throw new Error(`${describe(el)} isn't a list to choose from; click it instead.`);
      const want = o.value.toLowerCase();
      const opt = Array.from(el.options).find(op => op.value.toLowerCase() === want || clean(op.text).toLowerCase() === want) || Array.from(el.options).find(op => clean(op.text).toLowerCase().includes(want));
      if (!opt) throw new Error(`No option "${o.value}". Options: ${Array.from(el.options).map(op => clean(op.text, 30)).slice(0, 20).join(', ')}`);
      el.value = opt.value;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return `chose "${clean(opt.text)}" in ${describe(el)}`;
    }
    function reveal(r) { const el = get(r); el.scrollIntoView({ block: 'center', behavior: 'instant' }); return `showing ${describe(el)}; ${where()}`; }
    const viewport = () => ({ width: innerWidth, height: innerHeight, dpr: devicePixelRatio, scrollX, scrollY, page: document.documentElement.scrollHeight });
    const contains = t => (document.body?.innerText || '').toLowerCase().includes(t.toLowerCase());
    const position = () => where();
    const label = r => describe(get(r));
    Object.defineProperty(window, '__mbga', { value: { snapshot, read, find, point, focus, choose, reveal, viewport, contains, position, label } });
    })();
    """#
}

/// Runs `mbga run` scripts in JavaScriptCore, inside MBGA: each command is
/// an async function resolving to its text, `evaluate` runs a function in
/// the page and returns its value, `log` collects output.
@MainActor
final class AgentScriptRunner {
    private let commands: AgentCommands
    private let timeout: Double
    private var output: [String] = []

    init(commands: AgentCommands, timeout: Double) {
        self.commands = commands
        self.timeout = timeout
    }

    private static let prelude = #"""
    const __flags = (o = {}) => Object.entries(o).flatMap(([k, v]) => v === false || v == null ? [] : v === true ? ['--' + k] : ['--' + k, String(v)]);
    const __tab = o => o && o.tab ? ['--tab', String(o.tab)] : [];
    const mbga = (...argv) => __call(argv.map(String));
    const tabs = (o) => mbga('tabs', ...__flags(o));
    const open = async (url, o) => { const t = await mbga('open', url, ...__flags(o)); return t.split(' ')[0]; };
    const use = tab => mbga('use', tab);
    const goto = (url, o) => mbga('goto', url, ...__flags(o));
    const back = o => mbga('back', ...__flags(o));
    const reload = o => mbga('reload', ...__flags(o));
    const snapshot = o => mbga('snapshot', ...__flags(o));
    const read = o => mbga('read', ...__flags(o));
    const find = (text, o) => mbga('find', text, ...__flags(o));
    const click = (target, o) => mbga('click', target, ...__flags(o));
    const fill = (target, text, o) => mbga('fill', target, text, ...__flags(o));
    const press = (key, o) => mbga('press', key, ...__flags(o));
    const select = (target, value, o) => mbga('select', target, value, ...__flags(o));
    const scroll = (where, o) => mbga('scroll', where || 'down', ...__flags(o));
    const wait = (what, o) => typeof what === 'object' ? mbga('wait', what.gone ? 'gone' : 'text', what.gone || what.text, ...__flags(o)) : mbga('wait', String(what), ...__flags(o));
    const screenshot = o => mbga('screenshot', ...__flags(o));
    const consoleMessages = o => mbga('console', ...__flags(o));
    const sleep = ms => mbga('wait', String(ms));
    const evaluate = async (fn, ...args) => {
      const o = args.length && args[args.length - 1] && args[args.length - 1].__mbga ? args.pop() : null;
      const code = typeof fn === 'function' ? `(${fn})(...${JSON.stringify(args)})` : String(fn);
      return JSON.parse(await mbga('eval', code, ...__tab(o)));
    };
    const tab = t => ({ __mbga: true, tab: t });
    const log = (...a) => __log(a.map(v => typeof v === 'string' ? v : JSON.stringify(v, null, 1)).join(' '));
    const console = { log, info: log, warn: log, error: log };
    """#

    func run(_ argument: String) async throws -> String {
        guard let context = JSContext() else { throw AgentError("Couldn't start a script.") }
        let call: @convention(block) (JSValue) -> JSValue = { [weak self] argv in
            let words = argv.toArray()?.compactMap { $0 as? String } ?? []
            return JSValue(newPromiseIn: context) { resolve, reject in
                Task { @MainActor in
                    guard let self else { return }
                    if words.first == "run" {
                        reject?.call(withArguments: ["Scripts can't run scripts."])
                        return
                    }
                    switch await self.commands.run(words) {
                    case .success(let text): resolve?.call(withArguments: [text])
                    case .failure(let error): reject?.call(withArguments: [JSValue(newErrorFromMessage: error, in: context) as Any])
                    }
                }
            }
        }
        let collect: @convention(block) (String) -> Void = { [weak self] line in self?.output.append(line) }
        context.setObject(call, forKeyedSubscript: "__call" as NSString)
        context.setObject(collect, forKeyedSubscript: "__log" as NSString)
        context.evaluateScript(Self.prelude)
        let wrapped = "(async () => {\n\(argument)\n})()"
        guard let promise = context.evaluateScript(wrapped) else { throw AgentError("The script didn't start.") }
        if let exception = context.exception {
            throw AgentError("Script error: \(exception.toString() ?? "")")
        }
        let value: JSValue = try await withCheckedThrowingContinuation { continuation in
            var finished = false
            let fulfil: @convention(block) (JSValue) -> Void = { value in
                guard !finished else { return }
                finished = true
                continuation.resume(returning: value)
            }
            let fail: @convention(block) (JSValue) -> Void = { error in
                guard !finished else { return }
                finished = true
                let message = error.objectForKeyedSubscript("message")?.toString()
                continuation.resume(throwing: AgentError("Script error: \(message.flatMap { $0 == "undefined" ? nil : $0 } ?? error.toString() ?? "")"))
            }
            promise.invokeMethod("then", withArguments: [JSValue(object: fulfil, in: context) as Any, JSValue(object: fail, in: context) as Any])
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                guard !finished else { return }
                finished = true
                continuation.resume(throwing: AgentError("The script ran out of time (\(Int(self.timeout)) s; --timeout to allow more)."))
            }
        }
        var out = output
        if !value.isUndefined, !value.isNull {
            let json = context.objectForKeyedSubscript("JSON").invokeMethod("stringify", withArguments: [value, NSNull(), 1])
            out.append(value.isString ? value.toString() : json?.toString() ?? "")
        }
        return out.isEmpty ? "done" : out.joined(separator: "\n")
    }
}
