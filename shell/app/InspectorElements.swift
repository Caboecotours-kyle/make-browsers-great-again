import AppKit

// Elements: the page's DOM as a live tree, and the selected element's
// styles, computed values and box model, event listeners, properties and
// accessibility, all editable where DevTools allows.

/// A node of the page's DOM as DevTools reports it.
@MainActor
final class DOMNode {
    let id: Int
    let backendID: Int
    let type: Int
    let name: String
    let localName: String
    var value: String
    var attributes: [(name: String, value: String)]
    var childCount: Int
    /// Nil until fetched.
    var children: [DOMNode]?
    weak var parent: DOMNode?
    var shadowRoots: [DOMNode] = []
    var contentDocument: DOMNode?
    var templateContent: DOMNode?
    var before: DOMNode?
    var after: DOMNode?
    let pseudoType: String?
    let shadowRootType: String?
    let frameID: String?

    init(_ json: JSON) {
        id = json.int("nodeId") ?? 0
        backendID = json.int("backendNodeId") ?? 0
        type = json.int("nodeType") ?? 1
        name = json.str("nodeName") ?? ""
        localName = json.str("localName") ?? ""
        value = json.str("nodeValue") ?? ""
        let flat = json["attributes"] as? [String] ?? []
        attributes = stride(from: 0, to: flat.count - 1, by: 2).map { (flat[$0], flat[$0 + 1]) }
        childCount = json.int("childNodeCount") ?? 0
        pseudoType = json.str("pseudoType")
        shadowRootType = json.str("shadowRootType")
        frameID = json.str("frameId")
    }

    var isElement: Bool { type == 1 }
    var isText: Bool { type == 3 }

    func attribute(_ name: String) -> String? { attributes.first { $0.name == name }?.value }

    /// What the tree shows under it: shadow roots, a frame's document,
    /// ::before, the children (without blank text) and ::after.
    var shownChildren: [DOMNode] {
        var nodes = shadowRoots
        if let templateContent { nodes.append(templateContent) }
        if let contentDocument { nodes.append(contentDocument) }
        if let before { nodes.append(before) }
        nodes += (children ?? []).filter { !($0.isText && $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        if let after { nodes.append(after) }
        return nodes
    }

    /// Whether it has children to show or fetch.
    var hasChildren: Bool {
        if let inline = inlineText, !inline.isEmpty { return false }
        return !shownChildren.isEmpty || (children == nil && childCount > 0)
    }

    /// An element holding only a short text shows it on its own line.
    var inlineText: String? {
        guard isElement, shadowRoots.isEmpty, contentDocument == nil, before == nil, after == nil,
              let children, children.count == 1, children[0].isText else { return nil }
        let text = children[0].value
        return text.count <= 80 && !text.contains("\n") ? text : nil
    }

    /// `div#main.card.primary`, for breadcrumbs and links.
    var shortName: String {
        if let pseudoType { return "::\(pseudoType)" }
        guard isElement else { return name.lowercased() }
        var text = localName.isEmpty ? name.lowercased() : localName
        if let id = attribute("id"), !id.isEmpty { text += "#\(id)" }
        if let classes = attribute("class") {
            text += classes.split(separator: " ").prefix(3).map { ".\($0)" }.joined()
        }
        return text
    }

    /// Every node under it already known, it included.
    func walk(_ visit: (DOMNode) -> Void) {
        visit(self)
        for child in shadowRoots { child.walk(visit) }
        templateContent?.walk(visit)
        contentDocument?.walk(visit)
        before?.walk(visit)
        after?.walk(visit)
        for child in children ?? [] { child.walk(visit) }
    }
}

/// An expanded element's closing tag, its own row in the tree.
@MainActor
final class ClosingTag {
    let node: DOMNode
    init(_ node: DOMNode) { self.node = node }
}

@MainActor
final class ElementsModel: InspectorModel {
    private weak var session: InspectorSession?
    private(set) var document: DOMNode?
    private var nodes: [Int: DOMNode] = [:]
    private(set) var selected: DOMNode?
    /// Stylesheets by id: their URLs for the styles' links.
    private(set) var styleSheets: [String: JSON] = [:]
    /// The whole tree changed (a new document).
    let reset = Signal<Void>()
    /// A node's children or attributes changed.
    let nodeChanged = Signal<DOMNode>()
    let selectionChanged = Signal<Void>()
    /// The selected element's styles may have changed.
    let stylesChanged = Signal<Void>()
    /// A node to select and scroll to.
    let revealed = Signal<DOMNode>()
    private var started = false
    private var waitingReveal: Int?
    private var childWaiters: [Int: [@MainActor () -> Void]] = [:]

    init(session: InspectorSession) { self.session = session }

    func start() {
        guard let session, !started else { return }
        started = true
        session.on("DOM.", self) { [weak self] method, params in self?.domEvent(method, params) }
        session.on("CSS.", self) { [weak self] method, params in
            guard let self else { return }
            switch method {
            case "CSS.styleSheetAdded":
                if let header = params.obj("header"), let id = header.str("styleSheetId") { styleSheets[id] = header }
            case "CSS.styleSheetRemoved":
                if let id = params.str("styleSheetId") { styleSheets[id] = nil }
            case "CSS.styleSheetChanged", "CSS.mediaQueryResultChanged", "CSS.fontsUpdated":
                stylesChanged.send()
            default: break
            }
        }
        session.call("DOM.enable")
        session.call("CSS.enable")
        session.call("Overlay.enable")
        fetchDocument()
    }

    func stop() {
        session?.call("Overlay.hideHighlight")
        session?.call("CSS.disable")
        session?.call("Overlay.disable")
        session?.call("DOM.disable")
    }

    private func fetchDocument() {
        guard let session else { return }
        session.call("DOM.getDocument", ["depth": 3]) { [weak self] result, _ in
            guard let self, let root = result?.obj("root") else { return }
            nodes = [:]
            let document = build(root, parent: nil)
            self.document = document
            let previous = selected
            selected = nil
            reset.send()
            // Select <body>, or what was selected before if it's still there.
            if let waitingReveal {
                self.waitingReveal = nil
                reveal(backendNodeID: waitingReveal)
            } else if let previous, let again = document.find({ $0.backendID == previous.backendID }) {
                select(again)
                revealed.send(again)
            } else if let body = document.find({ $0.localName == "body" }) {
                select(body)
                revealed.send(body)
            }
        }
    }

    @discardableResult
    private func build(_ json: JSON, parent: DOMNode?) -> DOMNode {
        let node = DOMNode(json)
        node.parent = parent
        nodes[node.id] = node
        if let children = json["children"] as? [JSON] { node.children = children.map { build($0, parent: node) } }
        node.shadowRoots = json.list("shadowRoots").map { build($0, parent: node) }
        node.contentDocument = json.obj("contentDocument").map { build($0, parent: node) }
        node.templateContent = json.obj("templateContent").map { build($0, parent: node) }
        for pseudo in json.list("pseudoElements") {
            switch pseudo.str("pseudoType") {
            case "before": node.before = build(pseudo, parent: node)
            case "after": node.after = build(pseudo, parent: node)
            default: break
            }
        }
        return node
    }

    func node(_ id: Int) -> DOMNode? { nodes[id] }

    private func domEvent(_ method: String, _ params: JSON) {
        switch method {
        case "DOM.documentUpdated":
            fetchDocument()
        case "DOM.setChildNodes":
            guard let parent = params.int("parentId").flatMap({ nodes[$0] }) else { return }
            parent.children = params.list("nodes").map { build($0, parent: parent) }
            parent.childCount = parent.children?.count ?? 0
            nodeChanged.send(parent)
            for waiter in childWaiters.removeValue(forKey: parent.id) ?? [] { waiter() }
        case "DOM.childNodeInserted":
            guard let parent = params.int("parentNodeId").flatMap({ nodes[$0] }), let json = params.obj("node") else { return }
            let node = build(json, parent: parent)
            parent.childCount += 1
            if var children = parent.children {
                let previous = params.int("previousNodeId") ?? 0
                let index = children.firstIndex { $0.id == previous }.map { $0 + 1 } ?? 0
                children.insert(node, at: min(index, children.count))
                parent.children = children
            }
            nodeChanged.send(parent)
        case "DOM.childNodeRemoved":
            guard let parent = params.int("parentNodeId").flatMap({ nodes[$0] }), let id = params.int("nodeId") else { return }
            parent.children?.removeAll { $0.id == id }
            parent.childCount = max(parent.childCount - 1, 0)
            if let removed = nodes.removeValue(forKey: id), let selected, isAncestor(removed, of: selected) {
                select(parent)
            }
            nodeChanged.send(parent)
        case "DOM.childNodeCountUpdated":
            guard let node = params.int("nodeId").flatMap({ nodes[$0] }) else { return }
            node.childCount = params.int("childNodeCount") ?? node.childCount
            nodeChanged.send(node)
        case "DOM.attributeModified":
            guard let node = params.int("nodeId").flatMap({ nodes[$0] }), let name = params.str("name") else { return }
            let value = params.str("value") ?? ""
            if let index = node.attributes.firstIndex(where: { $0.name == name }) {
                node.attributes[index].value = value
            } else {
                node.attributes.append((name, value))
            }
            nodeChanged.send(node)
            if node === selected { stylesChanged.send() }
        case "DOM.attributeRemoved":
            guard let node = params.int("nodeId").flatMap({ nodes[$0] }), let name = params.str("name") else { return }
            node.attributes.removeAll { $0.name == name }
            nodeChanged.send(node)
            if node === selected { stylesChanged.send() }
        case "DOM.characterDataModified":
            guard let node = params.int("nodeId").flatMap({ nodes[$0] }) else { return }
            node.value = params.str("characterData") ?? ""
            if let parent = node.parent { nodeChanged.send(parent) }
            nodeChanged.send(node)
        case "DOM.inlineStyleInvalidated":
            let ids = params["nodeIds"] as? [Int] ?? []
            if let selected, ids.contains(selected.id) { stylesChanged.send() }
        case "DOM.shadowRootPushed":
            guard let host = params.int("hostId").flatMap({ nodes[$0] }), let root = params.obj("root") else { return }
            host.shadowRoots.append(build(root, parent: host))
            nodeChanged.send(host)
        case "DOM.shadowRootPopped":
            guard let host = params.int("hostId").flatMap({ nodes[$0] }), let id = params.int("rootId") else { return }
            host.shadowRoots.removeAll { $0.id == id }
            nodeChanged.send(host)
        case "DOM.pseudoElementAdded":
            guard let parent = params.int("parentId").flatMap({ nodes[$0] }), let json = params.obj("pseudoElement") else { return }
            let node = build(json, parent: parent)
            if node.pseudoType == "before" { parent.before = node } else if node.pseudoType == "after" { parent.after = node }
            nodeChanged.send(parent)
        case "DOM.pseudoElementRemoved":
            guard let parent = params.int("parentId").flatMap({ nodes[$0] }), let id = params.int("pseudoElementId") else { return }
            if parent.before?.id == id { parent.before = nil }
            if parent.after?.id == id { parent.after = nil }
            nodeChanged.send(parent)
        default:
            break
        }
    }

    private func isAncestor(_ ancestor: DOMNode, of node: DOMNode) -> Bool {
        var current: DOMNode? = node
        while let next = current {
            if next === ancestor { return true }
            current = next.parent
        }
        return false
    }

    // MARK: Actions

    /// Fetches `node`'s children if they aren't known, then calls `done`.
    func loadChildren(_ node: DOMNode, _ done: @escaping @MainActor () -> Void) {
        guard node.children == nil, node.childCount > 0 else { return done() }
        let first = childWaiters[node.id] == nil
        childWaiters[node.id, default: []].append(done)
        if first { session?.call("DOM.requestChildNodes", ["nodeId": node.id, "depth": 1]) }
    }

    func select(_ node: DOMNode?) {
        guard node !== selected else { return }
        selected = node
        if let node, node.id > 0 { session?.call("DOM.setInspectedNode", ["nodeId": node.id]) }
        selectionChanged.send()
    }

    /// Selects the node with `backendNodeID` (picked in the page, or from
    /// the console), fetching its ancestors first.
    func reveal(backendNodeID: Int) {
        guard let session else { return }
        guard document != nil else {
            waitingReveal = backendNodeID
            return
        }
        session.call("DOM.pushNodesByBackendIdsToFrontend", ["backendNodeIds": [backendNodeID]]) { [weak self] result, _ in
            guard let self, let id = (result?["nodeIds"] as? [Int])?.first, let node = nodes[id] else { return }
            select(node)
            revealed.send(node)
        }
    }

    func highlight(_ node: DOMNode?) {
        guard let session else { return }
        guard let node, node.id > 0, node.isElement || node.pseudoType != nil || node.isText else {
            session.call("Overlay.hideHighlight")
            return
        }
        session.call("Overlay.highlightNode", ["nodeId": node.id, "highlightConfig": Self.highlightConfig])
    }

    static let highlightConfig: JSON = {
        func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: Double) -> JSON { ["r": r, "g": g, "b": b, "a": a] }
        return ["showInfo": true, "showStyles": true, "showRulers": false, "showExtensionLines": false,
                "contentColor": rgba(111, 168, 220, 0.66), "paddingColor": rgba(147, 196, 125, 0.55),
                "borderColor": rgba(255, 229, 153, 0.66), "marginColor": rgba(246, 178, 107, 0.66)]
    }()

    /// Runs a DOM edit as one undoable step.
    func edit(_ method: String, _ params: JSON, _ done: (@MainActor (JSON?, String?) -> Void)? = nil) {
        guard let session else { return }
        session.call(method, params) { result, error in
            session.call("DOM.markUndoableState")
            done?(result, error)
        }
    }

    func undo() { session?.call("DOM.undo") }
    func redo() { session?.call("DOM.redo") }

    /// The node as a JavaScript object, for the console and Properties.
    func resolve(_ node: DOMNode) async -> JSON? {
        guard let session else { return nil }
        return try? await session.send("DOM.resolveNode", ["nodeId": node.id, "objectGroup": "elements"]).obj("object")
    }

    func callOn(_ node: DOMNode, _ function: String, returnByValue: Bool = true) async -> Any? {
        guard let session, let object = await resolve(node), let id = object.str("objectId") else { return nil }
        let result = try? await session.send("Runtime.callFunctionOn", ["objectId": id, "functionDeclaration": function,
                                                                         "returnByValue": returnByValue])
        return result?.obj("result")?["value"]
    }

    // MARK: Search

    private var searchID: String?
    private(set) var searchResults: [Int] = []

    /// Finds nodes by text, selector or XPath; calls back with how many.
    func search(_ query: String, _ done: @escaping @MainActor (Int) -> Void) {
        guard let session else { return }
        if let searchID { session.call("DOM.discardSearchResults", ["searchId": searchID]) }
        searchID = nil
        searchResults = []
        guard !query.isEmpty else { return done(0) }
        session.call("DOM.performSearch", ["query": query, "includeUserAgentShadowDOM": false]) { [weak self] result, _ in
            guard let self, let id = result?.str("searchId"), let count = result?.int("resultCount") else { return done(0) }
            searchID = id
            guard count > 0 else { return done(0) }
            session.call("DOM.getSearchResults", ["searchId": id, "fromIndex": 0, "toIndex": min(count, 500)]) { [weak self] result, _ in
                self?.searchResults = result?["nodeIds"] as? [Int] ?? []
                done(count)
            }
        }
    }

    func path(to node: DOMNode) -> [DOMNode] {
        var path: [DOMNode] = []
        var current: DOMNode? = node
        while let next = current {
            path.insert(next, at: 0)
            current = next.parent
        }
        return path
    }
}

private extension DOMNode {
    func find(_ test: (DOMNode) -> Bool) -> DOMNode? {
        var found: DOMNode?
        walk { node in if found == nil, test(node) { found = node } }
        return found
    }
}

// MARK: - Tree text

@MainActor
enum DOMText {
    static let font = InspectorTheme.mono(11)

