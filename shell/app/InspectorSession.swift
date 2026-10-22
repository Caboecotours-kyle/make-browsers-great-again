import AppKit

// The inspector: MBGA's own developer tools, a sidebar beside the page. It
// talks to the visible tab over the DevTools protocol, as Chrome's DevTools
// does, through one session per inspected tab. Each panel keeps what it
// knows about the page in a model owned by that session, so switching tabs
// and back finds the console and the requests as they were.

/// A JSON object from the DevTools protocol.
typealias JSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String? { self[key] as? String }
    func num(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func bool(_ key: String) -> Bool { (self[key] as? NSNumber)?.boolValue ?? false }
    func obj(_ key: String) -> JSON? { self[key] as? JSON }
    func list(_ key: String) -> [JSON] { self[key] as? [JSON] ?? [] }
}

struct InspectorError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Observers of one kind of change, each living as long as its owner.
@MainActor
final class Signal<Value> {
    private struct Observer {
        weak var owner: AnyObject?
        let handle: @MainActor (Value) -> Void
    }
    private var observers: [Observer] = []

    func observe(_ owner: AnyObject, _ handle: @escaping @MainActor (Value) -> Void) {
        observers.append(Observer(owner: owner, handle: handle))
    }

    func stopObserving(_ owner: AnyObject) {
        observers.removeAll { $0.owner == nil || $0.owner === owner }
    }

    func send(_ value: Value) {
        observers.removeAll { $0.owner == nil }
        for observer in observers { observer.handle(value) }
    }
}

extension Signal where Value == Void {
    func send() { send(()) }
}

/// Runs work at most once per `delay`, for views following a stream of
/// events: a busy page logs or requests hundreds of times a second.
@MainActor
final class Coalescer {
    private let delay: TimeInterval
    private var pending = false
    private let work: @MainActor () -> Void

    init(delay: TimeInterval = 0.05, _ work: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.work = work
    }

    func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = false
                self.work()
            }
        }
    }

    /// Runs now, dropping a scheduled run.
    func flush() {
        pending = false
        work()
    }
}

/// What one panel knows about one tab's page.
@MainActor
protocol InspectorModel: AnyObject {
    init(session: InspectorSession)
    /// Enables the domains it follows. Models that keep a history (the
    /// console, requests) start with the session; the rest when first shown.
    func start()
    /// Turns its domains off again as the inspector stops following the tab.
    func stop()
}

/// The inspector's connection to one tab.
@MainActor
final class InspectorSession {
    let tabID: UInt64
    private(set) weak var view: MBWebView?
    /// The page navigated (a new document in the main frame), with its URL.
    let navigated = Signal<String>()
    /// The main frame's URL, kept up to date.
    private(set) var url = ""
    private(set) var mainFrameID = ""
    /// The page's execution contexts, by id (frames' and extensions').
    private(set) var contexts: [Int: JSON] = [:]

    private struct Handler {
        weak var owner: AnyObject?
        let prefix: String
        let handle: @MainActor (String, JSON) -> Void
    }
    private var handlers: [Handler] = []
    private var models: [ObjectIdentifier: InspectorModel] = [:]
    private var order: [ObjectIdentifier] = []
    private var stopped = false

    /// Models started with the session, so nothing is missed before their
    /// panel is first shown.
    static let eagerModels: [InspectorModel.Type] = [ConsoleModel.self, NetworkModel.self, SourcesModel.self]

    init(view: MBWebView) {
        tabID = view.tabID
        self.view = view
        view.forwardsDevToolsEvents = true
        on("Page.frameNavigated", self) { [weak self] _, params in
            guard let self, let frame = params.obj("frame"), frame["parentId"] == nil else { return }
            url = frame.str("url") ?? url
            mainFrameID = frame.str("id") ?? mainFrameID
            navigated.send(url)
        }
        on("Runtime.executionContext", self) { [weak self] method, params in
            guard let self else { return }
            switch method {
            case "Runtime.executionContextCreated":
                if let context = params.obj("context"), let id = context.int("id") { contexts[id] = context }
            case "Runtime.executionContextDestroyed":
                if let id = params.int("executionContextId") { contexts[id] = nil }
            case "Runtime.executionContextsCleared":
                contexts = [:]
            default: break
            }
        }
        call("Page.enable")
        call("Runtime.enable")
        Task { [weak self] in
            guard let self, let tree = try? await send("Page.getFrameTree"),
                  let frame = tree.obj("frameTree")?.obj("frame") else { return }
            url = frame.str("url") ?? url
            mainFrameID = frame.str("id") ?? mainFrameID
        }
        for type in Self.eagerModels { _ = model(type) }
    }

    /// Stops following the tab: its domains go off and the page runs as if
    /// no one were looking.
    func stop() {
        guard !stopped else { return }
        stopped = true
        for id in order.reversed() { models[id]?.stop() }
        call("Runtime.disable")
        view?.forwardsDevToolsEvents = false
    }

