import AppKit

/// The full sidebar: toolbar, address field, favorites, the active space's
/// list (swipeable between spaces), the mini player and the bottom bar.
/// One instance moves between the window and the floating peek card.
@MainActor
final class SidebarView: FlippedView {
    private let store: BrowserStore
    private let toolbar: SidebarToolbarView
    private let address: AddressPillView
    private let favorites: FavoritesGridView
    private let pager: SpacePagerView
    private let player: MiniPlayerView
    private let bottom: SidebarBottomBar

    init(store: BrowserStore) {
        self.store = store
        toolbar = SidebarToolbarView(store: store)
        address = AddressPillView(store: store)
        favorites = FavoritesGridView(store: store)
        pager = SpacePagerView(store: store)
        player = MiniPlayerView(store: store)
        bottom = SidebarBottomBar(store: store)
        super.init(frame: .zero)
        for view in [toolbar, address, favorites, pager, player, bottom] as [NSView] { addSubview(view) }
        player.isHidden = store.mediaTab == nil
        store.observe(self) { [weak self] change in self?.handle(change) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func handle(_ change: StoreChange) {
        switch change {
        case .snapshot:
            favorites.update()
            pager.update(animation: store.snapshotAnimation)
            bottom.update()
            address.update()
            updatePlayer()
            needsLayout = true
        case .nav:
            toolbar.update()
            address.update()
        case .blocked:
            address.update()
        case .media:
            updatePlayer()
            pager.refreshDecorations()
        case .cleanup, .renaming:
            pager.refreshDecorations()
        case .drag:
            // Empty favorites open a drop target while something is dragged.
            favorites.update()
            pager.refreshDecorations()
            needsLayout = true
            Motion.animate(Motion.quick) { layoutSubtreeIfNeeded() }
        default:
            break
        }
    }

    private func updatePlayer() {
        let media = store.mediaTab
        player.update(media)
        let visible = media != nil
        guard visible == player.isHidden else { return }
        // The player rises from the bottom bar.
        player.isHidden = false
        player.alphaValue = visible ? 0 : 1
        Motion.animate(Motion.settle) {
            player.animator().alphaValue = visible ? 1 : 0
            needsLayout = true
            layoutSubtreeIfNeeded()
        } completion: { [weak self] in
            guard let self else { return }
            player.isHidden = store.mediaTab == nil
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let width = bounds.width - 20
        var y: CGFloat = 6
        toolbar.frame = NSRect(x: 10, y: y, width: width, height: 30)
        y += 30 + 10
        address.frame = NSRect(x: 10, y: y, width: width, height: 34)
        y += 34 + 10
        let favoritesHeight = favorites.preferredHeight(width: width)
        favorites.frame = NSRect(x: 10, y: y, width: width, height: favoritesHeight)
        if favoritesHeight > 0 { y += favoritesHeight + 10 }
        let bottomY = bounds.height - 8 - 28
        bottom.frame = NSRect(x: 10, y: bottomY, width: width, height: 28)
        var listBottom = bottomY - 10
        if store.mediaTab != nil || !player.isHidden {
            player.frame = NSRect(x: 10, y: listBottom - 46, width: width, height: 46)
            listBottom -= 46 + 10
        }
        pager.frame = NSRect(x: 10, y: y, width: width, height: max(listBottom - y, 0))
        // Two-finger swipes anywhere in the sidebar switch spaces.
        if let content = window?.contentView {
            store.pager.sidebarFrame = convert(bounds, to: content)
        }
    }
}

// MARK: - Toolbar

private final class SidebarToolbarView: WindowDragView {
    private let store: BrowserStore
    private let toggle: SymbolButton
    private let back: SymbolButton
    private let forward: SymbolButton
    private let reload: SymbolButton

    init(store: BrowserStore) {
        self.store = store
        toggle = SymbolButton("sidebar.left") { store.toggleSidebar() }
        back = SymbolButton("arrow.left") { store.goBack() }
        forward = SymbolButton("arrow.right") { store.goForward() }
        reload = SymbolButton("arrow.clockwise") { store.reloadOrStop() }
        super.init(frame: .zero)
        toggle.toolTip = "Focus Mode  ⌘S"
        for view in [toggle, back, forward, reload] { addSubview(view) }
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update() {
        back.isEnabled = store.nav.canGoBack
        forward.isEnabled = store.nav.canGoForward
        reload.setSymbol(store.nav.isLoading ? "xmark" : "arrow.clockwise")
        reload.isEnabled = store.visibleTabID != nil
    }

    override func layout() {
        super.layout()
        // Room for the window's traffic lights.
        toggle.frame = NSRect(x: 66, y: 3, width: 28, height: 24)
        reload.frame = NSRect(x: bounds.width - 28, y: 3, width: 28, height: 24)
        forward.frame = NSRect(x: bounds.width - 58, y: 3, width: 28, height: 24)
        back.frame = NSRect(x: bounds.width - 88, y: 3, width: 28, height: 24)
    }
}

// MARK: - Address field

/// The visible page's site; click to edit the address or search. Also shows
/// loading and how many ads and trackers were blocked.
private final class AddressPillView: HoverView {
    private let store: BrowserStore
    private let fill = FillLayer()
    private let lock = NSImageView()
    private let host = Label.make()
    private let spinner = NSProgressIndicator()
    private let shield = NSImageView()
    private let blocked = Label.make(size: 11, weight: .medium)
    private var shownCount = 0

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: .zero)
        fill.cornerRadius = 10
        layer?.addSublayer(fill)
        lock.image = .symbol("lock.fill", size: 10, weight: .regular)
        lock.contentTintColor = .labelColor
        lock.alphaValue = 0.5
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        shield.image = .symbol("shield.lefthalf.filled", size: 10, weight: .regular)
        shield.contentTintColor = .labelColor
        shield.alphaValue = 0.5
        blocked.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        blocked.alphaValue = 0.5
        blocked.wantsLayer = true
        for view in [lock, host, spinner, shield, blocked] as [NSView] { addSubview(view) }
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update() {
        let tab = store.visibleTab
        lock.isHidden = !(tab?.url.hasPrefix("https://") ?? false)
        host.stringValue = tab?.host ?? "Search or Enter URL…"
        host.alphaValue = tab == nil ? 0.5 : 0.85
        if store.nav.isLoading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        let count = tab == nil ? 0 : store.visibleBlockedCount
        shield.isHidden = count == 0
        blocked.isHidden = count == 0
        if count != shownCount {
            // The count rolls up as more is blocked.
            if count > shownCount, !Motion.reduced, let layer = blocked.layer {
                let roll = CATransition()
                roll.type = .push
                roll.subtype = .fromTop
                roll.duration = Motion.quick.duration
                roll.timingFunction = Motion.quick.timing
                layer.add(roll, forKey: "roll")
            }
            shownCount = count
            blocked.stringValue = "\(count)"
            toolTip = count > 0 ? "\(count) ads and trackers blocked on this page" : nil
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        CATransaction.commit()
        var x: CGFloat = 10
        if !lock.isHidden {
            lock.frame = NSRect(x: x, y: bounds.midY - 6, width: 10, height: 12)
            x += 16
        }
        var trailing = bounds.width - 10
        if !blocked.isHidden {
            let width = blocked.textWidth
            blocked.frame = NSRect(x: trailing - width, y: bounds.midY - 7, width: width, height: 14)
            shield.frame = NSRect(x: trailing - width - 14, y: bounds.midY - 6, width: 11, height: 12)
            trailing -= width + 20
        }
        if store.nav.isLoading {
            spinner.frame = NSRect(x: trailing - 12, y: bounds.midY - 6, width: 12, height: 12)
            trailing -= 18
        }
        host.frame = NSRect(x: x, y: bounds.midY - 8, width: max(trailing - x, 0), height: 16)
    }

    override func updateLayer() {
        fill.paint(fill: hovering ? Theme.controlHoverFill : Theme.controlFill, in: effectiveAppearance)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        store.commandBar = store.visibleTab == nil ? .newTab : .editCurrent
    }

    override func mouseDown(with event: NSEvent) {}
}

// MARK: - Favorites

/// Favorites belong to the profile, so every space using it shows the same
/// grid: four columns of tiles, reorderable by dragging.
private final class FavoritesGridView: FlippedView {
    private let store: BrowserStore
    private var tiles: [FavoriteTileView] = []
    private let caret = CALayer()
    private let hint = DropHintCellView()
    private var dropIndex: Int?
    private let columns = 4
    private let tileHeight: CGFloat = 42
    private let spacing: CGFloat = 8

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        caret.cornerRadius = 1.5
        caret.isHidden = true
        layer?.addSublayer(caret)
        hint.configure("Drop to add to Favorites", visible: true)
        addSubview(hint)
        registerForDraggedTypes([.sidebarItem, .URL])
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var space: SpaceInfo { store.activeSpace }

    func preferredHeight(width: CGFloat) -> CGFloat {
        let count = space.favorites.count
        if count == 0 { return store.isDragging ? 34 : 0 }
        let rowCount = (count + columns - 1) / columns
        return CGFloat(rowCount) * tileHeight + CGFloat(rowCount - 1) * spacing
    }

    func update() {
        let favorites = space.favorites
        while tiles.count > favorites.count { tiles.removeLast().removeFromSuperview() }
        while tiles.count < favorites.count {
            let tile = FavoriteTileView(store: store)
            tiles.append(tile)
            addSubview(tile)
        }
        for (tile, tab) in zip(tiles, favorites) { tile.configure(tab, space: space) }
        hint.isHidden = !(favorites.isEmpty && store.isDragging)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        hint.frame = bounds
        let width = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        for (i, tile) in tiles.enumerated() {
            let row = i / columns, column = i % columns
            tile.frame = NSRect(x: CGFloat(column) * (width + spacing), y: CGFloat(row) * (tileHeight + spacing),
                                width: width, height: tileHeight)
        }
    }

    // Dropping a tab here adds it as a favorite at the caret.

    private func insertionIndex(at point: NSPoint) -> Int {
        guard !tiles.isEmpty else { return 0 }
        for (i, tile) in tiles.enumerated() where point.y <= tile.frame.maxY + spacing / 2 {
            if point.x < tile.frame.midX { return i }
            if i % columns == columns - 1 || i == tiles.count - 1 { return i + 1 }
        }
        return tiles.count
    }

    private func showCaret(at index: Int?) {
        guard index != dropIndex else { return }
        dropIndex = index
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let index, !tiles.isEmpty else {
            caret.isHidden = true
            return
        }
        let anchor = index < tiles.count ? tiles[index].frame : tiles[index - 1].frame
        let x = index < tiles.count ? anchor.minX - spacing / 2 : anchor.maxX + spacing / 2
        caret.backgroundColor = NSColor.controlAccentColor.cgColor
        caret.frame = NSRect(x: x - 1.5, y: anchor.minY + 6, width: 3, height: anchor.height - 12)
        caret.isHidden = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        showCaret(at: insertionIndex(at: convert(sender.draggingLocation, from: nil)))
        return sender.draggingPasteboard.string(forType: .sidebarItem) != nil ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { showCaret(at: nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let index = insertionIndex(at: convert(sender.draggingLocation, from: nil))
        showCaret(at: nil)
        let target = DropTarget.favorites(profileId: space.profileId)
        if let id = sender.draggingPasteboard.string(forType: .sidebarItem).flatMap(UInt64.init) {
            guard store.core.tab(id: id) != nil else { return false }
            store.drop(id, on: target, index: index)
            return true
        }
        guard let url = sender.draggingPasteboard.string(forType: .URL) else { return false }
        store.dropURL(url, on: target, index: index)
        return true
    }
}

/// A favorite: its icon on a tile that, when selected, lights up in the
/// site's own color, as in Dia.
private final class FavoriteTileView: HoverView, NSDraggingSource {
    private let store: BrowserStore
    private let fill = FillLayer()
    private let brand = FillLayer()
    private let icon = NSImageView()
    private var tab: TabInfo?
    private var space: SpaceInfo?
    private var downEvent: NSEvent?
    private var dragging = false

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: .zero)
        fill.cornerRadius = 10
        brand.cornerRadius = 10
        layer?.addSublayer(fill)
        layer?.addSublayer(brand)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 3.6
        icon.layer?.cornerCurve = .continuous
        icon.layer?.masksToBounds = true
        icon.contentTintColor = .secondaryLabelColor
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ tab: TabInfo, space: SpaceInfo) {
        self.tab = tab
        self.space = space
        icon.image = FaviconCache.shared.image(for: tab)
        icon.alphaValue = tab.live || space.activeTab == tab.id ? 1 : 0.6
        toolTip = tab.displayTitle
        needsDisplay = true
        updateLayer()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        brand.frame = bounds
        CATransaction.commit()
        icon.frame = NSRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
    }

    override func updateLayer() {
        guard let tab, let space else { return }
        let active = space.activeTab == tab.id
        fill.paint(fill: active ? Theme.selectedFill : hovering ? Theme.controlHoverFill : Theme.controlFill,
                   shadow: active ? Theme.selectedShadow : nil, in: effectiveAppearance)
        let color = active ? tab.faviconPath.flatMap { FaviconCache.shared.brandColor(atPath: $0) } : nil
        let dark = effectiveAppearance.isDark
        brand.paint(fill: color.map { $0.nsColor.withAlphaComponent(dark ? 0.32 : 0.2) },
                    border: color.map { $0.nsColor.withAlphaComponent(dark ? 0.6 : 0.45) }, in: effectiveAppearance)
    }

    override func mouseDown(with event: NSEvent) {
        downEvent = event
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let downEvent, let tab else { return }
        let start = downEvent.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        dragging = true
        let item = NSPasteboardItem()
        item.setString(String(tab.id), forType: .sidebarItem)
        item.setString(tab.url, forType: .URL)
        item.setString(tab.url, forType: .string)
        let image = DragImages.pill(for: tab)
        let point = convert(event.locationInWindow, from: nil)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                                         width: image.size.width, height: image.size.height), contents: image)
        store.beginDrag(tab.id)
        let session = beginDraggingSession(with: [dragItem], event: downEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { downEvent = nil }
        guard !dragging, let tab, let space, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        store.select(tab.id, in: space.id)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let tab, let space else { return nil }
        return Menus.tab(tab, in: space, store: store)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        store.dragMoved(to: screenPoint)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        store.endDrag(at: screenPoint, accepted: operation != [])
    }
}

// MARK: - Space pager

/// The spaces' lists side by side, offset by the pager's position, so a
/// two-finger swipe slides them with the fingers. Only the pages near the
/// current position exist.
private final class SpacePagerView: FlippedView {
    private let store: BrowserStore
    private var pages: [UInt64: SpacePageView] = [:]
    private let gap: CGFloat = 24
    /// Pages also kept while animating from this position.
    private var animatingFrom: CGFloat?

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        // Neighbouring spaces wait just past the edge; never show them over
        // the page.
        layer?.masksToBounds = true
        store.pager.observe(self) { [weak self] animated in self?.positionChanged(animated: animated) }
        update(animation: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var stride: CGFloat { bounds.width + gap }

    func update(animation: Motion.Curve?) {
        let spaces = store.snapshot.spaces
        for (id, page) in pages where !spaces.contains(where: { $0.id == id }) {
            page.removeFromSuperview()
            pages[id] = nil
        }
        for space in spaces {
            pages[space.id]?.update(space, animation: animation)
        }
        ensurePages()
        layoutPages()
    }

    func refreshDecorations() {
        for page in pages.values { page.refreshDecorations() }
    }

    private func wanted(_ index: Int) -> Bool {
        let position = store.pager.position
        if abs(CGFloat(index) - position) < 1.2 { return true }
        if let from = animatingFrom {
            let low = min(from, position) - 1.2, high = max(from, position) + 1.2
            return CGFloat(index) > low && CGFloat(index) < high
        }
        return false
    }

    private func ensurePages() {
        for (index, space) in store.snapshot.spaces.enumerated() {
            if wanted(index) {
                if pages[space.id] == nil {
                    let page = SpacePageView(space: space, store: store)
                    pages[space.id] = page
                    addSubview(page)
                }
            } else if let page = pages.removeValue(forKey: space.id) {
                page.removeFromSuperview()
            }
        }
    }

    private func layoutPages() {
        let position = store.pager.position
        for (index, space) in store.snapshot.spaces.enumerated() {
            pages[space.id]?.frame = NSRect(x: (CGFloat(index) - position) * stride, y: 0,
                                            width: bounds.width, height: bounds.height)
        }
    }

    private func positionChanged(animated: Bool) {
        if animated {
            animatingFrom = currentVisualPosition()
            ensurePages()
            Motion.animate(Motion.glide) {
                let position = store.pager.position
                for (index, space) in store.snapshot.spaces.enumerated() {
                    pages[space.id]?.animator().frame = NSRect(x: (CGFloat(index) - position) * stride, y: 0,
                                                               width: bounds.width, height: bounds.height)
                }
            } completion: { [weak self] in
                self?.animatingFrom = nil
                self?.ensurePages()
            }
        } else {
            ensurePages()
            layoutPages()
        }
    }

    /// Where the pages are drawn right now (mid-animation included).
    private func currentVisualPosition() -> CGFloat {
        for (index, space) in store.snapshot.spaces.enumerated() {
            if let page = pages[space.id] {
                let x = page.layer?.presentation()?.frame.minX ?? page.frame.minX
                return CGFloat(index) - x / max(stride, 1)
            }
        }
        return store.pager.position
    }

    override func layout() {
        super.layout()
        store.pager.pageWidth = stride
        layoutPages()
    }
}

// MARK: - Bottom bar

/// Downloads, the space switcher (only once there is a second space) and
/// the + menu.
private final class SidebarBottomBar: FlippedView {
    private let store: BrowserStore
    private let downloads: SymbolButton
    private let add: SymbolButton
    private var dots: [SpaceDotView] = []

    init(store: BrowserStore) {
        self.store = store
        downloads = SymbolButton("arrow.down.circle") {
            if let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                NSWorkspace.shared.open(folder)
            }
        }
        add = SymbolButton("plus")
        super.init(frame: .zero)
        downloads.toolTip = "Downloads"
        add.action = { [weak add] in
            guard let add else { return }
            Menus.newItem(store: store).popUp(positioning: nil, at: NSPoint(x: 0, y: add.bounds.height + 4), in: add)
        }
        addSubview(downloads)
        addSubview(add)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update() {
        let spaces = store.snapshot.spaces
        // Most people use one space (5.5% of Arc's daily users used several),
        // so the switcher only appears once there is a second.
        let shown = spaces.count > 1 ? spaces : []
        while dots.count > shown.count { dots.removeLast().removeFromSuperview() }
        while dots.count < shown.count {
            let dot = SpaceDotView(store: store)
            dots.append(dot)
            addSubview(dot)
        }
        for (dot, space) in zip(dots, shown) { dot.configure(space, active: space.id == store.snapshot.activeSpace) }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        downloads.frame = NSRect(x: 0, y: 2, width: 28, height: 24)
        add.frame = NSRect(x: bounds.width - 28, y: 2, width: 28, height: 24)
        guard !dots.isEmpty else { return }
        // Icons shrink, then turn into dots, so many spaces never make the
        // bar (and with it the sidebar) wider.
        let available = bounds.width - 64
        let size = min(24, (available - CGFloat(dots.count - 1) * 2) / CGFloat(dots.count))
        let icons = size >= 16
        let width = CGFloat(dots.count) * size + CGFloat(dots.count - 1) * 2
        var x = (bounds.width - width) / 2
        for dot in dots {
            dot.showsIcon = icons
            dot.frame = NSRect(x: x, y: 2, width: max(size, 6), height: 24)
            x += size + 2
        }
    }
}

/// A space's emoji (or a dot); click to switch, drop a tab to move it there.
private final class SpaceDotView: HoverView {
    private let store: BrowserStore
    private let fill = FillLayer()
    private let label = Label.make(size: 13)
    private let dot = CALayer()
    private var space: SpaceInfo?
    private var active = false
    private var dropping = false
    var showsIcon = true {
        didSet { if showsIcon != oldValue { needsLayout = true } }
    }

    init(store: BrowserStore) {
        self.store = store
        super.init(frame: .zero)
        fill.cornerRadius = 6
        layer?.addSublayer(fill)
        dot.cornerRadius = 3
        layer?.addSublayer(dot)
        label.alignment = .center
        addSubview(label)
        registerForDraggedTypes([.sidebarItem, .URL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ space: SpaceInfo, active: Bool) {
        self.space = space
        label.stringValue = space.icon
        toolTip = space.name
        if active != self.active {
            self.active = active
            Motion.animate(Motion.quick) { animator().alphaValue = active ? 1 : 0.45 }
        } else {
            alphaValue = active ? 1 : 0.45
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let icon = showsIcon && !(space?.icon.isEmpty ?? true)
        label.isHidden = !icon
        label.font = Theme.font(min(bounds.width, 24) * 0.54)
        label.frame = NSRect(x: 0, y: bounds.midY - 9, width: bounds.width, height: 18)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        dot.isHidden = icon
        dot.frame = NSRect(x: bounds.midX - 3, y: bounds.midY - 3, width: 6, height: 6)
        CATransaction.commit()
    }

    override func updateLayer() {
        fill.paint(fill: dropping ? Theme.controlHoverFill : hovering ? Theme.hoverFill : nil, in: effectiveAppearance)
        effectiveAppearance.performAsCurrentDrawingAppearance { dot.backgroundColor = NSColor.labelColor.cgColor }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if let space, bounds.contains(convert(event.locationInWindow, from: nil)) { store.activateSpace(space.id) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let space else { return nil }
        let menu = NSMenu()
        menu.add("Edit Space…") { [store] in store.spaceEditor = SpaceEditorRequest(spaceID: space.id) }
        return menu
    }

    private func setDropping(_ value: Bool) {
        dropping = value
        FillLayer.animated(Motion.quick) { updateLayer() }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setDropping(true)
        return sender.draggingPasteboard.string(forType: .sidebarItem) != nil ? .move : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { setDropping(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropping(false)
        guard let space else { return false }
        let target = DropTarget.today(spaceId: space.id)
        if let id = sender.draggingPasteboard.string(forType: .sidebarItem).flatMap(UInt64.init) {
            guard store.core.tab(id: id) != nil else { return false }
            store.drop(id, on: target, index: 0)
            return true
        }
        guard let url = sender.draggingPasteboard.string(forType: .URL) else { return false }
        store.dropURL(url, on: target, index: 0)
        return true
    }
}