    /// `<div id="main" class="card">…</div>` as DevTools draws a row.
    static func row(_ node: DOMNode, expanded: Bool) -> NSAttributedString {
        let out = NSMutableAttributedString()
        switch node.type {
        case 1:
            if let pseudo = node.pseudoType { return out.add("::\(pseudo)", InspectorTheme.tag, font: font) }
            let name = node.localName.isEmpty ? node.name.lowercased() : node.localName
            out.add("<", InspectorTheme.tag, font: font).add(name, InspectorTheme.tag, font: font)
            for (attribute, value) in node.attributes {
                out.add(" ", .labelColor, font: font).add(attribute, InspectorTheme.attribute, font: font)
                out.add("=\"", .secondaryLabelColor, font: font)
                out.add(value.clipped(attribute == "style" || attribute == "d" ? 120 : 300).oneLine, InspectorTheme.string, font: font)
                out.add("\"", .secondaryLabelColor, font: font)
            }
            out.add(">", InspectorTheme.tag, font: font)
            if let inline = node.inlineText {
                out.add(inline, .labelColor, font: font)
                out.add("</\(name)>", InspectorTheme.tag, font: font)
            } else if !expanded, node.hasChildren {
                out.add("…", .secondaryLabelColor, font: font).add("</\(name)>", InspectorTheme.tag, font: font)
            } else if !node.hasChildren, !voidElements.contains(name) {
                out.add("</\(name)>", InspectorTheme.tag, font: font)
            }
        case 3:
            out.add("\"\(node.value.trimmingCharacters(in: .whitespacesAndNewlines).clipped(400).oneLine)\"", .labelColor, font: font)
        case 8:
            out.add("<!--\(node.value.clipped(300).oneLine)-->", InspectorTheme.comment, font: font)
        case 9:
            out.add("#document", .secondaryLabelColor, font: font)
            if node.parent != nil, let frame = node.frameID { out.add("  (frame \(frame.prefix(6)))", .tertiaryLabelColor, font: font) }
        case 10:
            out.add("<!DOCTYPE \(node.name)>", InspectorTheme.comment, font: font)
        case 11:
            out.add(node.shadowRootType.map { "#shadow-root (\($0))" } ?? "#document-fragment", .secondaryLabelColor, font: font)
        default:
            out.add(node.name, .secondaryLabelColor, font: font)
        }
        return out
    }

    static func closing(_ node: DOMNode) -> NSAttributedString {
        let name = node.localName.isEmpty ? node.name.lowercased() : node.localName
        return NSMutableAttributedString().add("</\(name)>", InspectorTheme.tag, font: font)
    }

    static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
                                             "param", "source", "track", "wbr"]
}

// MARK: - Panel