    /// The panel model of `type` for this tab, started on first use.
    func model<M: InspectorModel>(_ type: M.Type) -> M {
        let id = ObjectIdentifier(type)
        if let model = models[id] as? M { return model }
        let model = M(session: self)
        models[id] = model
        order.append(id)
        model.start()
        return model
    }

    /// The model of `type` if its panel has been shown, without starting it.
    func existing<M: InspectorModel>(_ type: M.Type) -> M? {
        models[ObjectIdentifier(type)] as? M
    }

    /// Brings a panel forward (set by the store).
    var showPanel: ((InspectorPanelKind) -> Void)?
    /// Opens a page in a new tab beside this one (set by the store).
    var openTab: ((String) -> Void)?
    /// The tab's developer emulations, shared with the developer toolbar
    /// (set by the store).
    var developerState: (() -> DevTabState)?
    var updateDeveloperState: (((inout DevTabState) -> Void) -> Void)?
    /// A source location to open in Sources: a script's or stylesheet's URL
    /// and a zero-based line. Kept until Sources shows it.
    private(set) var pendingSource: (url: String, line: Int, column: Int)?
    let sourceRequested = Signal<Void>()

    /// Opens `url` at zero-based `line` in Sources.
    func revealSource(url: String, line: Int, column: Int = 0) {
        pendingSource = (url, line, column)
        showPanel?(.sources)
        sourceRequested.send()
    }

    /// Takes the location waiting for Sources.
    func takePendingSource() -> (url: String, line: Int, column: Int)? {
        defer { pendingSource = nil }
        return pendingSource
    }

    /// Selects a node in Elements, by its backend id.
    func revealNode(backendNodeID: Int) {
        showPanel?(.elements)
        model(ElementsModel.self).reveal(backendNodeID: backendNodeID)
    }

    /// Selects the element at `point`, in CSS pixels, in Elements.
    func inspect(at point: NSPoint) {
        showPanel?(.elements)
        _ = model(ElementsModel.self)
        call("DOM.getNodeForLocation", ["x": Int(point.x), "y": Int(point.y), "ignorePointerEventsNone": true]) { [weak self] result, _ in
            guard let self, let id = result?.int("backendNodeId") else { return }
            revealNode(backendNodeID: id)
        }
    }

    /// The main frame's default context, where the console evaluates.
    var mainContextID: Int? {
        let defaults = contexts.values.filter { $0.obj("auxData")?.bool("isDefault") ?? false }
        return (defaults.first { $0.obj("auxData")?.str("frameId") == mainFrameID } ?? defaults.first)?.int("id")
    }

    // MARK: Commands

    /// Sends `method`; the result, or the protocol's error.
    func send(_ method: String, _ params: JSON = [:], timeout: TimeInterval = 15) async throws -> JSON {
        try await withCheckedThrowingContinuation { continuation in
            call(method, params, timeout: timeout) { result, error in
                if let result { continuation.resume(returning: result) } else {
                    continuation.resume(throwing: InspectorError(error ?? "\(method) failed"))
                }
            }
        }
    }

    /// Sends `method`, calling `done` with the result or an error, or an
    /// error after `timeout` seconds without an answer.
    func call(_ method: String, _ params: JSON = [:], timeout: TimeInterval = 15,
              _ done: (@MainActor (JSON?, String?) -> Void)? = nil) {
        guard let view, !view.isClosing else {
            done?(nil, "The page is closed.")
            return
        }
        let json = params.isEmpty ? nil : (try? JSONSerialization.data(withJSONObject: params))
            .map { String(decoding: $0, as: UTF8.self) }
        var answered = false
        if let done {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                MainActor.assumeIsolated {
                    guard !answered else { return }
                    answered = true
                    done(nil, "The page didn't answer \(method).")
                }
            }
        }
        view.sendDevToolsCommand(method, params: json) { result, error in
            MainActor.assumeIsolated {
                guard let done, !answered else { return }
                answered = true
                if let result {
                    done((try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? JSON ?? [:], nil)
                } else {
                    done(nil, error ?? "\(method) failed")
                }
            }
        }
    }

    // MARK: Events

    /// Calls `handle` with every event whose name starts with `prefix`
    /// ("Network." or "DOM.childNodeInserted") while `owner` lives.
    func on(_ prefix: String, _ owner: AnyObject, _ handle: @escaping @MainActor (String, JSON) -> Void) {
        handlers.append(Handler(owner: owner, prefix: prefix, handle: handle))
    }

    /// An event from the engine.
    func receive(_ method: String, _ params: JSON) {
        guard !stopped else { return }
        var stale = false
        for handler in handlers {
            guard handler.owner != nil else {
                stale = true
                continue
            }
            if method.hasPrefix(handler.prefix) { handler.handle(method, params) }
        }
        if stale { handlers.removeAll { $0.owner == nil } }
    }
}

