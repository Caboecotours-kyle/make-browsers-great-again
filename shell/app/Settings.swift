import AppKit

enum SettingsPane: Int, CaseIterable {
    case general, privacy, developer, agents

    var title: String {
        switch self {
        case .general: "General"
        case .privacy: "Privacy"
        case .developer: "Developer"
        case .agents: "Agents"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .privacy: "hand.raised"
        case .developer: "hammer"
        case .agents: "sparkles"
        }
    }
}

/// Settings (⌘,): every preference in one window, a pane per topic, laid
/// out as macOS settings are (labels right-aligned against their controls).
@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()

    init(store: BrowserStore) {
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        for pane in SettingsPane.allCases {
            let controller = SettingsPaneController(pane: pane, store: store)
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        window.setFrameAutosaveName("Settings")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ pane: SettingsPane?) {
        if let pane { tabs.selectedTabViewItemIndex = pane.rawValue }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// One pane: a grid of labelled rows that reads its values when shown and
/// whenever the preferences change elsewhere (a menu, the command bar).
@MainActor
private final class SettingsPaneController: NSViewController {
    private let pane: SettingsPane
    private let store: BrowserStore
    private var refreshers: [() -> Void] = []

    init(pane: SettingsPane, store: BrowserStore) {
        self.pane = pane
        self.store = store
        super.init(nibName: nil, bundle: nil)
        title = pane.title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let rows: [[NSView]]
        switch pane {
        case .general: rows = generalRows()
        case .privacy: rows = privacyRows()
        case .developer: rows = developerRows()
        case .agents: rows = agentRows()
        }
        let grid = NSGridView(views: rows)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 150
        // Captions wrap at this width; a narrower column would cut them off.
        grid.column(at: 1).width = 340
        grid.rowAlignment = .firstBaseline
        // Captions sit closer under the control they explain.
        for (i, row) in rows.enumerated() where row.last?.identifier == Self.captionID {
            grid.row(at: i).topPadding = -4
        }
        let view = NSView()
        view.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -24),
            grid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            grid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
        self.view = view
        // Values first: a caption filled in later would be cut off.
        refresh()
        preferredContentSize = view.fittingSize
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: UserDefaults.didChangeNotification, object: nil)
        store.observe(self) { [weak self] change in
            if case .snapshot = change { self?.refresh() }
            if case .layout = change { self?.refresh() }
        }
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    @objc private func refresh() {
        for refresher in refreshers { refresher() }
    }

    // MARK: Panes

    private func generalRows() -> [[NSView]] {
        let layout = popUp(SidebarLayout.allCases.map(\.title)) { [store] i in store.setLayout(SidebarLayout.allCases[i]) }
        refreshers.append { [store] in layout.selectItem(at: SidebarLayout.allCases.firstIndex(of: store.layout) ?? 0) }

        let colour = popUp(TintStyle.allCases.map(\.title)) { i in
            UserDefaults.standard.set(TintStyle.allCases[i].rawValue, forKey: TintStyle.defaultsKey)
        }
        refreshers.append { colour.selectItem(at: TintStyle.allCases.firstIndex(of: TintStyle.saved) ?? 0) }
        let matchPage = checkbox("Take the colour of the page in front") { on in
            UserDefaults.standard.set(on, forKey: TintStyle.matchPageKey)
        }
        refreshers.append { matchPage.state = UserDefaults.standard.bool(forKey: TintStyle.matchPageKey) ? .on : .off }

        let intervals: [(String, UInt32)] = [("Never", 0), ("After 12 Hours", 12), ("After a Day", 24), ("After a Week", 168)]
        let archive = popUp(intervals.map(\.0)) { [store] i in store.setArchiveAfterHours(intervals[i].1) }
        refreshers.append { [store] in
            archive.selectItem(at: intervals.firstIndex { $0.1 == store.archiveAfterHours } ?? 0)
        }

        return [
            [label("Sidebar:"), layout],
            [label("Sidebar colour:"), colour],
            [NSGridCell.emptyContentView, matchPage],
            [label("Archive Today tabs:"), archive],
            [NSGridCell.emptyContentView, caption("Tabs in Today you haven't used for this long move to the archive. Pinned tabs and favourites stay.")],
        ]
    }

    private func privacyRows() -> [[NSView]] {
        let blockAds = checkbox("Block ads and trackers") { [store] on in store.setBlockAds(on) }
        refreshers.append { [store] in blockAds.state = store.blockAds ? .on : .off }
        let filters = NSButton.push("Edit My Filters…") { [store] in
            NSWorkspace.shared.open(URL(fileURLWithPath: store.core.userFiltersPath()))
        }
        let isolation = checkbox("Strict site isolation") { [store] on in store.setStrictSiteIsolation(on) }
        refreshers.append { [store] in isolation.state = store.strictSiteIsolation ? .on : .off }
        return [
            [label("Ad blocking:"), blockAds],
            [NSGridCell.emptyContentView, filters],
            [label("Processes:"), isolation],
            [NSGridCell.emptyContentView, caption("Every site gets its own process, as in desktop Chrome: the strongest protection against one site reading another's data, for about 30% more memory. Takes effect at next launch.")],
        ]
    }

    private func developerRows() -> [[NSView]] {
        let enabled = NSSwitch()
        enabled.controlSize = .small
        enabled.onAction { [weak enabled] in
            UserDefaults.standard.set(enabled?.state == .on, forKey: DeveloperSettings.enabledKey)
        }
        let everywhere = popUp(["Local sites", "Every site"]) { i in
            UserDefaults.standard.set(i == 1, forKey: DeveloperSettings.everywhereKey)
        }
        let collapses = checkbox("Shrink to the page's status when the pointer is away") { on in
            UserDefaults.standard.set(on, forKey: DeveloperSettings.collapsesKey)
        }
        let anchors = DevToolbarAnchor.allCases
        let position = NSSegmentedControl(labels: ["Left", "Centre", "Right"], trackingMode: .selectOne, target: nil, action: nil)
        position.onAction { [weak position] in
            guard let position else { return }
            UserDefaults.standard.set(anchors[position.selectedSegment].rawValue, forKey: DeveloperSettings.anchorKey)
        }
        let devTools = popUp(["Beside the page", "In a separate window"]) { i in
            UserDefaults.standard.set(i == 1, forKey: DeveloperSettings.devToolsInWindowKey)
        }
        refreshers.append { devTools.selectItem(at: DeveloperSettings.docksDevTools ? 0 : 1) }
        let dependents: [NSControl] = [everywhere, collapses, position]
        refreshers.append {
            let on = DeveloperSettings.enabled
            enabled.state = on ? .on : .off
            everywhere.selectItem(at: DeveloperSettings.everywhere ? 1 : 0)
            collapses.state = DeveloperSettings.collapses ? .on : .off
            position.selectedSegment = anchors.firstIndex(of: DeveloperSettings.anchor) ?? 1
            for control in dependents { control.isEnabled = on }
        }
        return [
            [label("Developer Mode:"), enabled],
            [NSGridCell.emptyContentView, caption("A toolbar floats over the top of the page: how it loaded, console errors, reload without the cache, element picking, dark mode and device previews, full-page screenshots and a QR code for your phone. The Develop menu appears too.")],
            [label("Show the toolbar on:"), everywhere],
            [NSGridCell.emptyContentView, caption("Local sites are localhost, .local and .test names, addresses on your network, and files. ⇧⌘D shows or hides it on any tab.")],
            [label("Toolbar:"), collapses],
            [label("Position:"), position],
            [NSGridCell.emptyContentView, caption("You can also drag the toolbar along the top of the page.")],
            [label("Developer tools open:"), devTools],
            [NSGridCell.emptyContentView, caption("Beside the page, each tab keeps its own; drag the edge to resize. ⌥⌘I opens and closes them.")],
        ]
    }

    private func agentRows() -> [[NSView]] {
        let enabled = NSSwitch()
        enabled.controlSize = .small
        enabled.onAction { [weak enabled] in
            UserDefaults.standard.set(enabled?.state == .on, forKey: AgentSettings.enabledKey)
        }
        let status = caption("")
        let install = NSButton.push("Install the mbga Command") {
            if let error = AgentSettings.installCommand() {
                status.stringValue = "Couldn't install it: \(error)"
            } else {
                status.stringValue = Self.installedNote
            }
        }
        let link = AgentSettings.commandLink.path
        let setup = NSTextField(wrappingLabelWithString: "claude mcp add mbga -- \(link) mcp")
        setup.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        setup.isSelectable = true
        setup.preferredMaxLayoutWidth = 340
        refreshers.append {
            enabled.state = AgentSettings.enabled ? .on : .off
            if status.stringValue.isEmpty || status.stringValue == Self.installedNote {
                status.stringValue = FileManager.default.fileExists(atPath: link) ? Self.installedNote
                    : "Puts mbga in ~/.local/bin, so any terminal or agent can run it."
            }
        }
        return [
            [label("Agent access:"), enabled],
            [NSGridCell.emptyContentView, caption("Agents on this Mac (Claude Code, MCP apps, your scripts) can open tabs, read pages, click and type, through the mbga command. They see pages as short outlines rather than screenshots, so it costs them few tokens. Only apps running as you can connect, and the page glows while an agent acts on it.")],
            [label("Command:"), install],
            [NSGridCell.emptyContentView, status],
            [label("MCP:"), setup],
            [NSGridCell.emptyContentView, caption("Adds MBGA to Claude Code as an MCP server. Other MCP apps: run \"mbga mcp\". Run \"mbga help\" for every command.")],
        ]
    }

    private static let installedNote = "Installed at ~/.local/bin/mbga. Run \"mbga help\" in a terminal to try it."

    // MARK: Controls

    private static let captionID = NSUserInterfaceItemIdentifier("caption")

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.alignment = .right
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.preferredMaxLayoutWidth = 340
        label.identifier = Self.captionID
        return label
    }

    private func checkbox(_ title: String, _ action: @escaping (Bool) -> Void) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.onAction { [weak button] in action(button?.state == .on) }
        return button
    }

    private func popUp(_ titles: [String], _ action: @escaping (Int) -> Void) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: titles)
        button.onAction { [weak button] in action(button?.indexOfSelectedItem ?? 0) }
        return button
    }
}