final class ElementsPanel: InspectorPanelView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let toolbar = InspectorToolbar()
    private let search = InspectorFilterField(placeholder: "Find by text, selector or XPath")
    private let searchCount = Label.make("", size: 11, color: .secondaryLabelColor)
    private let tree = DOMOutlineView()
    private let treeScroll = NSScrollView()
    private let crumbs = BreadcrumbBar()
    private let treePane = FlippedView()
    private let sidebar = ElementSidebar()
    private lazy var split = InspectorSplitView(treePane, sidebar, vertical: false, key: "elements", fraction: 0.5, minimum: 90)
    private var model: ElementsModel?
    private var closingTags: [Int: ClosingTag] = [:]
    private var searchIndex = 0
    private var suppressSelection = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        search.onChange = { [weak self] text in self?.find(text) }
        search.target = self
        search.action = #selector(searchAction)
        toolbar.add(search, width: nil)
        toolbar.add(searchCount, width: 56)
        let undo = InspectorButton("arrow.uturn.backward", tip: "Undo  ⌘Z") { [weak self] in self?.model?.undo() }
        let redo = InspectorButton("arrow.uturn.forward", tip: "Redo  ⇧⌘Z") { [weak self] in self?.model?.redo() }
        toolbar.add(undo, width: 24)
        toolbar.add(redo, width: 24)
        addSubview(toolbar)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("node"))
        column.resizingMask = .autoresizingMask
        tree.addTableColumn(column)
        tree.outlineTableColumn = column
        tree.headerView = nil
        tree.style = .plain
        tree.rowHeight = 18
        tree.indentationPerLevel = 12
        tree.backgroundColor = .clear
        tree.focusRingType = .none
        tree.intercellSpacing = .zero
        tree.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tree.autoresizesOutlineColumn = false
        tree.dataSource = self
        tree.delegate = self
        tree.target = self
        tree.doubleAction = #selector(doubleClicked)
        tree.menuForRow = { [weak self] row in self?.menu(row) }
        tree.onKey = { [weak self] event in self?.key(event) ?? false }
        tree.onHover = { [weak self] row in self?.hover(row) }
        treeScroll.documentView = tree
        treeScroll.hasVerticalScroller = true
        treeScroll.hasHorizontalScroller = true
        treeScroll.autohidesScrollers = true
        treeScroll.drawsBackground = false
        treeScroll.borderType = .noBorder
        treePane.addSubview(treeScroll)
        crumbs.onSelect = { [weak self] node in
            self?.model?.select(node)
            self?.revealRow(node)
        }
        treePane.addSubview(crumbs)
        addSubview(split)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        toolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: InspectorToolbar.height)
        split.frame = NSRect(x: 0, y: toolbar.frame.maxY, width: bounds.width, height: bounds.height - toolbar.frame.maxY)
        split.layoutSubtreeIfNeeded()
        let pane = treePane.bounds
        crumbs.frame = NSRect(x: 0, y: pane.height - BreadcrumbBar.height, width: pane.width, height: BreadcrumbBar.height)
        treeScroll.frame = NSRect(x: 0, y: 0, width: pane.width, height: max(pane.height - BreadcrumbBar.height, 0))
        // The split moves its divider after this; they follow the pane.
        crumbs.autoresizingMask = [.width, .minYMargin]
        treeScroll.autoresizingMask = [.width, .height]
        sizeTreeColumn()
    }

    /// Rows are as wide as their text, so long tags scroll sideways.
    private func sizeTreeColumn() {
        guard let column = tree.tableColumns.first else { return }
        let width = max(treeScroll.contentSize.width, column.width)
        if column.width < width { column.width = width }
    }

    override func sessionChanged() {
        for signal in [model?.reset, model?.selectionChanged].compactMap({ $0 }) { signal.stopObserving(self) }
        model?.nodeChanged.stopObserving(self)
        model?.revealed.stopObserving(self)
        model = isShown ? session?.model(ElementsModel.self) : nil
        observe()
    }

    override func panelDidAppear() {
        if model == nil, let session {
            model = session.model(ElementsModel.self)
            observe()
        }
        reloadTree()
    }

    override func panelDidDisappear() {
        model?.highlight(nil)
    }

    override func focusFilter() { window?.makeFirstResponder(search) }

    private func observe() {
        closingTags = [:]
        sidebar.bind(model, session: session)
        guard let model else {
            tree.reloadData()
            crumbs.show([])
            return
        }
        model.reset.observe(self) { [weak self] in self?.reloadTree() }
        model.nodeChanged.observe(self) { [weak self] node in self?.reload(node) }
        model.selectionChanged.observe(self) { [weak self] in self?.selectionChanged() }
        model.revealed.observe(self) { [weak self] node in self?.revealRow(node) }
        reloadTree()
    }

    private func reloadTree() {
        closingTags = [:]
        tree.reloadData()
        guard let document = model?.document else { return }
        // Open down to <body>, as DevTools does.
        for child in document.shownChildren {
            tree.expandItem(child)
            if child.localName == "html" {
                for grandchild in child.shownChildren where grandchild.localName == "body" { expand(grandchild) }
            }
        }
        if let selected = model?.selected { revealRow(selected) }
        selectionChanged()
    }

    private func reload(_ node: DOMNode) {
        let row = tree.row(forItem: node)
        guard row >= 0 || node === model?.document else { return }
        let expanded = tree.isItemExpanded(node)
        tree.reloadItem(node === model?.document ? nil : node, reloadChildren: true)
        if expanded, row >= 0, !tree.isItemExpanded(node) { tree.expandItem(node) }
        if let selected = model?.selected, tree.row(forItem: selected) >= 0, tree.selectedRow != tree.row(forItem: selected) {
            selectRow(of: selected)
        }
        sizeTreeColumn()
    }

    private func selectionChanged() {
        guard let model else { return }
        if let selected = model.selected { selectRow(of: selected) }
        crumbs.show(model.selected.map { model.path(to: $0).filter { $0.type == 1 || $0.type == 11 } } ?? [])
        sidebar.selectionChanged()
    }

    private func selectRow(of node: DOMNode) {
        let row = tree.row(forItem: node)
        guard row >= 0 else { return }
        suppressSelection = true
        tree.selectRowIndexes([row], byExtendingSelection: false)
        suppressSelection = false
    }

    /// Expands its ancestors and scrolls it into the middle.
    private func revealRow(_ node: DOMNode) {
        guard let model else { return }
        for ancestor in model.path(to: node).dropLast() where ancestor !== model.document { tree.expandItem(ancestor) }
        let row = tree.row(forItem: node)
        guard row >= 0 else { return }
        selectRow(of: node)
        let visible = treeScroll.contentView.bounds
        let rect = tree.rect(ofRow: row)
        if !visible.contains(rect) {
            treeScroll.contentView.scroll(to: NSPoint(x: max(rect.minX - 40 + CGFloat(tree.level(forRow: row)) * 0, 0) * 0,
                                                      y: max(rect.midY - visible.height / 2, 0)))
            treeScroll.reflectScrolledClipView(treeScroll.contentView)
        }
    }

    private func expand(_ node: DOMNode) {
        guard let model else { return }
        if node.children == nil, node.childCount > 0 {
            model.loadChildren(node) { [weak self] in
                self?.tree.reloadItem(node, reloadChildren: true)
                self?.tree.expandItem(node)
            }
        } else {
            tree.expandItem(node)
        }
    }

    // MARK: Search

    private func find(_ query: String) {
        searchIndex = 0
        model?.search(query) { [weak self] count in
            guard let self else { return }
            searchCount.stringValue = query.isEmpty ? "" : count == 0 ? "No match" : "1 of \(count)"
            showSearchResult()
        }
    }

    @objc private func searchAction() {
        guard let results = model?.searchResults, !results.isEmpty else { return }
        searchIndex = (searchIndex + (NSEvent.modifierFlags.contains(.shift) ? -1 : 1) + results.count) % results.count
        searchCount.stringValue = "\(searchIndex + 1) of \(results.count)"
        showSearchResult()
    }

    private func showSearchResult() {
        guard let model, model.searchResults.indices.contains(searchIndex) else { return }
        let id = model.searchResults[searchIndex]
        // Results arrive with their ancestors pushed; a moment later they're known.
        if let node = model.node(id) {
            model.select(node)
            revealRow(node)
        }
    }

    // MARK: Interaction

    private func node(atRow row: Int) -> DOMNode? {
        let item = tree.item(atRow: row)
        return item as? DOMNode ?? (item as? ClosingTag)?.node
    }

    private func hover(_ row: Int?) {
        model?.highlight(row.flatMap { node(atRow: $0) })
    }

    @objc private func doubleClicked() {
        let row = tree.clickedRow
        guard row >= 0, let node = node(atRow: row) else { return }
        if node.isText {
            editText(node)
        } else if node.isElement, node.pseudoType == nil {
            editHTML(node)
        }
    }

    private func key(_ event: NSEvent) -> Bool {
        guard let model, let node = model.selected else { return false }
        let command = event.modifierFlags.contains(.command)
        switch event.charactersIgnoringModifiers {
        case "z" where command:
            if event.modifierFlags.contains(.shift) { model.redo() } else { model.undo() }
            return true
        case "c" where command:
            copyOuterHTML(node)
            return true
        case "h" where !command:
            toggleHidden(node)
            return true
        default:
            break
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            model.edit("DOM.removeNode", ["nodeId": node.id])
            return true
        }
        if event.keyCode == 36, node.isElement {
            editHTML(node)
            return true
        }
        return false
    }

    private func menu(_ row: Int) -> NSMenu? {
        guard let model, let node = node(atRow: row) else { return nil }
        model.select(node)
        let menu = NSMenu()
        if node.isElement, node.pseudoType == nil {
            menu.add("Add Attribute") { [weak self] in self?.editAttribute(node, name: nil) }
            if !node.attributes.isEmpty {
                menu.addSubmenu(titled: "Edit Attribute") { sub in
                    for attribute in node.attributes {
                        sub.add(attribute.name) { [weak self] in self?.editAttribute(node, name: attribute.name) }
                    }
                }
            }
            menu.add("Edit as HTML") { [weak self] in self?.editHTML(node) }
            menu.add("Duplicate Element") {
                guard let parent = node.parent else { return }
                let next = parent.children?.drop { $0 !== node }.dropFirst().first
                var params: JSON = ["nodeId": node.id, "targetNodeId": parent.id]
                if let next { params["insertBeforeNodeId"] = next.id }
                model.edit("DOM.copyTo", params)
            }
            menu.add("Delete Element") { model.edit("DOM.removeNode", ["nodeId": node.id]) }
            menu.addItem(.separator())
            menu.addSubmenu(titled: "Copy") { sub in
                sub.add("Copy Element") { [weak self] in self?.copyOuterHTML(node) }
                sub.add("Copy Selector") { [weak self] in self?.copySelector(node, kind: "selector") }
                sub.add("Copy JS Path") { [weak self] in self?.copySelector(node, kind: "js") }
                sub.add("Copy XPath") { [weak self] in self?.copySelector(node, kind: "xpath") }
                sub.add("Copy Styles") {
                    Task {
                        let text = await model.callOn(node, """
                            function(){ const s = getComputedStyle(this); let out = ''; for (const p of s) out += p + ': ' + s.getPropertyValue(p) + ';\\n'; return out }
                            """) as? String
                        if let text { Format.copy(text) }
                    }
                }
            }
            menu.addSubmenu(titled: "Force State") { [weak self] sub in
                for state in ["hover", "active", "focus", "focus-within", "focus-visible", "visited", "target"] {
                    let on = self?.sidebar.forcedStates[node.id]?.contains(state) ?? false
                    sub.add(":\(state)", state: on) { self?.sidebar.toggleForcedState(state, on: node) }
                }
            }
            menu.add(sidebar.hiddenNodes.contains(node.id) ? "Show Element" : "Hide Element") { [weak self] in self?.toggleHidden(node) }
            menu.addSubmenu(titled: "Break On") { sub in
                for (title, type) in [("Subtree Modifications", "subtree-modified"), ("Attribute Modifications", "attribute-modified"),
                                      ("Node Removal", "node-removed")] {
                    sub.add(title) { [weak self] in
                        self?.session?.call("Debugger.enable")
                        self?.session?.call("DOMDebugger.setDOMBreakpoint", ["nodeId": node.id, "type": type])
                    }
                }
                sub.addItem(.separator())
                sub.add("Remove All") { [weak self] in
                    for type in ["subtree-modified", "attribute-modified", "node-removed"] {
                        self?.session?.call("DOMDebugger.removeDOMBreakpoint", ["nodeId": node.id, "type": type])
                    }
                }
            }
            menu.addItem(.separator())
            menu.add("Scroll into View") { [weak self] in self?.session?.call("DOM.scrollIntoViewIfNeeded", ["nodeId": node.id]) }
            menu.add("Focus") { Task { _ = await model.callOn(node, "function(){ this.focus() }") } }
            menu.add("Store as Global Variable") { [weak self] in self?.storeGlobal(node) }
            if node.localName == "a" || node.localName == "img" || node.localName == "script" || node.localName == "link",
               let link = node.attribute("href") ?? node.attribute("src") {
                menu.add("Copy Link Address") { Format.copy(link) }
            }
        } else if node.isText {
            menu.add("Edit Text") { [weak self] in self?.editText(node) }
            menu.add("Delete") { model.edit("DOM.removeNode", ["nodeId": node.id]) }
        } else if node.type == 8 {
            menu.add("Delete Comment") { model.edit("DOM.removeNode", ["nodeId": node.id]) }
        }
        if node.hasChildren {
            menu.addItem(.separator())
            menu.add("Expand Recursively") { [weak self] in self?.expandRecursively(node) }
            menu.add("Collapse Children") { [weak self] in
                guard let self else { return }
                for child in node.shownChildren { tree.collapseItem(child, collapseChildren: true) }
            }
        }
        return menu
    }

    private func expandRecursively(_ node: DOMNode) {
        session?.call("DOM.requestChildNodes", ["nodeId": node.id, "depth": -1])
        // The children arrive as events; expand once they have.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.tree.expandItem(node, expandChildren: true)
        }
    }

    private func toggleHidden(_ node: DOMNode) {
        sidebar.toggleHidden(node)
    }

    private func copyOuterHTML(_ node: DOMNode) {
        session?.call("DOM.getOuterHTML", ["nodeId": node.id]) { result, _ in
            if let html = result?.str("outerHTML") { Format.copy(html) }
        }
    }

    private func copySelector(_ node: DOMNode, kind: String) {
        guard let model else { return }
        let function = """
            function(kind){
              const el = this;
              if (kind === 'xpath') {
                const parts = [];
                for (let n = el; n && n.nodeType === 1; n = n.parentNode) {
                  if (n.id) { parts.unshift('//*[@id="' + n.id + '"]'); return parts.join('/') }
                  let i = 1; for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === n.localName) i++;
                  parts.unshift(n.localName + '[' + i + ']');
                }
                return '/' + parts.join('/');
              }
              const parts = [];
              for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
                if (n.id && /^[A-Za-z][\\w-]*$/.test(n.id)) { parts.unshift('#' + n.id); break }
                let part = n.localName;
                const parent = n.parentElement;
                if (parent) {
                  const same = [...parent.children].filter(c => c.localName === n.localName);
                  if (same.length > 1) part += ':nth-child(' + ([...parent.children].indexOf(n) + 1) + ')';
                }
                parts.unshift(part);
              }
              const selector = parts.join(' > ');
              return kind === 'js' ? 'document.querySelector(' + JSON.stringify(selector) + ')' : selector;
            }
            """
        Task {
            guard let object = await model.resolve(node), let id = object.str("objectId"), let session else { return }
            let result = try? await session.send("Runtime.callFunctionOn", [
                "objectId": id, "functionDeclaration": function, "arguments": [["value": kind]], "returnByValue": true,
            ])
            if let text = result?.obj("result")?.str("value") { Format.copy(text) }
        }
    }

    private func storeGlobal(_ node: DOMNode) {
        guard let model, let session else { return }
        Task {
            guard let object = await model.resolve(node), let id = object.str("objectId") else { return }
            let result = try? await session.send("Runtime.callFunctionOn", [
                "objectId": id, "returnByValue": true,
                "functionDeclaration": "function(){ let i = 1; while (('temp' + i) in globalThis) i++; globalThis['temp' + i] = this; return 'temp' + i }",
            ])
            if let name = result?.obj("result")?.str("value") {
                session.model(ConsoleModel.self).evaluate(name)
                session.showPanel?(.console)
            }
        }
    }

    // MARK: Editing

    private func editHTML(_ node: DOMNode) {
        guard let model, let row = rowView(for: node) else { return }
        session?.call("DOM.getOuterHTML", ["nodeId": node.id]) { [weak self] result, _ in
            guard let self, let html = result?.str("outerHTML") else { return }
            TextEditPopover.show(title: "Edit as HTML", text: html, language: .html, relativeTo: row, of: tree) { text in
                model.edit("DOM.setOuterHTML", ["nodeId": node.id, "outerHTML": text])
            }
        }
    }

    private func editText(_ node: DOMNode) {
        guard let model, let row = rowView(for: node) else { return }
        TextEditPopover.show(title: "Edit Text", text: node.value, language: .plain, relativeTo: row, of: tree) { text in
            model.edit("DOM.setNodeValue", ["nodeId": node.id, "value": text])
        }
    }

    /// Edits one attribute as `name="value"` text (several may be typed),
    /// or adds new ones when `name` is nil.
    private func editAttribute(_ node: DOMNode, name: String?) {
        guard let model, let row = rowView(for: node) else { return }
        let current = name.flatMap { n in node.attribute(n).map { "\(n)=\"\($0)\"" } } ?? ""
        TextEditPopover.show(title: name == nil ? "Add Attribute" : "Edit Attribute", text: current, language: .html,
                             relativeTo: row, of: tree, singleLine: true) { text in
            var params: JSON = ["nodeId": node.id, "text": text]
            if let name { params["name"] = name }
            if text.trimmingCharacters(in: .whitespaces).isEmpty, let name {
                model.edit("DOM.removeAttribute", ["nodeId": node.id, "name": name])
            } else {
                model.edit("DOM.setAttributesAsText", params)
            }
        }
    }

    private func rowView(for node: DOMNode) -> NSRect? {
        let row = tree.row(forItem: node)
        return row >= 0 ? tree.rect(ofRow: row) : nil
    }

    // MARK: Outline

    private func items(of item: Any?) -> [AnyObject] {
        guard let node = item as? DOMNode ?? model?.document else { return [] }
        if item == nil { return node.shownChildren }
        var children: [AnyObject] = node.shownChildren
        if node.isElement, node.pseudoType == nil, !children.isEmpty {
            let closing = closingTags[node.id] ?? ClosingTag(node)
            closingTags[node.id] = closing
            children.append(closing)
        }
        return children
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        items(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        items(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? DOMNode)?.hasChildren ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let node = item as? DOMNode, let model else { return false }
        if node.children == nil, node.childCount > 0 {
            model.loadChildren(node) { [weak self] in
                self?.tree.reloadItem(node, reloadChildren: true)
                self?.tree.expandItem(node)
            }
            return false
        }
        return true
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? DOMNode { tree.reloadItem(node, reloadChildren: false) }
        sizeTreeColumn()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? DOMNode { tree.reloadItem(node, reloadChildren: false) }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let closing = item as? ClosingTag {
            return InspectorTable.cell(outlineView, "dom", DOMText.closing(closing.node))
        }
        guard let node = item as? DOMNode else { return nil }
        let text = DOMText.row(node, expanded: outlineView.isItemExpanded(node))
        let cell = InspectorTable.cell(outlineView, "dom", text)
        cell.alphaValue = sidebarHidden(node) ? 0.5 : 1
        return cell
    }

    private func sidebarHidden(_ node: DOMNode) -> Bool { sidebar.hiddenNodes.contains(node.id) }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { InspectorRowView() }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelection, let model else { return }
        let row = tree.selectedRow
        guard row >= 0, let node = node(atRow: row) else { return }
        if tree.item(atRow: row) is ClosingTag {
            selectRow(of: node)
        }
        model.select(node)
    }
}