// MARK: - Remote objects

/// How the console and the debugger show a JavaScript value (a
/// Runtime.RemoteObject), in one line, as DevTools does.
enum RemoteValue {
    static func isExpandable(_ object: JSON) -> Bool {
        object.str("objectId") != nil && object.str("type") == "object" || object.str("type") == "function"
            && object.str("objectId") != nil
    }

    /// `"text"`, `42`, `{a: 1, b: "x"}`, `Array(3)`, `ƒ name()`, `div#main`.
    static func summary(_ object: JSON, quoteStrings: Bool = true, preview usePreview: Bool = true) -> String {
        let type = object.str("type") ?? "undefined"
        switch type {
        case "string":
            let value = object.str("value") ?? ""
            return quoteStrings ? "\"\(value)\"" : value
        case "number", "boolean":
            if let unserializable = object.str("unserializableValue") { return unserializable }
            return object["value"].map { "\($0)" }.map { type == "boolean" ? ($0 == "1" ? "true" : $0 == "0" ? "false" : $0) : $0 } ?? ""
        case "bigint":
            return object.str("unserializableValue") ?? ""
        case "undefined":
            return "undefined"
        case "symbol":
            return object.str("description") ?? "Symbol()"
        case "function":
            let description = object.str("description") ?? "function"
            return functionSignature(description)
        default:
            break
        }
        if object.str("subtype") == "null" { return "null" }
        if usePreview, let preview = object.obj("preview") { return summary(preview: preview, depth: 0) }
        return object.str("description") ?? object.str("className") ?? "Object"
    }

    /// `ƒ name(a, b)` from a function's source.
    static func functionSignature(_ source: String) -> String {
        let head = source.prefix { $0 != "{" && $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        var text = head
        for prefix in ["async function", "function*", "function"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            return (prefix == "async function" ? "async ƒ " : "ƒ ") + (text.isEmpty ? "()" : text)
        }
        if text.hasPrefix("class") { return text }
        if text.contains("=>") { return "ƒ " + text.replacingOccurrences(of: " =>", with: "").replacingOccurrences(of: "=>", with: "") }
        return "ƒ " + text
    }

    /// An object preview: `{a: 1, b: {…}}`, `(3) [1, 2, 3]`, `Map(2) {…}`.
    static func summary(preview: JSON, depth: Int) -> String {
        let subtype = preview.str("subtype")
        let description = preview.str("description") ?? "Object"
        let properties = preview.list("properties")
        let entries = preview.list("entries")
        let more = preview.bool("overflow") ? ", …" : ""
        if subtype == "node" { return description }
        if subtype == "array" || subtype == "typedarray" {
            let items = properties.filter { Int($0.str("name") ?? "") != nil }.map(propertyValue).joined(separator: ", ")
            let digits = description.drop { $0 != "(" }.dropFirst().prefix { $0.isNumber }
            let count = digits.isEmpty ? "" : "(\(digits)) "
            let name = description.hasPrefix("Array") ? "" : String(description.prefix { $0 != "(" }) + " "
            return "\(name)\(count)[\(items)\(more)]"
        }
        if subtype == "map" || subtype == "set" {
            let items = entries.map { entry -> String in
                let value = entry.obj("value").map { summary(preview: $0, depth: depth + 1) } ?? ""
                if let key = entry.obj("key") { return "\(summary(preview: key, depth: depth + 1)) => \(value)" }
                return value
            }
            return "\(description) {\(items.joined(separator: ", "))\(more)}"
        }
        if subtype == "error" || subtype == "regexp" || subtype == "date" { return description }
        if preview.str("type") != "object" { return description }
        let items = properties.map { "\($0.str("name") ?? ""): \(propertyValue($0))" }.joined(separator: ", ")
        let name = description == "Object" ? "" : description + " "
        return "\(name){\(items)\(more)}"
    }

    private static func propertyValue(_ property: JSON) -> String {
        if let nested = property.obj("valuePreview") { return summary(preview: nested, depth: 1) }
        let value = property.str("value") ?? ""
        switch property.str("type") {
        case "string": return "\"\(value)\""
        case "function": return "ƒ"
        case "object":
            if property.str("subtype") == "null" { return "null" }
            if property.str("subtype") == "array" { return value }
            return value == "Object" ? "{…}" : value
        case "accessor": return "(…)"
        default: return value
        }
    }

    /// The colour DevTools gives a value of this type.
    static func color(_ object: JSON) -> NSColor {
        switch object.str("type") {
        case "string": return InspectorTheme.string
        case "number", "bigint", "boolean": return InspectorTheme.number
        case "undefined": return .tertiaryLabelColor
        case "symbol": return InspectorTheme.string
        case "function": return InspectorTheme.keyword
        default: return object.str("subtype") == "null" ? .tertiaryLabelColor : .labelColor
        }
    }
}