/// The DOM tree: reports the row under the pointer, for highlighting the
/// element in the page.
final class DOMOutlineView: InspectorOutlineView {
    var onHover: ((Int?) -> Void)?
    private var area: NSTrackingArea?
    private var hovered: Int?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseMoved(with event: NSEvent) {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        let value = row >= 0 ? row : nil
        guard value != hovered else { return }
        hovered = value
        onHover?(value)
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        onHover?(nil)
    }
}

/// The selected element's ancestors along the bottom of the tree.
final class BreadcrumbBar: FlippedView {
    static let height: CGFloat = 22
    var onSelect: ((DOMNode) -> Void)?
    private let scroll = NSScrollView()
    private let strip = FlippedView()
    private let line = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(line)
        scroll.documentView = strip
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = InspectorTheme.bar.cgColor
        line.backgroundColor = InspectorTheme.separator.cgColor
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        line.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        CATransaction.commit()
        scroll.frame = NSRect(x: 0, y: 1, width: bounds.width, height: bounds.height - 1)
        strip.frame.size.height = bounds.height - 1
        // The selected end stays in view.
        strip.scroll(NSPoint(x: max(strip.frame.width - scroll.contentSize.width, 0), y: 0))
    }

    func show(_ path: [DOMNode]) {
        strip.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 6
        for (i, node) in path.enumerated() {
            let button = NSButton(title: node.shortName, target: nil, action: nil)
            button.isBordered = false
            button.font = InspectorTheme.mono(10.5, i == path.count - 1 ? .semibold : .regular)
            button.contentTintColor = i == path.count - 1 ? .labelColor : .secondaryLabelColor
            button.attributedTitle = NSAttributedString(string: node.shortName.clipped(40), attributes: [
                .font: InspectorTheme.mono(10.5, i == path.count - 1 ? .semibold : .regular),
                .foregroundColor: i == path.count - 1 ? NSColor.labelColor : InspectorTheme.tag,
            ])
            button.onAction { [weak self] in self?.onSelect?(node) }
            button.sizeToFit()
            button.frame = NSRect(x: x, y: 2, width: button.frame.width + 4, height: 17)
            strip.addSubview(button)
            x += button.frame.width + 2
            if i < path.count - 1 {
                let separator = NSTextField(labelWithString: "›")
                separator.font = Theme.font(10)
                separator.textColor = .tertiaryLabelColor
                separator.frame = NSRect(x: x, y: 3, width: 8, height: 14)
                strip.addSubview(separator)
                x += 10
            }
        }
        strip.frame = NSRect(x: 0, y: 0, width: x + 6, height: bounds.height - 1)
        needsLayout = true
    }
}

// MARK: - Sidebar

/// Under the tree: the selected element's Styles, Computed values, Event
/// Listeners, Properties and Accessibility.
final class ElementSidebar: FlippedView {
    private let tabs = InspectorChips(["Styles", "Computed", "Listeners", "Properties", "Accessibility"])
    private let bar = InspectorToolbar()
    private let styles = StylesView()
    private let computed = ComputedView()
    private let values = ValueTreeView()
    private weak var model: ElementsModel?
    private weak var session: InspectorSession?
    private var tab = UserDefaults.standard.integer(forKey: "inspector.elements.tab")
    private lazy var refresh = Coalescer(delay: 0.1) { [weak self] in self?.reload() }
    /// Pseudo-classes forced on, by node.
    private(set) var forcedStates: [Int: Set<String>] = [:]
    /// Nodes hidden with H.
    private(set) var hiddenNodes: Set<Int> = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        tabs.selected = [tab]
        tabs.onChange = { [weak self] selected in
            guard let self else { return }
            tab = selected.first ?? 0
            UserDefaults.standard.set(tab, forKey: "inspector.elements.tab")
            reload()
        }
        bar.add(tabs, width: tabs.preferredWidth)
        addSubview(bar)
        addSubview(styles)
        addSubview(computed)
        addSubview(values)
        styles.sidebar = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: InspectorToolbar.height)
        let content = NSRect(x: 0, y: bar.frame.maxY, width: bounds.width, height: max(bounds.height - bar.frame.maxY, 0))
        for view in [styles, computed, values] as [NSView] { view.frame = content }
    }

    func bind(_ model: ElementsModel?, session: InspectorSession?) {
        self.model?.stylesChanged.stopObserving(self)
        self.model = model
        self.session = session
        styles.model = model
        styles.session = session
        computed.model = model
        computed.session = session
        forcedStates = [:]
        hiddenNodes = []
        model?.stylesChanged.observe(self) { [weak self] in self?.refresh.schedule() }
        reload()
    }

    func selectionChanged() { refresh.flush() }

    private func reload() {
        styles.isHidden = tab != 0
        computed.isHidden = tab != 1
        values.isHidden = tab < 2
        let node = model?.selected
        switch tab {
        case 0: styles.show(node)
        case 1: computed.show(node)
        case 2: showListeners(node)
        case 3: showProperties(node)
        default: showAccessibility(node)
        }
    }

    private func showListeners(_ node: DOMNode?) {
        values.show([])
        guard let node, let model, let session, node.isElement else { return }
        Task {
            guard let object = await model.resolve(node), let id = object.str("objectId") else { return }
            let result = try? await session.send("DOMDebugger.getEventListeners", ["objectId": id, "depth": 1])
            let listeners = result?.list("listeners") ?? []
            let types = Dictionary(grouping: listeners) { $0.str("type") ?? "" }
            let groups = types.keys.sorted().map { type -> ValueNode in
                GroupNode(name: type, children: types[type]!.map { listener in
                    var flags: [String] = []
                    if listener.bool("useCapture") { flags.append("capture") }
                    if listener.bool("passive") { flags.append("passive") }
                    if listener.bool("once") { flags.append("once") }
                    let handler = listener.obj("handler") ?? ["type": "function", "description": "handler"]
                    let label = "line \((listener.int("lineNumber") ?? 0) + 1)" + (flags.isEmpty ? "" : " · " + flags.joined(separator: ", "))
                    return RemoteValueNode(name: label, object: handler, session: session)
                })
            }
            guard model.selected === node else { return }
            values.show(groups.isEmpty ? [GroupNode(name: "", value: NSMutableAttributedString().add("No event listeners", .tertiaryLabelColor))] : groups)
            values.expandRoots()
        }
    }

    private func showProperties(_ node: DOMNode?) {
        values.show([])
        guard let node, let model, let session else { return }
        Task {
            guard let object = await model.resolve(node), model.selected === node else { return }
            let root = RemoteValueNode(name: node.shortName, object: object, session: session)
            values.show([root])
            values.expand(root)
        }
    }

    private func showAccessibility(_ node: DOMNode?) {
        values.show([])
        guard let node, let session else { return }
        Task {
            let result = try? await session.send("Accessibility.getPartialAXTree", ["nodeId": node.id, "fetchRelatives": true])
            guard model?.selected === node else { return }
            let nodes = result?.list("nodes") ?? []
            guard let mine = nodes.first(where: { $0.int("backendDOMNodeId") == node.backendID }) ?? nodes.first else {
                values.show([GroupNode(name: "", value: NSMutableAttributedString().add("Not in the accessibility tree", .tertiaryLabelColor))])
                return
            }
            func text(_ value: JSON?) -> NSAttributedString {
                let raw = value?["value"].map { "\($0)" } ?? ""
                return NSMutableAttributedString().add(raw.isEmpty ? "—" : raw, raw.isEmpty ? .tertiaryLabelColor : .labelColor)
            }
            var rows: [ValueNode] = [
                GroupNode(name: "Role", value: text(mine.obj("role"))),
                GroupNode(name: "Name", value: text(mine.obj("name"))),
            ]
            if let description = mine.obj("description") { rows.append(GroupNode(name: "Description", value: text(description))) }
            if mine.bool("ignored") {
                let reasons = mine.list("ignoredReasons").compactMap { $0.str("name") }.joined(separator: ", ")
                rows.append(GroupNode(name: "Ignored", value: NSMutableAttributedString().add(reasons.isEmpty ? "yes" : reasons, InspectorTheme.warning)))
            }
            let properties = mine.list("properties").map { GroupNode(name: $0.str("name") ?? "", value: text($0.obj("value"))) }
            if !properties.isEmpty { rows.append(GroupNode(name: "Properties", children: properties)) }
            // The way up: what assistive technology reads around it.
            var chain: [String] = []
            var parentID = mine.str("parentId")
            while let id = parentID, let parent = nodes.first(where: { $0.str("nodeId") == id }) {
                let role = parent.obj("role")?["value"].map { "\($0)" } ?? ""
                let name = parent.obj("name")?["value"].map { "\($0)" } ?? ""
                if !parent.bool("ignored") { chain.insert(name.isEmpty ? role : "\(role) \"\(name.clipped(30))\"", at: 0) }
                parentID = parent.str("parentId")
            }
            if !chain.isEmpty { rows.append(GroupNode(name: "Ancestors", value: NSMutableAttributedString().add(chain.joined(separator: " › "), .secondaryLabelColor))) }
            values.show(rows)
            values.expandRoots()
        }
    }

    // MARK: States

    func toggleForcedState(_ state: String, on node: DOMNode) {
        var states = forcedStates[node.id] ?? []
        if states.contains(state) { states.remove(state) } else { states.insert(state) }
        forcedStates[node.id] = states
        session?.call("CSS.forcePseudoState", ["nodeId": node.id, "forcedPseudoClasses": Array(states)])
        styles.forcedChanged()
        refresh.schedule()
    }

    func toggleHidden(_ node: DOMNode) {
        guard let model else { return }
        let hide = !hiddenNodes.contains(node.id)
        if hide { hiddenNodes.insert(node.id) } else { hiddenNodes.remove(node.id) }
        Task {
            _ = await model.callOn(node, "function(hide){ this.style.setProperty('visibility', hide ? 'hidden' : '', hide ? 'important' : '') }"
                .replacingOccurrences(of: "function(hide){", with: "function(){ const hide = \(hide);"))
        }
    }
}

// MARK: - Styles

/// The rules that apply to the selected element, most specific first, as
/// editable blocks: tick a declaration off, click a name or value to edit,
/// click a rule's empty line to add one.
final class StylesView: FlippedView {
    weak var model: ElementsModel?
    weak var session: InspectorSession?
    weak var sidebar: ElementSidebar?
    private let toolbar = InspectorToolbar()
    private let filter = InspectorFilterField(placeholder: "Filter styles")
    private let hov = InspectorButton("hand.point.up.left", tip: "Force element state (:hover, :focus…)")
    private let newRule = InspectorButton("plus", tip: "New style rule")
    private let scroll = NSScrollView()
    private let document = FlippedView()
    private let empty = InspectorEmptyView("Select an element to see its styles.")
    private var node: DOMNode?
    private var blocks: [RuleBlock] = []
    private var filterText = ""
    private var loading = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        filter.onChange = { [weak self] text in
            self?.filterText = text
            self?.layoutBlocks()
        }
        hov.action = { [weak self] in self?.showStates() }
        newRule.action = { [weak self] in self?.addRule() }
        toolbar.add(filter, width: nil)
        toolbar.add(hov, width: 24)
        toolbar.add(newRule, width: 24)
        addSubview(toolbar)
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        addSubview(scroll)
        addSubview(empty)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        toolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: InspectorToolbar.height)
        scroll.frame = NSRect(x: 0, y: toolbar.frame.maxY, width: bounds.width, height: max(bounds.height - toolbar.frame.maxY, 0))
        empty.frame = scroll.frame
        layoutBlocks()
    }

    func forcedChanged() {
        guard let node else { return }
        hov.isOn = !(sidebar?.forcedStates[node.id]?.isEmpty ?? true)
    }

    func show(_ node: DOMNode?) {
        let same = node === self.node
        self.node = node
        forcedChanged()
        guard let node, let session, node.isElement || node.pseudoType != nil else {
            setBlocks([])
            empty.isHidden = false
            empty.text = node == nil ? "Select an element to see its styles." : "Text and comments have no styles."
            return
        }
        empty.isHidden = true
        loading += 1
        let ticket = loading
        session.call("CSS.getMatchedStylesForNode", ["nodeId": node.id]) { [weak self] result, error in
            guard let self, ticket == loading, self.node === node else { return }
            guard let result else {
                setBlocks([])
                empty.isHidden = false
                empty.text = error ?? "No styles."
                return
            }
            let offset = same ? scroll.contentView.bounds.origin : .zero
            setBlocks(makeBlocks(result, node: node))
            scroll.contentView.scroll(to: offset)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func makeBlocks(_ result: JSON, node: DOMNode) -> [RuleBlock] {
        var rules: [StyleRule] = []
        if let inline = result.obj("inlineStyle") {
            rules.append(StyleRule(selector: "element.style", style: inline, origin: "inline", media: [], source: nil))
        }
        for match in result.list("matchedCSSRules").reversed() {
            guard let rule = match.obj("rule") else { continue }
            rules.append(StyleRule(rule: rule, sheets: model?.styleSheets ?? [:], matching: match["matchingSelectors"] as? [Int]))
        }
        if let attributes = result.obj("attributesStyle"), !attributes.list("cssProperties").isEmpty {
            rules.append(StyleRule(selector: "\(node.localName)[Attributes Style]", style: attributes, origin: "attributes", media: [], source: nil))
        }
        // Pseudo-elements' rules.
        for pseudo in result.list("pseudoElements") {
            let type = pseudo.str("pseudoType") ?? ""
            for match in pseudo.list("matches").reversed() {
                guard let rule = match.obj("rule") else { continue }
                var styleRule = StyleRule(rule: rule, sheets: model?.styleSheets ?? [:], matching: match["matchingSelectors"] as? [Int])
                styleRule.heading = "Pseudo ::\(type) element"
                rules.append(styleRule)
            }
        }
        // Inherited properties, from each ancestor.
        var ancestor = node.parent
        for entry in result.list("inherited") {
            while let current = ancestor, !current.isElement { ancestor = current.parent }
            let name = ancestor?.shortName ?? "ancestor"
            var first = true
            if let inline = entry.obj("inlineStyle"), inline.list("cssProperties").contains(where: { Self.inherits($0.str("name") ?? "") }) {
                var rule = StyleRule(selector: "style attribute", style: inline, origin: "inline", media: [], source: nil)
                rule.heading = "Inherited from \(name)"
                rule.inherited = true
                first = false
                rules.append(rule)
            }
            for match in entry.list("matchedCSSRules").reversed() {
                guard let raw = match.obj("rule") else { continue }
                var rule = StyleRule(rule: raw, sheets: model?.styleSheets ?? [:], matching: match["matchingSelectors"] as? [Int])
                rule.inherited = true
                guard rule.declarations.contains(where: { Self.inherits($0.name) }) else { continue }
                if first { rule.heading = "Inherited from \(name)"; first = false }
                rules.append(rule)
            }
            ancestor = ancestor?.parent
        }
        // Which declarations lose: a later one of the same name, or one an
        // !important declaration beats.
        var winners: [String: (important: Bool, rule: Int)] = [:]
        for (r, rule) in rules.enumerated() {
            for (d, declaration) in rule.declarations.enumerated() where declaration.enabled && declaration.parsedOK {
                if rule.inherited, !Self.inherits(declaration.name) {
                    rules[r].declarations[d].inactive = true
                    continue
                }
                let key = declaration.name
                if let winner = winners[key] {
                    if declaration.important, !winner.important, winner.rule != r || true {
                        // An earlier non-important winner loses to this one.
                        for (wr, wrule) in rules.enumerated() where wr <= r {
                            for (wd, wdecl) in wrule.declarations.enumerated() where wdecl.name == key && !wdecl.important && !(wr == r && wd == d) {
                                rules[wr].declarations[wd].overridden = true
                            }
                        }
                        winners[key] = (true, r)
                    } else {
                        rules[r].declarations[d].overridden = true
                    }
                } else {
                    winners[key] = (declaration.important, r)
                }
            }
        }
        return rules.map { RuleBlock(rule: $0, styles: self) }
    }

    /// Properties children take from their parents.
    static func inherits(_ name: String) -> Bool {
        if name.hasPrefix("--") { return true }
        let inherited: Set<String> = ["color", "cursor", "direction", "font", "font-family", "font-size", "font-style", "font-variant",
                                      "font-weight", "font-stretch", "font-feature-settings", "letter-spacing", "line-height",
                                      "list-style", "list-style-type", "list-style-position", "list-style-image", "quotes",
                                      "text-align", "text-indent", "text-transform", "text-shadow", "visibility", "white-space",
                                      "word-break", "word-spacing", "word-wrap", "overflow-wrap", "caret-color", "tab-size",
                                      "-webkit-font-smoothing", "text-rendering", "hyphens", "orientation", "writing-mode",
                                      "border-collapse", "border-spacing", "caption-side", "empty-cells", "speak", "accent-color",
                                      "color-scheme", "pointer-events", "user-select", "-webkit-text-fill-color"]
        return inherited.contains(name)
    }

    private func setBlocks(_ new: [RuleBlock]) {
        blocks.forEach { $0.removeFromSuperview() }
        blocks = new
        blocks.forEach { document.addSubview($0) }
        layoutBlocks()
    }

    private func layoutBlocks() {
        let width = scroll.contentSize.width
        var y: CGFloat = 0
        for block in blocks {
            block.filter = filterText
            let height = block.layoutRows(width: width)
            block.isHidden = height == 0
            block.frame = NSRect(x: 0, y: y, width: width, height: height)
            y += height
        }
        document.frame = NSRect(x: 0, y: 0, width: width, height: max(y + 20, scroll.contentSize.height))
    }

    private func showStates() {
        guard let node, let sidebar else { return }
        let menu = NSMenu()
        for state in ["hover", "active", "focus", "focus-within", "focus-visible", "visited", "target"] {
            let on = sidebar.forcedStates[node.id]?.contains(state) ?? false
            menu.add(":\(state)", state: on) { [weak sidebar] in sidebar?.toggleForcedState(state, on: node) }
        }
        hov.popUp(menu)
    }

    /// A new rule for the selected element in an inspector stylesheet.
    private func addRule() {
        guard let node, let session, node.isElement else { return }
        let selector = node.attribute("id").flatMap { $0.isEmpty ? nil : "#\($0)" }
            ?? node.attribute("class")?.split(separator: " ").first.map { ".\($0)" } ?? node.localName
        Task {
            let frame = node.frameID ?? session.mainFrameID
            guard let sheet = try? await session.send("CSS.createStyleSheet", ["frameId": frame]).str("styleSheetId") else { return }
            let text = (try? await session.send("CSS.getStyleSheetText", ["styleSheetId": sheet]).str("text")) ?? ""
            let lines = text.components(separatedBy: "\n")
            let location: JSON = ["startLine": lines.count - 1, "startColumn": lines.last?.utf16.count ?? 0,
                                  "endLine": lines.count - 1, "endColumn": lines.last?.utf16.count ?? 0]
            _ = try? await session.send("CSS.addRule", ["styleSheetId": sheet, "ruleText": "\(selector) {}", "location": location])
            show(node)
        }
    }

    // MARK: Edits

    /// Replaces a style's text, then shows the result.
    func setStyleText(_ rule: StyleRule, _ text: String) {
        guard let session, let node else { return }
        if let sheet = rule.styleSheetID, let range = rule.range {
            session.call("CSS.setStyleTexts", ["edits": [["styleSheetId": sheet, "range": range, "text": text]]]) { [weak self] _, error in
                if let error { NSLog("styles: %@", error) }
                self?.show(node)
            }
        } else if rule.origin == "inline" {
            model?.edit("DOM.setAttributeValue", ["nodeId": node.id, "name": "style", "value": text]) { [weak self] _, _ in self?.show(node) }
        }
    }

    func reveal(_ rule: StyleRule) {
        guard let source = rule.source, let range = rule.range else { return }
        session?.revealSource(url: source, line: range.int("startLine") ?? 0, column: range.int("startColumn") ?? 0)
    }

    func setSelector(_ rule: StyleRule, _ text: String) {
        guard let session, let sheet = rule.styleSheetID, let range = rule.selectorRange, let node else { return }
        session.call("CSS.setRuleSelector", ["styleSheetId": sheet, "range": range, "selector": text]) { [weak self] _, _ in self?.show(node) }
    }
}

/// A CSS declaration as the Styles pane shows it.
struct StyleDeclaration {
    var name: String
    var value: String
    var important: Bool
    var enabled: Bool
    var parsedOK: Bool
    /// Its text in the stylesheet, kept to rewrite the style.
    var text: String?
    var overridden = false
    /// Not inherited from an ancestor.
    var inactive = false
}

/// A rule (or inline style) and its declarations.
struct StyleRule {
    var selector: String
    var heading: String?
    var origin: String
    var media: [String]
    var source: String?
    var styleSheetID: String?
    var range: JSON?
    var selectorRange: JSON?
    var declarations: [StyleDeclaration] = []
    var inherited = false
    /// Indices of the selectors in the list that match.
    var matching: [Int]?
    var selectors: [String] = []

    init(selector: String, style: JSON, origin: String, media: [String], source: String?) {
        self.selector = selector
        self.origin = origin
        self.media = media
        self.source = source
        styleSheetID = style.str("styleSheetId")
        range = style.obj("range")
        declarations = Self.declarations(style)
    }

    init(rule: JSON, sheets: [String: JSON], matching: [Int]?) {
        let list = rule.obj("selectorList")
        selector = list?.str("text") ?? ""
        selectors = list?.list("selectors").compactMap { $0.str("text") } ?? []
        selectorRange = list?.list("selectors").first?.obj("range").flatMap { first in
            list?.list("selectors").last?.obj("range").map { last in
                ["startLine": first["startLine"]!, "startColumn": first["startColumn"]!, "endLine": last["endLine"]!, "endColumn": last["endColumn"]!]
            }
        }
        self.matching = matching
        origin = rule.str("origin") ?? "regular"
        media = rule.list("media").compactMap { $0.str("text") }.map { "@media \($0)" }
            + rule.list("containerQueries").compactMap { $0.str("text") }.map { "@container \($0)" }
            + rule.list("supports").compactMap { $0.str("text") }.map { "@supports \($0)" }
            + rule.list("layers").compactMap { $0.str("text") }.filter { !$0.isEmpty }.map { "@layer \($0)" }
        let style = rule.obj("style") ?? [:]
        styleSheetID = style.str("styleSheetId") ?? rule.str("styleSheetId")
        range = style.obj("range")
        if let id = rule.str("styleSheetId"), let header = sheets[id] {
            let url = header.str("sourceURL") ?? ""
            source = url.isEmpty ? nil : url
        }
        declarations = Self.declarations(style)
    }

    private static func declarations(_ style: JSON) -> [StyleDeclaration] {
        let properties = style.list("cssProperties")
        let authored = properties.contains { $0.str("text") != nil }
        return properties.compactMap { property in
            // Longhands a shorthand expands to have no text of their own.
            if authored, property.str("text") == nil { return nil }
            guard let name = property.str("name") else { return nil }
            var value = property.str("value") ?? ""
            let important = property.bool("important")
            if important { value = value.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces) }
            return StyleDeclaration(name: name, value: value, important: important,
                                    enabled: !property.bool("disabled"), parsedOK: property["parsedOk"] as? Bool ?? true,
                                    text: property.str("text"))
        }
    }

    var editable: Bool { (origin == "regular" || origin == "inline" || origin == "inspector") && (styleSheetID != nil || origin == "inline") }

    /// The style's text with `declarations` as given, disabled ones in
    /// comments, as DevTools writes it.
    func text(with declarations: [StyleDeclaration]) -> String {
        let lines = declarations.map { d -> String in
            let line = "\(d.name): \(d.value)\(d.important ? " !important" : "");"
            return d.enabled ? line : "/* \(line) */"
        }
        return origin == "inline" && styleSheetID == nil ? lines.joined(separator: " ") : "\n    " + lines.joined(separator: "\n    ") + "\n"
    }
}

/// One rule's block in the Styles pane.
final class RuleBlock: FlippedView {
    private(set) var rule: StyleRule
    private weak var styles: StylesView?
    var filter = ""
    private var rowViews: [NSView] = []

    init(rule: StyleRule, styles: StylesView) {
        self.rule = rule
        self.styles = styles
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Lays out its rows for `width`; its height, or 0 when filtered out.
    func layoutRows(width: CGFloat) -> CGFloat {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []
        let matches = filter.isEmpty || rule.selector.localizedCaseInsensitiveContains(filter)
            || rule.declarations.contains { "\($0.name): \($0.value)".localizedCaseInsensitiveContains(filter) }
        guard matches else { return 0 }
        var y: CGFloat = 0
        let font = InspectorTheme.mono(11)
        if let heading = rule.heading {
            let label = Label.make(heading, size: 11, weight: .medium, color: .secondaryLabelColor)
            label.frame = NSRect(x: 8, y: y + 6, width: width - 16, height: 16)
            add(label)
            y += 24
        }
        for media in rule.media {
            let label = NSTextField(labelWithString: media)
            label.font = InspectorTheme.mono(10.5)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 8, y: y + 4, width: width - 16, height: 15)
            add(label)
            y += 17
        }
        // Selector line, with the source on the right.
        let source = sourceLabel()
        let sourceWidth = source.map { min($0.textWidth, width * 0.45) } ?? 0
        let selector = selectorText()
        let selectorField = ClickableText(selector) { [weak self] in self?.editSelector() }
        selectorField.frame = NSRect(x: 8, y: y + 4, width: max(width - 24 - sourceWidth, 40), height: 16)
        add(selectorField)
        if let source {
            source.frame = NSRect(x: width - sourceWidth - 8, y: y + 4, width: sourceWidth, height: 16)
            add(source)
        }
        y += 20
        for (index, declaration) in rule.declarations.enumerated() {
            guard filter.isEmpty || matchesFilter(declaration) || rule.selector.localizedCaseInsensitiveContains(filter) else { continue }
            let row = DeclarationRow(declaration, editable: rule.editable)
            row.onToggle = { [weak self] in self?.toggle(index) }
            row.onEdit = { [weak self] name, value in self?.edit(index, name: name, value: value) }
            row.frame = NSRect(x: 0, y: y, width: width, height: 18)
            add(row)
            y += 18
        }
        let close = ClickableText(NSMutableAttributedString().add("}", .labelColor, font: font)) { [weak self] in self?.addDeclaration() }
        close.frame = NSRect(x: 8, y: y, width: width - 16, height: 16)
        close.toolTip = rule.editable ? "Click to add a declaration" : nil
        add(close)
        y += 22
        // A hairline under the block.
        let line = NSView(frame: NSRect(x: 0, y: y - 1, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = InspectorTheme.separator.cgColor
        add(line)
        return y
    }

    private func add(_ view: NSView) {
        addSubview(view)
        rowViews.append(view)
    }

    private func matchesFilter(_ declaration: StyleDeclaration) -> Bool {
        "\(declaration.name): \(declaration.value)".localizedCaseInsensitiveContains(filter)
    }

    private func selectorText() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let font = InspectorTheme.mono(11)
        if rule.selectors.count > 1, let matching = rule.matching {
            for (i, selector) in rule.selectors.enumerated() {
                if i > 0 { out.add(", ", .secondaryLabelColor, font: font) }
                out.add(selector, matching.contains(i) ? .labelColor : .tertiaryLabelColor, font: font)
            }
        } else {
            out.add(rule.selector, rule.origin == "user-agent" ? .secondaryLabelColor : .labelColor, font: font)
        }
        out.add(" {", .labelColor, font: font)
        return out
    }

    private func sourceLabel() -> NSTextField? {
        let text: String
        switch rule.origin {
        case "user-agent": text = "user agent stylesheet"
        case "inline" where rule.styleSheetID == nil, "attributes": return nil
        case "inline": return nil
        case "inspector": text = "inspector-stylesheet"
        default:
            guard let source = rule.source else { return nil }
            var name = URL(string: source)?.lastPathComponent ?? source
            // A <style> in the page, as DevTools names the document.
            if name.isEmpty || name == "/" { name = "(index)" }
            let line = (rule.range?.int("startLine") ?? 0) + 1
            text = "\(name.isEmpty ? source : name):\(line)"
        }
        let label = ClickableText(NSMutableAttributedString().add(text, rule.origin == "user-agent" ? .tertiaryLabelColor : InspectorTheme.link,
                                                                   font: InspectorTheme.mono(10.5))) { [weak self] in
            guard let self else { return }
            styles?.reveal(rule)
        }
        label.alignment = .right
        label.lineBreakMode = .byTruncatingHead
        label.toolTip = rule.source
        return label
    }

    private func toggle(_ index: Int) {
        guard rule.editable else { return }
        var declarations = rule.declarations
        declarations[index].enabled.toggle()
        styles?.setStyleText(rule, rule.text(with: declarations))
    }

    /// A name or value edited: "" removes the declaration; a value with
    /// several declarations typed (`a: 1; b: 2`) adds them all.
    private func edit(_ index: Int, name: String, value: String) {
        guard rule.editable else { return }
        var declarations = rule.declarations
        if name.isEmpty || (value.isEmpty && name == declarations[safe: index]?.name) {
            if declarations.indices.contains(index) { declarations.remove(at: index) }
        } else {
            let parsed = Self.parse(name.contains(":") ? name : "\(name): \(value)")
            if declarations.indices.contains(index) {
                declarations.replaceSubrange(index...index, with: parsed)
            } else {
                declarations += parsed
            }
        }
        styles?.setStyleText(rule, rule.text(with: declarations))
    }

    /// `a: 1; b: 2 !important` as declarations.
    static func parse(_ text: String) -> [StyleDeclaration] {
        text.split(separator: ";").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count == 2, !pieces[0].isEmpty else { return nil }
            var value = pieces[1]
            let important = value.hasSuffix("!important")
            if important { value = String(value.dropLast(10)).trimmingCharacters(in: .whitespaces) }
            return StyleDeclaration(name: pieces[0], value: value, important: important, enabled: true, parsedOK: true)
        }
    }

    private func addDeclaration() {
        guard rule.editable else { return }
        let index = rule.declarations.count
        let row = DeclarationRow(StyleDeclaration(name: "", value: "", important: false, enabled: true, parsedOK: true), editable: true)
        row.onEdit = { [weak self] name, value in
            guard !name.isEmpty else { return }
            self?.edit(index, name: name, value: value)
        }
        let closing = rowViews.last(where: { $0 is ClickableText }) ?? self
        row.frame = NSRect(x: 0, y: closing.frame.minY, width: bounds.width, height: 18)
        closing.frame.origin.y += 18
        add(row)
        row.beginEditingName()
    }

    private func editSelector() {
        guard rule.editable, rule.origin != "inline", let field = rowViews.first(where: { $0 is ClickableText }) else { return }
        InlineEditor.edit(rule.selector, over: field, in: self) { [weak self] text in
            guard let self, let text, !text.isEmpty, text != rule.selector else { return }
            styles?.setSelector(rule, text)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// `☑ color: ■ red;`: a checkbox, the name and value (each editable on
/// click) and a swatch before colours.
final class DeclarationRow: FlippedView {
    private let declaration: StyleDeclaration
    private let editable: Bool
    private let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let name = ClickableText(NSAttributedString())
    private let value = ClickableText(NSAttributedString())
    private let swatch = NSView()
    var onToggle: (() -> Void)?
    var onEdit: ((String, String) -> Void)?

    init(_ declaration: StyleDeclaration, editable: Bool) {
        self.declaration = declaration
        self.editable = editable
        super.init(frame: .zero)
        check.controlSize = .mini
        check.state = declaration.enabled ? .on : .off
        check.isEnabled = editable
        check.onAction { [weak self] in self?.onToggle?() }
        addSubview(check)
        let font = InspectorTheme.mono(11)
        let dim = declaration.overridden || !declaration.enabled || declaration.inactive
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if declaration.overridden || !declaration.enabled { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        let nameText = NSMutableAttributedString(string: declaration.name, attributes: attributes)
        nameText.addAttribute(.foregroundColor, value: dim ? InspectorTheme.property.withAlphaComponent(0.5) : InspectorTheme.property,
                              range: NSRange(location: 0, length: nameText.length))
        if !declaration.parsedOK { nameText.addAttribute(.foregroundColor, value: InspectorTheme.warning, range: NSRange(location: 0, length: nameText.length)) }
        nameText.append(NSAttributedString(string: ":", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        name.attributedStringValue = nameText
        let valueText = NSMutableAttributedString(string: declaration.value + (declaration.important ? " !important" : ""), attributes: attributes)
        valueText.addAttribute(.foregroundColor, value: dim ? NSColor.tertiaryLabelColor : NSColor.labelColor,
                               range: NSRange(location: 0, length: valueText.length))
        valueText.append(NSAttributedString(string: ";", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        value.attributedStringValue = valueText
        name.onClick = { [weak self] in self?.beginEditingName() }
        value.onClick = { [weak self] in self?.beginEditingValue() }
        addSubview(name)
        addSubview(value)
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 2
        swatch.layer?.borderWidth = 0.5
        swatch.layer?.borderColor = NSColor.black.withAlphaComponent(0.3).cgColor
        if let color = CSSColor.parse(declaration.value) {
            swatch.layer?.backgroundColor = color.cgColor
        } else {
            swatch.isHidden = true
        }
        addSubview(swatch)
        toolTip = declaration.inactive ? "Not inherited" : !declaration.parsedOK ? "Invalid property value" : nil
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        check.frame = NSRect(x: 10, y: 2, width: 14, height: 14)
        let nameWidth = min(name.textWidth, bounds.width * 0.5)
        name.frame = NSRect(x: 26, y: 1, width: nameWidth, height: 16)
        var x = name.frame.maxX + 2
        if !swatch.isHidden {
            swatch.frame = NSRect(x: x + 2, y: 4, width: 10, height: 10)
            x += 16
        }
        value.frame = NSRect(x: x, y: 1, width: max(bounds.width - x - 8, 20), height: 16)
    }

    func beginEditingName() {
        guard editable else { return }
        InlineEditor.edit(declaration.name, over: name, in: self, minWidth: 120) { [weak self] text in
            guard let self, let text else { return }
            if text.contains(":") {
                onEdit?(text, "")
            } else if text != declaration.name {
                onEdit?(text, declaration.value.isEmpty ? "" : declaration.value)
            } else if declaration.value.isEmpty {
                beginEditingValue()
            }
        }
    }

    func beginEditingValue() {
        guard editable else { return }
        let current = declaration.value + (declaration.important ? " !important" : "")
        InlineEditor.edit(current, over: value, in: self, minWidth: 140) { [weak self] text in
            guard let self, let text, text != current else { return }
            onEdit?(declaration.name, text)
        }
    }
}

/// A one-line label that reports clicks.
final class ClickableText: NSTextField {
    var onClick: (() -> Void)?

    convenience init(_ text: NSAttributedString, onClick: (() -> Void)? = nil) {
        self.init(labelWithAttributedString: text)
        self.onClick = onClick
        lineBreakMode = .byTruncatingTail
        maximumNumberOfLines = 1
        cell?.truncatesLastVisibleLine = true
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick { onClick() } else { super.mouseDown(with: event) }
    }

    override func resetCursorRects() {
        if onClick != nil { addCursorRect(bounds, cursor: .iBeam) }
    }
}

/// Edits a short text in place over a label: Return or leaving commits,
/// Escape cancels (nil).
@MainActor
enum InlineEditor {
    private final class Delegate: NSObject, NSTextFieldDelegate {
        let done: (String?) -> Void
        var finished = false
        init(_ done: @escaping (String?) -> Void) { self.done = done }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) { finish(control, nil); return true }
            if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.insertTab(_:)) {
                finish(control, control.stringValue)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            finish(field, field.stringValue)
        }

        func finish(_ control: NSControl, _ value: String?) {
            guard !finished else { return }
            finished = true
            control.removeFromSuperview()
            done(value)
        }
    }

    private nonisolated(unsafe) static var key: UInt8 = 0

    static func edit(_ text: String, over view: NSView, in host: NSView, minWidth: CGFloat = 80, done: @escaping (String?) -> Void) {
        let field = NSTextField(string: text)
        field.font = InspectorTheme.mono(11)
        field.isBordered = true
        field.bezelStyle = .squareBezel
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = InspectorTheme.surface
        let frame = host.convert(view.frame, from: view.superview)
        field.frame = NSRect(x: frame.minX - 2, y: frame.minY - 1, width: max(frame.width + 8, minWidth),
                             height: frame.height + 2).intersection(host.bounds.insetBy(dx: 0, dy: -4))
        let delegate = Delegate(done)
        objc_setAssociatedObject(field, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        field.delegate = delegate
        host.addSubview(field)
        host.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }
}

/// Colours in CSS values, for swatches.
enum CSSColor {
    static func parse(_ value: String) -> NSColor? {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            let hex = String(text.dropFirst())
            guard [3, 4, 6, 8].contains(hex.count), let number = UInt64(hex, radix: 16) else { return nil }
            func channel(_ shift: Int, _ bits: Int) -> CGFloat {
                let max = bits == 4 ? 15.0 : 255.0
                return CGFloat(Double((number >> UInt64(shift)) & (bits == 4 ? 0xF : 0xFF)) / max)
            }
            switch hex.count {
            case 3: return NSColor(srgbRed: channel(8, 4), green: channel(4, 4), blue: channel(0, 4), alpha: 1)
            case 4: return NSColor(srgbRed: channel(12, 4), green: channel(8, 4), blue: channel(4, 4), alpha: channel(0, 4))
            case 6: return NSColor(srgbRed: channel(16, 8), green: channel(8, 8), blue: channel(0, 8), alpha: 1)
            default: return NSColor(srgbRed: channel(24, 8), green: channel(16, 8), blue: channel(8, 8), alpha: channel(0, 8))
            }
        }
        if text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") {
            let parts = text[text.index(after: open)..<close].split(whereSeparator: { ", /".contains($0) }).map(String.init)
            guard parts.count >= 3 else { return nil }
            func number(_ part: String, scale: Double) -> CGFloat {
                part.hasSuffix("%") ? CGFloat((Double(part.dropLast()) ?? 0) / 100) : CGFloat((Double(part) ?? 0) / scale)
            }
            return NSColor(srgbRed: number(parts[0], scale: 255), green: number(parts[1], scale: 255), blue: number(parts[2], scale: 255),
                           alpha: parts.count > 3 ? number(parts[3], scale: 1) : 1)
        }
        let named: [String: UInt32] = ["white": 0xFFFFFF, "black": 0x000000, "red": 0xFF0000, "green": 0x008000, "blue": 0x0000FF,
                                       "gray": 0x808080, "grey": 0x808080, "orange": 0xFFA500, "yellow": 0xFFFF00, "purple": 0x800080,
                                       "rebeccapurple": 0x663399, "pink": 0xFFC0CB, "silver": 0xC0C0C0, "navy": 0x000080,
                                       "teal": 0x008080, "maroon": 0x800000, "olive": 0x808000, "lime": 0x00FF00, "aqua": 0x00FFFF,
                                       "fuchsia": 0xFF00FF, "whitesmoke": 0xF5F5F5, "transparent": 0]
        if let hex = named[text] {
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                           alpha: text == "transparent" ? 0 : 1)
        }
        return nil
    }
}

// MARK: - Computed

/// The box model and every computed property, filterable.
final class ComputedView: FlippedView, NSTableViewDataSource, NSTableViewDelegate {
    weak var model: ElementsModel?
    weak var session: InspectorSession?
    private let toolbar = InspectorToolbar()
    private let filter = InspectorFilterField(placeholder: "Filter")
    private let showAll = InspectorButton("list.bullet", tip: "Show all properties, not only those set by rules")
    private let box = BoxModelView()
    private let table = InspectorTableView()
    private lazy var scroll = InspectorTable.make(table, columns: [("name", "Property", 150), ("value", "Value", 200)], header: false)
    private var all: [(name: String, value: String)] = []
    private var shown: [(name: String, value: String)] = []
    private var authored: Set<String> = []
    private var node: DOMNode?

    override init(frame: NSRect) {
        super.init(frame: frame)
        filter.onChange = { [weak self] _ in self?.applyFilter() }
        showAll.isOn = UserDefaults.standard.bool(forKey: "inspector.computed.all")
        showAll.action = { [weak self] in
            guard let self else { return }
            showAll.isOn.toggle()
            UserDefaults.standard.set(showAll.isOn, forKey: "inspector.computed.all")
            applyFilter()
        }
        toolbar.add(filter, width: nil)
        toolbar.add(showAll, width: 24)
        addSubview(toolbar)
        addSubview(box)
        table.dataSource = self
        table.delegate = self
        table.menuForRow = { [weak self] row in
            guard let self, shown.indices.contains(row) else { return nil }
            let item = shown[row]
            let menu = NSMenu()
            menu.add("Copy Declaration") { Format.copy("\(item.name): \(item.value);") }
            menu.add("Copy Value") { Format.copy(item.value) }
            return menu
        }
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        toolbar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: InspectorToolbar.height)
        box.frame = NSRect(x: 0, y: toolbar.frame.maxY, width: bounds.width, height: 170)
        scroll.frame = NSRect(x: 0, y: box.frame.maxY, width: bounds.width, height: max(bounds.height - box.frame.maxY, 0))
    }

    func show(_ node: DOMNode?) {
        self.node = node
        guard let node, let session, node.isElement || node.pseudoType != nil else {
            all = []
            applyFilter()
            box.model = nil
            return
        }
        session.call("CSS.getComputedStyleForNode", ["nodeId": node.id]) { [weak self] result, _ in
            guard let self, self.node === node else { return }
            all = (result?.list("computedStyle") ?? []).compactMap { entry in
                guard let name = entry.str("name") else { return nil }
                return (name, entry.str("value") ?? "")
            }.sorted { $0.name < $1.name }
            applyFilter()
        }
        session.call("CSS.getMatchedStylesForNode", ["nodeId": node.id]) { [weak self] result, _ in
            guard let self, self.node === node else { return }
            var names = Set<String>()
            let styles = [result?.obj("inlineStyle")].compactMap { $0 } + (result?.list("matchedCSSRules") ?? []).compactMap { $0.obj("rule")?.obj("style") }
            for style in styles { for property in style.list("cssProperties") { if let name = property.str("name") { names.insert(name) } } }
            authored = names
            applyFilter()
        }
        session.call("DOM.getBoxModel", ["nodeId": node.id]) { [weak self] result, _ in
            guard let self, self.node === node else { return }
            box.model = result?.obj("model")
        }
    }

    private func applyFilter() {
        let text = filter.stringValue
        shown = all.filter { item in
            (showAll.isOn || authored.contains(item.name) || authored.isEmpty)
                && (text.isEmpty || item.name.localizedCaseInsensitiveContains(text) || item.value.localizedCaseInsensitiveContains(text))
        }
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = shown[row]
        if tableColumn?.identifier.rawValue == "name" {
            return InspectorTable.cell(tableView, "name", item.name, color: InspectorTheme.property, font: InspectorTheme.mono(11))
        }
        return InspectorTable.cell(tableView, "value", item.value, font: InspectorTheme.mono(11))
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { InspectorRowView() }
}

/// Margin, border, padding and content, nested as DevTools draws them.
final class BoxModelView: NSView {
    var model: JSON? {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let model else {
            let text = "No box model" as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: Theme.font(11), .foregroundColor: NSColor.tertiaryLabelColor]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
            return
        }
        func quad(_ name: String) -> [Double] { (model[name] as? [NSNumber])?.map(\.doubleValue) ?? [] }
        let content = quad("content"), padding = quad("padding"), border = quad("border"), margin = quad("margin")
        guard content.count == 8, padding.count == 8, border.count == 8, margin.count == 8 else { return }
        // Edges: top, right, bottom, left differences between quads.
        func edges(_ outer: [Double], _ inner: [Double]) -> [Double] {
            [inner[1] - outer[1], outer[2] - inner[2], outer[5] - inner[5], inner[0] - outer[0]]
        }
        let layers: [(String, [Double], NSColor)] = [
            ("margin", edges(margin, border), NSColor(srgbRed: 0.96, green: 0.7, blue: 0.42, alpha: 0.55)),
            ("border", edges(border, padding), NSColor(srgbRed: 1, green: 0.9, blue: 0.6, alpha: 0.75)),
            ("padding", edges(padding, content), NSColor(srgbRed: 0.58, green: 0.77, blue: 0.49, alpha: 0.55)),
        ]
        var rect = bounds.insetBy(dx: max((bounds.width - 300) / 2, 12), dy: 10)
        let step: CGFloat = 26
        let font = InspectorTheme.mono(10)
        func draw(_ text: String, at point: NSPoint, color: NSColor = .labelColor) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
        }
        func number(_ value: Double) -> String {
            let rounded = (value * 100).rounded() / 100
            return rounded == 0 ? "–" : rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.2f", rounded)
        }
        for (name, sides, color) in layers {
            color.setFill()
            let path = NSBezierPath(rect: rect)
            path.fill()
            NSColor.black.withAlphaComponent(0.25).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            draw(name, at: NSPoint(x: rect.minX + 26, y: rect.minY + 8), color: NSColor.black.withAlphaComponent(0.6))
            draw(number(sides[0]), at: NSPoint(x: rect.midX, y: rect.minY + step / 2), color: .black)
            draw(number(sides[2]), at: NSPoint(x: rect.midX, y: rect.maxY - step / 2), color: .black)
            draw(number(sides[3]), at: NSPoint(x: rect.minX + step / 2, y: rect.midY), color: .black)
            draw(number(sides[1]), at: NSPoint(x: rect.maxX - step / 2, y: rect.midY), color: .black)
            rect = rect.insetBy(dx: step, dy: step)
        }
        NSColor(srgbRed: 0.44, green: 0.66, blue: 0.86, alpha: 0.6).setFill()
        NSBezierPath(rect: rect).fill()
        let width = model.num("width") ?? (content[2] - content[0])
        let height = model.num("height") ?? (content[5] - content[1])
        draw("\(number(width)) × \(number(height))", at: NSPoint(x: rect.midX, y: rect.midY), color: .black)
    }
}

// MARK: - Text editing

/// A popover for editing HTML or text, committed with ⌘Return or Save.
@MainActor
enum TextEditPopover {
    private final class Controller: NSViewController {
        let code = CodeView()
        let done: (String) -> Void
        weak var popover: NSPopover?
        let singleLine: Bool

        init(text: String, language: CodeLanguage, title: String, singleLine: Bool, done: @escaping (String) -> Void) {
            self.done = done
            self.singleLine = singleLine
            super.init(nibName: nil, bundle: nil)
            let root = FlippedView(frame: NSRect(x: 0, y: 0, width: 440, height: singleLine ? 84 : 300))
            let label = Label.make(title, size: 11, weight: .semibold, color: .secondaryLabelColor)
            label.frame = NSRect(x: 12, y: 8, width: 300, height: 16)
            root.addSubview(label)
            code.frame = NSRect(x: 8, y: 28, width: 424, height: root.frame.height - 66)
            code.autoresizingMask = [.width, .height]
            code.textView.isEditable = true
            code.wraps = true
            code.show(text, language: language)
            code.textView.font = InspectorTheme.mono(11)
            code.wantsLayer = true
            code.layer?.borderWidth = 1
            code.layer?.borderColor = InspectorTheme.separator.cgColor
            code.layer?.cornerRadius = 4
            if singleLine { code.rulersVisible = false }
            root.addSubview(code)
            let save = NSButton.push("Save") { [weak self] in self?.commit() }
            save.keyEquivalent = singleLine ? "\r" : ""
            save.frame = NSRect(x: 440 - 88, y: root.frame.height - 34, width: 80, height: 28)
            root.addSubview(save)
            let hint = Label.make(singleLine ? "Return to save, Escape to cancel" : "⌘Return to save, Escape to cancel", size: 10.5,
                                  color: .tertiaryLabelColor)
            hint.frame = NSRect(x: 12, y: root.frame.height - 28, width: 260, height: 16)
            root.addSubview(hint)
            view = root
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidAppear() {
            super.viewDidAppear()
            view.window?.makeFirstResponder(code.textView)
            code.textView.selectAll(nil)
        }

        func commit() {
            done(code.text)
            popover?.close()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36, event.modifierFlags.contains(.command) { commit(); return }
            super.keyDown(with: event)
        }
    }

    private final class Monitor {
        var token: Any?
    }

    static func show(title: String, text: String, language: CodeLanguage, relativeTo rect: NSRect, of view: NSView,
                     singleLine: Bool = false, done: @escaping (String) -> Void) {
        let controller = Controller(text: text, language: language, title: title, singleLine: singleLine, done: done)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        controller.popover = popover
        // ⌘Return saves even while the text view has the keyboard.
        let monitor = Monitor()
        monitor.token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            guard let controller, controller.view.window?.isKeyWindow == true else { return event }
            if event.keyCode == 36, event.modifierFlags.contains(.command) || controller.singleLine {
                controller.commit()
                return nil
            }
            return event
        }
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { _ in
            if let token = monitor.token { NSEvent.removeMonitor(token) }
            monitor.token = nil
        }
        let visible = view.visibleRect
        let anchor = NSRect(x: max(rect.minX, visible.minX) + 40, y: rect.minY, width: 20, height: rect.height)
        popover.show(relativeTo: anchor, of: view, preferredEdge: .maxY)
    }
}
